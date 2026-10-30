import AppKit
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
    private let onBackgroundChange: () -> Void
    private let onAnimationsChange: () -> Void
    private let onSearchChange: (Bool, UInt32, UInt32) throws -> Void
    private var backgroundPreview: NSImageView!
    private var iconPreview: NSImageView!
    private var backgroundLabel: NSTextField!
    private var animationCheckbox: NSButton!
    private var searchCheckbox: NSButton!
    private var shortcutRecorder: SettingsShortcutRecorder!
    private var imageButtons: [NSButton] = []
    private var previewGeneration = 0
    private static var iconGeneration = 0

    init(onBackgroundChange: @escaping () -> Void, onAnimationsChange: @escaping () -> Void,
         onSearchChange: @escaping (Bool, UInt32, UInt32) throws -> Void) {
        self.onBackgroundChange = onBackgroundChange
        self.onAnimationsChange = onAnimationsChange
        self.onSearchChange = onSearchChange
        super.init(window: nil)
        buildWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Launcheer 设置"
        window.isReleasedWhenClosed = false
        let content = NSView()
        window.contentView = content
        let title = NSTextField(labelWithString: "Launcheer")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        let versionLabel = NSTextField(labelWithString: "版本 \(version)（Build \(build)）")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        let about = NSButton(title: "关于…", target: NSApp, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        let header = column([row([title, about]), versionLabel])
        header.spacing = 4

        backgroundPreview = preview(width: 154, height: 88)
        backgroundLabel = NSTextField(labelWithString: "")
        let backgroundButton = button("选择图片…", action: #selector(chooseBackground(_:)))
        let desktopButton = button("跟随桌面", action: #selector(followDesktop(_:)))
        let background = column([heading("背景"), row([backgroundPreview, column([backgroundLabel, row([backgroundButton, desktopButton])])])])

        animationCheckbox = NSButton(checkboxWithTitle: "关闭过渡动画", target: self, action: #selector(changeAnimations(_:)))
        iconPreview = preview(width: 64, height: 64)
        let iconButton = button("选择图标…", action: #selector(chooseIcon(_:)))
        let restoreButton = button("恢复原图标", action: #selector(restoreIcon(_:)))
        let icon = column([heading("应用图标（Dock）"), row([iconPreview, column([
            NSTextField(labelWithString: "更改 Launcheer 在 Dock 中显示的图标。"), row([iconButton, restoreButton])
        ])])])
        imageButtons = [backgroundButton, desktopButton, iconButton, restoreButton]

        searchCheckbox = NSButton(checkboxWithTitle: "启用全局应用搜索", target: self, action: #selector(changeSearch(_:)))
        shortcutRecorder = SettingsShortcutRecorder()
        shortcutRecorder.onRecord = { [weak self] code, modifiers, label in
            guard let self else { return }
            applySearch(enabled: searchCheckbox.state == .on, code: code, modifiers: modifiers, label: label)
        }
        let help = NSTextField(wrappingLabelWithString: "点击快捷键按钮录制，需包含 ⌘、⌥ 或 ⌃，Esc 取消。\n快捷键唤出搜索框，↑↓ 选择，回车启动。若组合已被占用，会保留原快捷键。")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        let search = column([heading("快捷搜索"), searchCheckbox, row([NSTextField(labelWithString: "全局快捷键"), shortcutRecorder]), help])
        let stack = column([header, background, separator(), animationCheckbox, separator(), icon, separator(), search])
        stack.spacing = 17
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            background.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.widthAnchor.constraint(equalTo: stack.widthAnchor),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            help.widthAnchor.constraint(equalTo: search.widthAnchor)
        ])
        for separator in stack.arrangedSubviews where separator is NSBox {
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        self.window = window
        window.center()
    }

    func show() {
        refreshControls()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func captureRegisteredShortcut(keyCode: UInt32, modifiers: UInt32, label: String) -> Bool {
        return shortcutRecorder.acceptRegisteredShortcut(keyCode: keyCode, modifiers: modifiers, label: label)
    }

    static func restoreApplicationIcon() {
        guard let path = UserDefaults.standard.string(forKey: "appearance.customIconPath") else { return }
        iconGeneration += 1
        let generation = iconGeneration
        Task {
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Data(contentsOf: URL(fileURLWithPath: path))
                }.value
                guard generation == iconGeneration else { return }
                guard let image = NSImage(data: data) else { throw SettingsImageFiles.invalidImage }
                NSApp.applicationIconImage = image
            } catch {
                DebugLog.write("custom application icon unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func refreshControls(reloadImages: Bool = true) {
        let defaults = UserDefaults.standard
        animationCheckbox.state = defaults.bool(forKey: "animations.disabled") ? .on : .off
        searchCheckbox.state = defaults.bool(forKey: "search.isEnabled") ? .on : .off
        shortcutRecorder.cancelRecording()
        shortcutRecorder.title = storedShortcut().2
        shortcutRecorder.toolTip = "点击录制新的快捷键"
        backgroundLabel.stringValue = defaults.string(forKey: "background.customImagePath") == nil ? "跟随当前桌面壁纸" : "自定义背景已启用"
        guard reloadImages else { return }
        backgroundPreview.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "背景")
        iconPreview.image = NSApp.applicationIconImage
        previewGeneration += 1
        let generation = previewGeneration
        for (key, imageView) in [("background.customImagePath", backgroundPreview!), ("appearance.customIconPath", iconPreview!)] {
            guard let path = defaults.string(forKey: key) else { continue }
            Task { [weak self, weak imageView] in
                do {
                    let data = try await Task.detached(priority: .utility) {
                        try SettingsImageFiles.preview(at: URL(fileURLWithPath: path), pixels: 320)
                    }.value
                    guard let self, generation == previewGeneration else { return }
                    imageView?.image = NSImage(data: data)
                } catch {
                    DebugLog.write("settings image preview unavailable: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func changeAnimations(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "animations.disabled")
        onAnimationsChange()
    }

    @objc private func changeSearch(_ sender: NSControl) {
        let (code, modifiers, label) = storedShortcut()
        applySearch(enabled: searchCheckbox.state == .on, code: code, modifiers: modifiers, label: label)
    }

    private func applySearch(enabled: Bool, code: UInt32, modifiers: UInt32, label: String) {
        do {
            try onSearchChange(enabled, code, modifiers)
            let defaults = UserDefaults.standard
            defaults.set(enabled, forKey: "search.isEnabled")
            defaults.set(Int(code), forKey: "search.keyCode")
            defaults.set(Int(modifiers), forKey: "search.modifiers")
            defaults.set(label, forKey: "search.keyLabel")
            refreshControls(reloadImages: false)
        } catch {
            refreshControls(reloadImages: false)
            NSAlert(error: error).runModal()
        }
    }

    private func storedShortcut() -> (UInt32, UInt32, String) {
        let settings = ShortcutSettings.loadSearch()
        return (settings.keyCode, settings.modifiers, UserDefaults.standard.string(forKey: "search.keyLabel") ?? settings.keyLabel)
    }

    @objc private func chooseBackground(_ sender: NSButton) { chooseImage(forIcon: false) }
    @objc private func chooseIcon(_ sender: NSButton) { chooseImage(forIcon: true) }

    private func chooseImage(forIcon: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "使用图片"
        guard panel.runModal() == .OK else { return }
        let url = panel.url!
        let directory = SettingsImageFiles.directory
        previewGeneration += 1
        imageButtons.forEach { $0.isEnabled = false }
        Task { [weak self] in
            do {
                let (saved, preview) = try await Task.detached(priority: .userInitiated) {
                    if forIcon { return try SettingsImageFiles.saveIcon(from: url, directory: directory) }
                    return try SettingsImageFiles.saveBackground(from: url, directory: directory)
                }.value
                guard let self else { return }
                previewGeneration += 1
                let image = NSImage(data: preview)!
                if forIcon {
                    Self.iconGeneration += 1
                    UserDefaults.standard.set(saved.path, forKey: "appearance.customIconPath")
                    NSApp.applicationIconImage = image
                    iconPreview.image = image
                } else {
                    UserDefaults.standard.set(saved.path, forKey: "background.customImagePath")
                    onBackgroundChange()
                    backgroundPreview.image = image
                }
                refreshControls(reloadImages: false)
            } catch {
                self?.refreshControls()
                NSAlert(error: error).runModal()
            }
            self?.imageButtons.forEach { $0.isEnabled = true }
        }
    }

    @objc private func followDesktop(_ sender: NSButton) {
        UserDefaults.standard.removeObject(forKey: "background.customImagePath")
        onBackgroundChange()
        refreshControls()
    }

    @objc private func restoreIcon(_ sender: NSButton) {
        do {
            let url = SettingsImageFiles.directory.appendingPathComponent("custom-icon.png")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            Self.iconGeneration += 1
            UserDefaults.standard.removeObject(forKey: "appearance.customIconPath")
            NSApp.applicationIconImage = nil
            refreshControls()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func heading(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }
    private func column(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }
    private func preview(width: CGFloat, height: CGFloat) -> NSImageView {
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: width), image.heightAnchor.constraint(equalToConstant: height)])
        return image
    }
    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
}

@MainActor
private final class SettingsShortcutRecorder: NSButton {
    var onRecord: ((UInt32, UInt32, String) -> Void)?
    private var recording = false
    private var previousTitle = ""

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording(_ sender: NSButton) {
        if recording {
            cancelRecording()
            window?.makeFirstResponder(nil)
            return
        }
        previousTitle = title
        recording = true
        title = "请按快捷键（Esc 取消）"
        window?.makeFirstResponder(self)
    }

    func cancelRecording() {
        if recording { title = previousTitle; recording = false }
    }

    func acceptRegisteredShortcut(keyCode: UInt32, modifiers: UInt32, label: String) -> Bool {
        guard recording, window?.isKeyWindow == true else { return false }
        cancelRecording()
        window?.makeFirstResponder(nil)
        onRecord?(keyCode, modifiers, label)
        return true
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event) || super.performKeyEquivalent(with: event)
    }

    private func record(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        if event.keyCode == 53 {
            cancelRecording()
            window?.makeFirstResponder(nil)
            return true
        }
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            title = "请包含 ⌘、⌥ 或 ⌃"
            return true
        }
        if event.isARepeat { return true }
        var modifiers: UInt32 = 0
        var label = ""
        for (flag, carbon, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(carbon); label += symbol }
        }
        switch event.keyCode {
        case 49: label += "Space"
        case 36: label += "Return"
        case 76: label += "Enter"
        case 48: label += "Tab"
        case 51: label += "Delete"
        case 117: label += "Forward Delete"
        case 115: label += "Home"
        case 119: label += "End"
        case 116: label += "Page Up"
        case 121: label += "Page Down"
        case 123: label += "←"
        case 124: label += "→"
        case 125: label += "↓"
        case 126: label += "↑"
        default:
            if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
               (UInt32(NSF1FunctionKey)...UInt32(NSF35FunctionKey)).contains(scalar.value) {
                label += "F\(scalar.value - UInt32(NSF1FunctionKey) + 1)"
            } else {
                label += event.charactersIgnoringModifiers?.uppercased() ?? "键码 \(event.keyCode)"
            }
        }
        cancelRecording()
        window?.makeFirstResponder(nil)
        onRecord?(UInt32(event.keyCode), modifiers, label)
        return true
    }
}

enum SettingsImageFiles {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Launcheer", isDirectory: true)
    }
    static let invalidImage = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError,
                                      userInfo: [NSLocalizedDescriptionKey: "所选文件不是可解码的图片。"])

    static func saveBackground(from url: URL, directory: URL) throws -> (URL, Data) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let preview = try thumbnail(data: data, pixels: 320)
        let saved = directory.appendingPathComponent("custom-background")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: saved, options: .atomic)
        return (saved, preview)
    }

    static func saveIcon(from url: URL, directory: URL) throws -> (URL, Data) {
        let data = try preview(at: url, pixels: 512)
        let saved = directory.appendingPathComponent("custom-icon.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: saved, options: .atomic)
        return (saved, data)
    }

    static func preview(at url: URL, pixels: Int) throws -> Data {
        try thumbnail(data: Data(contentsOf: url, options: .mappedIfSafe), pixels: pixels)
    }

    private static func thumbnail(data: Data, pixels: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let output = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw invalidImage }
        return output as Data
    }
}
