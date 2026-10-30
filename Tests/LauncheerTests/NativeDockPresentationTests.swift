import AppKit
import Darwin
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeDockPresentationTests {
    @Test(arguments: [
        NSApplication.PresentationOptions(),
        [.autoHideDock, .autoHideMenuBar, .disableMenuBarTransparency],
        [.hideDock, .hideMenuBar]
    ])
    func closingTheGroupRestoresTheOriginalPresentation(options: NSApplication.PresentationOptions) throws {
        try withApplication(options: options) { application in
            let host = visibleHost()
            let group = NSObject()

            try callback("groupShownForItem:atIndex:", host: host, group: group)
            #expect(application.presentationOptions & NSApplication.PresentationOptions.hideDock.rawValue != 0)
            #expect(application.presentationOptions & NSApplication.PresentationOptions.autoHideDock.rawValue == 0)
            let dockFlags = NSApplication.PresentationOptions.hideDock.rawValue | NSApplication.PresentationOptions.autoHideDock.rawValue
            #expect(application.presentationOptions & ~dockFlags == options.rawValue & ~dockFlags)

            try callback("groupShownForItem:atIndex:", host: host, group: group)
            try callback("groupHiddenForItem:atIndex:", host: host, group: group)
            #expect(application.presentationOptions == options.rawValue)
        }
    }

    @Test func anOldCloseCallbackDoesNotRestoreOverANewerGroup() throws {
        try withApplication(options: []) { application in
            let host = visibleHost()
            let first = NSObject()
            let second = NSObject()

            try callback("groupShownForItem:atIndex:", host: host, group: first)
            try callback("groupShownForItem:atIndex:", host: host, group: second)
            try callback("groupHiddenForItem:atIndex:", host: host, group: first)
            #expect(application.presentationOptions == NSApplication.PresentationOptions.hideDock.rawValue)

            try callback("groupHiddenForItem:atIndex:", host: host, group: second)
            #expect(application.presentationOptions == 0)
            application.presentationOptions = NSApplication.PresentationOptions.autoHideDock.rawValue
            try callback("groupHiddenForItem:atIndex:", host: host, group: first)
            #expect(application.presentationOptions == NSApplication.PresentationOptions.autoHideDock.rawValue)
        }
    }

    @Test func hidingRestoresTheDockAndIgnoresLateGroupCallbacks() throws {
        let original: NSApplication.PresentationOptions = [.autoHideDock, .autoHideMenuBar]
        try withApplication(options: original) { application in
            let host = visibleHost()
            let window = DockPresentationWindow()
            host.setValue(window, forKey: "window")
            let group = NSObject()

            try callback("groupShownForItem:atIndex:", host: host, group: group)
            host.hideLauncher()
            #expect(window.orderOutCount == 1)
            #expect(application.presentationOptions == original.rawValue)

            try callback("groupShownForItem:atIndex:", host: host, group: group)
            try callback("groupHiddenForItem:atIndex:", host: host, group: group)
            #expect(application.presentationOptions == original.rawValue)
        }
    }

    @Test func hidingRestoresPresentationAfterAGroupCallbackWithoutAnItem() throws {
        let original: NSApplication.PresentationOptions = [.autoHideDock, .autoHideMenuBar]
        try withApplication(options: original) { application in
            let host = visibleHost()
            let window = DockPresentationWindow()
            host.setValue(window, forKey: "window")

            try callback("groupShownForItem:atIndex:", host: host, group: nil)
            host.hideLauncher()

            #expect(window.orderOutCount == 1)
            #expect(application.presentationOptions == original.rawValue)
            host.setValue(true, forKey: "wantsLauncherVisible")
            #expect(application.presentationOptions == original.rawValue)
        }
    }

    @Test(arguments: [false, true])
    func closingAfterAGroupCallbackWithoutAnItemPreservesTheOriginalPresentation(newOwner: Bool) throws {
        let original: NSApplication.PresentationOptions = [.autoHideDock, .autoHideMenuBar]
        try withApplication(options: original) { application in
            let host = visibleHost()
            try callback("groupShownForItem:atIndex:", host: host, group: nil)

            if newOwner {
                let group = NSObject()
                try callback("groupShownForItem:atIndex:", host: host, group: group)
                try callback("groupHiddenForItem:atIndex:", host: host, group: nil)
                #expect(application.presentationOptions & NSApplication.PresentationOptions.hideDock.rawValue != 0)
                try callback("groupHiddenForItem:atIndex:", host: host, group: group)
            } else {
                try callback("groupHiddenForItem:atIndex:", host: host, group: nil)
            }

            #expect(application.presentationOptions == original.rawValue)
        }
    }

    private func visibleHost() -> NativeHost {
        let host = NativeHost()
        host.setValue(true, forKey: "wantsLauncherVisible")
        return host
    }

    private func callback(_ name: String, host: NativeHost, group: NSObject?) throws {
        let selector = NSSelectorFromString(name)
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Callback = @convention(c) (AnyObject, Selector, AnyObject?, UInt) -> Void
        let implementation = unsafeBitCast(method_getImplementation(method), to: Callback.self)
        implementation(host, selector, group, 0)
    }

    private func withApplication(options: NSApplication.PresentationOptions, operation: (DockPresentationApplication) throws -> Void) throws {
        let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "NSApp"))
        let slot = symbol.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
        let original = slot.pointee
        let application = DockPresentationApplication()
        application.presentationOptions = options.rawValue
        // Keep the real AppKit presentation setter and the system Dock out of this test.
        slot.pointee = Unmanaged.passUnretained(application).toOpaque()
        defer { slot.pointee = original }
        try withExtendedLifetime(application) { try operation(application) }
    }
}

@MainActor
private final class DockPresentationApplication: NSObject {
    @objc var presentationOptions: UInt = 0

    // hideLauncher ends scroll tracking, whose NSEvent initialization asks for this flag.
    @objc(_wantsDeviceDependentEventModifierFlags)
    func wantsDeviceDependentEventModifierFlags() -> Bool { false }
}

@MainActor
private final class DockPresentationWindow: NSObject {
    @objc var ignoresMouseEvents = false
    @objc var isKeyWindow: Bool { false }
    private(set) var orderOutCount = 0

    @objc func orderOut(_ sender: Any?) { orderOutCount += 1 }
}
