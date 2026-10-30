import AppKit
import NativeLaunchpad

@MainActor
final class AppDelegate: NativeHost {
    private var hotKeyManager: GlobalHotKeyManager?
    private var applicationDirectoryMonitor: ApplicationDirectoryMonitor?
    private var runningApplicationMonitor: RunningApplicationMonitor?
    private var applicationReloadTask: Task<Void, Never>?
    private var controllerNavigation: GameControllerNavigation?
    private var controllerVisibility: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var settingsController: SettingsWindowController?
    private var quickSearch: QuickSearchController?

    override func applicationDidFinishLaunching(_ notification: Notification) {
        if !verifying {
            showOnlyOnMainScreen = DisplaySettings.load().showOnlyOnMainScreen
            SettingsWindowController.restoreApplicationIcon()
            if Bundle.main.bundleURL.pathExtension == "app" {
                do {
                    runningApplicationMonitor = try RunningApplicationMonitor(url: Bundle.main.bundleURL) {
                        NSApp.terminate(nil)
                    }
                } catch {
                    DebugLog.write("running application monitor failed: \(error.localizedDescription)")
                    NSApp.terminate(nil)
                    return
                }
            }
        }

        super.applicationDidFinishLaunching(notification)
        guard !verifying else { return }
        let navigation = GameControllerNavigation { [weak self] keyCode, pressed, repeated in
            self?.handleControllerKey(keyCode, pressed: pressed, repeated: repeated)
        }
        controllerNavigation = navigation
        navigation.start()
        controllerVisibility = observe(\.wantsLauncherVisible, options: [.initial, .new]) { [weak navigation] host, _ in
            MainActor.assumeIsolated {
                navigation?.setActive(host.wantsLauncherVisible)
            }
        }
        do {
            hotKeyManager = try GlobalHotKeyManager(
                onToggle: { [weak self] in self?.handleLauncherShortcut() },
                onSearch: { [weak self] in self?.toggleQuickSearch() }
            )
        } catch {
            var settings = ShortcutSettings.loadSearch()
            settings.isEnabled = false
            settings.saveSearch()
            NSAlert(error: error).runModal()
        }
        if let hotKeyManager {
            do { try hotKeyManager.applyCurrentSettings() }
            catch { NSAlert(error: error).runModal() }
            var searchSettings = ShortcutSettings.loadSearch()
            do { try hotKeyManager.applySearchSettings(searchSettings) }
            catch {
                searchSettings.isEnabled = false
                searchSettings.saveSearch()
                NSAlert(error: error).runModal()
            }
        }
        itemObservation = observe(\.items, options: [.new]) { [weak self] host, _ in
            MainActor.assumeIsolated { self?.quickSearch?.updateItems(host.items) }
        }
        iconDidLoad = { [weak self] url in
            MainActor.assumeIsolated { self?.quickSearch?.refreshIcon(for: url) }
        }
        applicationDirectoryMonitor = ApplicationDirectoryMonitor(urls: ApplicationScanner.applicationRoots()) { [weak self] in
            Task { @MainActor in self?.scheduleApplicationReload() }
        }
        applicationDirectoryMonitor?.start()
    }

    override func applicationWillTerminate(_ notification: Notification) {
        itemObservation?.invalidate()
        iconDidLoad = nil
        quickSearch?.hide()
        settingsController?.close()
        controllerVisibility?.invalidate()
        controllerNavigation?.stop()
        controllerNavigation = nil
        applicationReloadTask?.cancel()
        applicationDirectoryMonitor?.stop()
        runningApplicationMonitor?.stop()
        hotKeyManager?.stop()
        super.applicationWillTerminate(notification)
    }

    override func showLauncher() {
        quickSearch?.hide()
        settingsController?.window?.orderOut(nil)
        super.showLauncher()
    }

