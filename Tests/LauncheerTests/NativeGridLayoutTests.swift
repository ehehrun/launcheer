import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeGridLayoutTests {
    @Test(arguments: ["bottom", "left", "right"])
    func hidingAndRestoringTheDockDoesNotReflowTheGrid(edge: String) throws {
        try withNativeLayout { layout in
            let input = GridInput(edge: edge)
            layout(input)
            let frame = input.springboard.layer.frame
            let margins = input.springboard.margins
            let zoom = input.springboard.zoomFactor
            let visible = input.visibleFrame

            // Group open, close, and a quick reopen all change Dock visibility, not the grid.
            for _ in 0..<3 {
                input.window.screen.visibleFrame = input.window.screen.frame
                layout(input)
                #expect(input.springboard.layer.frame == frame)
                #expect(input.springboard.margins == margins)
                #expect(input.springboard.zoomFactor == zoom)
                #expect(input.visibleFrame == visible)
                #expect(input.springboard.layoutCount == 1)

                input.window.screen.visibleFrame = visible
                layout(input)
                #expect(input.springboard.layer.frame == frame)
                #expect(input.springboard.layoutCount == 1)
            }
            #expect(NSApp == nil)
        }
    }

    @Test func realScreenGeometryScaleAndNotchChangesStillUpdateLayout() throws {
        try withNativeLayout { layout in
            let input = GridInput(edge: "bottom")
            layout(input)
            let original = input.springboard.layer.frame

            input.window.screen.frame = CGRect(x: 1800, y: 0, width: 1920, height: 1200)
            input.window.screen.visibleFrame = CGRect(x: 1800, y: 90, width: 1920, height: 1084)
            input.bounds.size = input.window.screen.frame.size
            layout(input)
            #expect(input.springboard.layoutCount == 2)
            #expect(input.springboard.layer.frame != original)
            #expect(input.backdrop.frame == input.bounds)

            input.window.backingScaleFactor = 2
            layout(input)
            #expect(input.springboard.layoutCount == 3)
            #expect(input.springboard.scaleFactor == 2)

            let beforeNotch = input.springboard.layer.frame
            input.window.screen.safeAreaInsets.top = 38
            layout(input)
            #expect(input.springboard.layoutCount == 4)
            #expect(input.springboard.layer.frame.height == beforeNotch.height - 38)

            layout(input)
            #expect(input.springboard.layoutCount == 4)
            #expect(NSApp == nil)
        }
    }

    @Test func movingToAnEqualSizeScreenRefreshesItsDockInsets() throws {
        try withNativeLayout { layout in
            let input = GridInput(edge: "bottom")
            layout(input)
            let original = input.springboard.layer.frame

            input.window.screen.frame.origin.x = 1800
            input.window.screen.visibleFrame = CGRect(x: 1900, y: 0, width: 1700, height: 1074)
            layout(input)

            #expect(input.springboard.layoutCount == 2)
            #expect(input.springboard.layer.frame != original)
            #expect(input.visibleFrame == input.window.screen.visibleFrame)
            #expect(input.springboard.margins[0] > input.springboard.margins[1])
            #expect(NSApp == nil)
        }
    }

    @Test func showingAgainPicksUpTheCurrentDockInsets() throws {
        try withNativeLayout { layout in
            let input = GridInput(edge: "bottom")
            layout(input)
            let original = input.springboard.layer.frame
            let host = GridShowHost()
            host.setValue(input.window, forKey: "window")
            host.setValue(input, forKey: "view")
            host.setValue(input.springboard, forKey: "springboard")
            input.window.screen.visibleFrame = CGRect(x: 100, y: 0, width: 1700, height: 1074)

            let selector = NSSelectorFromString("showLauncherOnScreen:")
            let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
            typealias Show = @convention(c) (AnyObject, Selector, AnyObject) -> Void
            let show = unsafeBitCast(method_getImplementation(method), to: Show.self)
            show(host, selector, input.window.screen)
            layout(input)

            #expect(input.springboard.layoutCount == 2)
            #expect(input.springboard.layer.frame != original)
            #expect(input.springboard.margins[0] > input.springboard.margins[1])
            #expect(host.wantsLauncherVisible && input.springboard.visible)

            show(host, selector, input.window.screen)
            layout(input)
            #expect(input.springboard.layoutCount == 2)
            #expect(NSApp == nil)
        }
    }

    private func withNativeLayout(_ operation: ((GridInput) -> Void) throws -> Void) throws {
        let view: AnyClass = try #require(NSClassFromString("NativeView"))
        let selector = NSSelectorFromString("layout")
        let method = try #require(class_getInstanceMethod(view, selector))
        typealias Layout = @convention(c) (AnyObject, Selector) -> Void
        let layout = unsafeBitCast(method_getImplementation(method), to: Layout.self)
        let base = try #require(class_getInstanceMethod(NSView.self, selector))
        let block: @convention(block) (AnyObject) -> Void = { _ in }
        let replacement = imp_implementationWithBlock(block)
        let previous = method_setImplementation(base, replacement)
        defer {
            method_setImplementation(base, previous)
            imp_removeBlock(replacement)
        }
        // Run the production override on plain objects without entering NSView's own layout.
        try operation { layout($0, selector) }
    }
}

