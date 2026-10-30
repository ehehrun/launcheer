import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeWallpaperApplyTests {
    @Test(arguments: ["visible", "hidden", "cancelled"])
    func aSuccessfulSelectionAppliesBeforeReturning(state: String) throws {
        let url = NSURL(fileURLWithPath: "/tmp/launcheer-wallpaper-fixture.jpeg")
        let panel = WallpaperPanel(url: url, accepted: state != "cancelled")
        let panelMethod = try #require(class_getClassMethod(NSOpenPanel.self, NSSelectorFromString("openPanel")))
        let backdropType: AnyClass = try #require(NSClassFromString("NativeBackdrop"))
        let urlMethod = try #require(class_getClassMethod(backdropType, NSSelectorFromString("desktopImageURLForScreen:error:")))
        let panelBlock: @convention(block) (AnyObject) -> NSObject = { _ in panel }
        let urlBlock: @convention(block) (AnyObject, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSURL = { _, _, _ in url }
        let panelImplementation = imp_implementationWithBlock(panelBlock)
        let urlImplementation = imp_implementationWithBlock(urlBlock)
        let originalPanel = method_setImplementation(panelMethod, panelImplementation)
        let originalURL = method_setImplementation(urlMethod, urlImplementation)
        defer {
            method_setImplementation(panelMethod, originalPanel)
            method_setImplementation(urlMethod, originalURL)
            imp_removeBlock(panelImplementation)
            imp_removeBlock(urlImplementation)
        }

        let host = WallpaperHost()
        let view = WallpaperContent()
        let window = WallpaperWindow()
        host.setValue(window, forKey: "window")
        host.setValue(view, forKey: "view")
        host.setValue(state == "visible", forKey: "wantsLauncherVisible")

        host.authorizeDesktopImage(NSObject())

        #expect(host.refreshCount == (state == "visible" ? 1 : 0))
        #expect(host.showCount == (state == "hidden" ? 1 : 0))
        #expect(host.shownScreen === (state == "hidden" ? window.screen : nil))
        #expect(view.backdrop.cachedURL == (state == "cancelled" ? nil : url))
    }
}

private final class WallpaperHost: NativeHost {
    private(set) var refreshCount = 0
    private(set) var showCount = 0
    private(set) var shownScreen: NSObject?
    @objc(showLauncherOnScreen:)
    func showLauncher(on screen: NSObject) {
        showCount += 1
        shownScreen = screen
    }
    @objc(refreshDesktop:)
    func refreshDesktop(_ notification: NSNotification?) { refreshCount += 1 }
}

@MainActor
private final class WallpaperWindow: NSObject {
    @objc let screen = NSObject()
}

@MainActor
private final class WallpaperContent: NSObject {
    @objc let backdrop = WallpaperCache()
}

@MainActor
private final class WallpaperCache: NSObject {
    private(set) var cachedURL: NSURL?
    @objc(cacheAuthorizedImageAtURL:error:)
    func cache(_ url: NSURL, error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
        cachedURL = url
        return true
    }
}

@MainActor
private final class WallpaperPanel: NSObject {
    @objc var message = ""
    @objc var prompt = ""
    @objc var directoryURL: NSURL?
    @objc var canChooseFiles = false
    @objc var canChooseDirectories = false
    @objc var allowsMultipleSelection = false
    @objc var canCreateDirectories = false
    @objc(URL) let selectedURL: NSURL
    let accepted: Bool

    init(url: NSURL, accepted: Bool) {
        selectedURL = url
        self.accepted = accepted
        super.init()
    }

    @objc func runModal() -> Int {
        accepted ? NSApplication.ModalResponse.OK.rawValue : NSApplication.ModalResponse.cancel.rawValue
    }
}