    @objc func openSettings(_ sender: Any?) {
        guard !verifying else { return }
        hideLauncherImmediately()
        quickSearch?.hide()
        if settingsController == nil {
            settingsController = SettingsWindowController(
                onBackgroundChange: { [weak self] in self?.refreshBackground() },
                onAnimationsChange: { [weak self] in self?.applyAnimationSettings() },
                onSearchChange: { [weak self] enabled, keyCode, modifiers in
                    if !enabled {
                        try self?.hotKeyManager?.applySearchSettings(ShortcutSettings(isEnabled: false, keyCode: keyCode, modifiers: modifiers))
                        self?.quickSearch?.hide()
                        return
                    }
                    guard let manager = self?.hotKeyManager else {
                        throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [
                            NSLocalizedDescriptionKey: "全局快捷键服务不可用，请重新启动 Launcheer 后再试。"
                        ])
                    }
                    try manager.applySearchSettings(ShortcutSettings(isEnabled: enabled, keyCode: keyCode, modifiers: modifiers))
                }
            )
        }
        settingsController?.show()
    }

    private func toggleQuickSearch() {
        let settings = ShortcutSettings.loadSearch()
        guard settings.isEnabled else { return }
        let label = UserDefaults.standard.string(forKey: "search.keyLabel") ?? settings.keyLabel
        if settingsController?.captureRegisteredShortcut(keyCode: settings.keyCode, modifiers: settings.modifiers, label: label) == true { return }
        hideLauncherImmediately()
        settingsController?.window?.orderOut(nil)
        if quickSearch == nil {
            quickSearch = QuickSearchController(items: items, iconProvider: { [weak self] url in self?.icon(forItem: url) })
        }
        quickSearch?.toggle()
    }

    private func handleLauncherShortcut() {
        let settings = ShortcutSettings.load()
        if settingsController?.captureRegisteredShortcut(keyCode: settings.keyCode, modifiers: settings.modifiers, label: settings.keyLabel) == true { return }
        toggleLauncher()
    }

    private func scheduleApplicationReload() {
        applicationReloadTask?.cancel()
        applicationReloadTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            let items = await Task.detached(priority: .utility) {
                ApplicationScanner.scan().map(\.url)
            }.value
            guard !Task.isCancelled else { return }
            self?.reloadItems(items)
        }
    }
}

@main
@MainActor
private enum LauncheerApp {
    private static var delegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.contains("--check-compatibility") {
            var nativeError: NSError?
            guard NativeInitializeDock(&nativeError) else {
                FileHandle.standardError.write(Data("\(nativeError!.localizedDescription)\n".utf8))
                exit(1)
            }
            print("Native Launchpad compatibility check passed on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let host = AppDelegate()
        let verifyAll = CommandLine.arguments.contains("--verify-all")
        host.verifying = verifyAll || CommandLine.arguments.contains("--verify")
        host.automatedVerification = host.verifying
        let roots = host.verifying && !verifyAll
            ? [URL(fileURLWithPath: "/System/Applications")]
            : ApplicationScanner.applicationRoots()
        let scanStarted = ProcessInfo.processInfo.systemUptime
        host.items = ApplicationScanner.scan(roots: roots).map(\.url)
        NSLog("Application scan: %.1f ms; %ld apps", (ProcessInfo.processInfo.systemUptime - scanStarted) * 1000, host.items.count)
        delegate = host
        application.delegate = host

        let menu = NSMenu()
        let item = NSMenuItem()
        let applicationMenu = NSMenu()
        let about = NSMenuItem(title: "关于 Launcheer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = application
        applicationMenu.addItem(about)
        applicationMenu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(NativeHost.showSettings(_:)), keyEquivalent: ",")
        settings.target = host
        applicationMenu.addItem(settings)
        let authorizeWallpaper = NSMenuItem(title: "允许读取当前壁纸…", action: #selector(NativeHost.authorizeDesktopImage(_:)), keyEquivalent: "")
        authorizeWallpaper.target = host
        applicationMenu.addItem(authorizeWallpaper)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "退出 Launcheer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = applicationMenu
        menu.addItem(item)
        application.mainMenu = menu
        application.run()
    }
}