@MainActor
private final class GridInput: NSObject {
    @objc let window: GridWindow
    @objc let host = GridHost()
    @objc let springboard = GridSpringboard()
    @objc let layer = CALayer()
    @objc let backdrop = CALayer()
    @objc var bounds = CGRect(x: 0, y: 0, width: 1800, height: 1100)
    @objc var layoutBounds = CGRect.null
    @objc var screenFrame = CGRect.zero
    @objc var visibleFrame: CGRect
    @objc var safeAreaTop: CGFloat = 0
    @objc var layoutScale: Float = 0
    @objc var needsLayout = false

    @objc func activePager() -> NSObject? { nil }

    init(edge: String) {
        let screen = GridScreen(edge: edge)
        window = GridWindow(screen: screen)
        visibleFrame = screen.visibleFrame
        super.init()
    }
}

@MainActor
private final class GridWindow: NSObject {
    @objc let contentView = GridContent()
    @objc let screen: GridScreen
    @objc var backingScaleFactor: CGFloat = 1
    @objc var ignoresMouseEvents = false
    @objc var frame = CGRect.zero
    init(screen: GridScreen) { self.screen = screen; super.init() }
    @objc(setFrame:display:)
    func setFrame(_ frame: NSRect, display: Bool) { self.frame = frame }
    @objc func makeKeyAndOrderFront(_ sender: NSObject?) {}
    @objc func makeFirstResponder(_ responder: NSObject?) -> Bool { true }
}

@MainActor
private final class GridContent: NSObject {
    @objc let layer = CALayer()
}

@MainActor
private final class GridScreen: NSObject {
    @objc var backingScaleFactor: CGFloat = 1
    @objc var frame = CGRect(x: 0, y: 0, width: 1800, height: 1100)
    @objc var visibleFrame: CGRect
    @objc var safeAreaInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    init(edge: String) {
        switch edge {
        case "left": visibleFrame = CGRect(x: 100, y: 0, width: 1700, height: 1074)
        case "right": visibleFrame = CGRect(x: 0, y: 0, width: 1700, height: 1074)
        default: visibleFrame = CGRect(x: 0, y: 80, width: 1800, height: 994)
        }
        super.init()
    }
}

@MainActor
private final class GridHost: NSObject {
    @objc var search: NSObject?
    @objc var versionLabel: NSObject?
    @objc var groupTextInput: CALayer?
}

private final class GridShowHost: NativeHost {
    @objc(updateBackgroundMaterial:)
    func updateBackgroundMaterial(_ notification: NSNotification?) {}
    @objc(updateMenuBarCoverForScreen:)
    func updateMenuBarCover(_ screen: NSObject) {}
    @objc(prepareDesktopForScreen:)
    func prepareDesktop(_ screen: NSObject) {}
}

private final class GridLayer: CALayer {
    @objc var searchTextInputLayer: CALayer?
}

@MainActor
private final class GridSpringboard: NSObject {
    @objc let layer = GridLayer()
    @objc var visible = false
    private(set) var margins = [Double](repeating: 0, count: 4)
    private(set) var zoomFactor: Double = 0
    private(set) var scaleFactor: Float = 0
    private(set) var layoutCount = 0
    @objc func setLeftMargin(_ value: Double) { margins[0] = value }
    @objc func setRightMargin(_ value: Double) { margins[1] = value }
    @objc func setTopMargin(_ value: Double) { margins[2] = value }
    @objc func setBottomMargin(_ value: Double) { margins[3] = value }
    @objc func setZoomFactor(_ value: Double) { zoomFactor = value }
    @objc func setScaleFactor(_ value: Float) { scaleFactor = value }
    @objc func layout() { layoutCount += 1 }
}
