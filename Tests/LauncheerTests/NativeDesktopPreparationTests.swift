import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeDesktopPreparationTests {
    @Test(arguments: ["success", "failure", "cancelled"], [true, false])
    func completionUpdatesOnlyAVisibleLauncher(status: String, visible: Bool) throws {
        let host = DesktopPreparationHost()
        let view = DesktopPreparationContent()
        let screen = NSObject()
        host.setValue(view, forKey: "view")
        host.setValue(true, forKey: "wantsLauncherVisible")
        let selector = NSSelectorFromString("prepareDesktopForScreen:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Prepare = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let prepare = unsafeBitCast(method_getImplementation(method), to: Prepare.self)

        prepare(host, selector, screen)

        #expect(view.backdrop.requestedScreen === screen)
        #expect(host.backgroundUpdates == 0 && host.coverScreen == nil && host.showCount == 0)
        #expect(host.value(forKey: "view") as? DesktopPreparationContent === view)
        let complete = try #require(view.backdrop.completion)
        host.setValue(visible, forKey: "wantsLauncherVisible")
        let success = status == "success"
        let cancelled = status == "cancelled"
        let code: CocoaError.Code = cancelled ? .userCancelled : .fileReadNoPermission
        let error = success ? nil : NSError(domain: NSCocoaErrorDomain, code: code.rawValue)

        complete(success, error)

        #expect(view.backdrop.colorScreen === (status == "failure" ? screen : nil))
        #expect(host.backgroundUpdates == (visible && !cancelled ? 1 : 0))
        #expect(host.coverScreen === (visible && !cancelled ? screen : nil))
        #expect(host.showCount == 0)
        #expect(host.value(forKey: "view") as? DesktopPreparationContent === view)
    }
}

private final class DesktopPreparationHost: NativeHost {
    private(set) var backgroundUpdates = 0
    private(set) var coverScreen: NSObject?
    private(set) var showCount = 0
    override func showLauncher() { showCount += 1 }
    @objc(showLauncherOnScreen:)
    func showLauncher(on screen: NSObject) { showCount += 1 }
    @objc(updateBackgroundMaterial:)
    func updateBackground(_ notification: NSNotification?) { backgroundUpdates += 1 }
    @objc(updateMenuBarCoverForScreen:)
    func updateCover(_ screen: NSObject) { coverScreen = screen }
}

@MainActor
private final class DesktopPreparationContent: NSObject {
    @objc let backdrop = DesktopPreparationBackdrop()
}

@MainActor
private final class DesktopPreparationBackdrop: NSObject {
    private(set) var requestedScreen: NSObject?
    private(set) var colorScreen: NSObject?
    private(set) var completion: ((Bool, NSError?) -> Void)?
    @objc(updateForScreen:completion:)
    func update(_ screen: NSObject, completion: @escaping (Bool, NSError?) -> Void) {
        requestedScreen = screen
        self.completion = completion
    }
    @objc(useBackgroundColorForScreen:)
    func useColor(_ screen: NSObject) { colorScreen = screen }
}
