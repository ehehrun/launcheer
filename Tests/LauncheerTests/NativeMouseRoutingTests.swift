import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeMouseRoutingTests {
    @Test(arguments: ["blank", "icon", "control"])
    func mouseCaptureBelongsToTheHandlerThatAcceptsThePress(target: String) throws {
        let type: AnyClass = try #require(NSClassFromString("NativeView"))
        let selector = NSSelectorFromString("routeMouse:down:")
        let method = try #require(class_getInstanceMethod(type, selector))
        typealias Route = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
        let route = unsafeBitCast(method_getImplementation(method), to: Route.self)
        let view = MouseInput()
        let springboardLayer = view.springboard.layer
        springboardLayer.frame = view.layer.bounds
        springboardLayer.acceptsMouse = true
        view.layer.addSublayer(springboardLayer)
        let hit = MouseLayer()
        hit.frame = NSRect(x: 10, y: 10, width: 100, height: 100)
        hit.acceptsMouse = target == "control"
        springboardLayer.addSublayer(hit)
        let receiver = MouseReceiver()
        receiver.acceptsMouse = target == "icon"
        hit.eventDelegate = receiver

        let cancelSelector = NSSelectorFromString("cancelActionWithEvent:sender:")
        let cancelMethod = try #require(class_getInstanceMethod(NativeHost.self, cancelSelector))
        typealias Cancel = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> Void
        let cancel = unsafeBitCast(method_getImplementation(cancelMethod), to: Cancel.self)
        let host = view.host
        springboardLayer.onMouseUp = { cancel(host, cancelSelector, nil, nil) }
        let event = MouseEvent()

        route(view, selector, event, true)
        #expect(view.downLayer === (target == "blank" ? springboardLayer : hit))
        #expect(view.downPage === (target == "icon" ? receiver : nil))
        #expect(receiver.downCount == 1)
        #expect(receiver.upCount == 0)
        #expect(host.hideCount == 0)

        route(view, selector, event, false)
        #expect(receiver.upCount == (target == "icon" ? 1 : 0))
        #expect(hit.downCount == (target == "icon" ? 0 : 1))
        #expect(hit.upCount == (target == "control" ? 1 : 0))
        #expect(springboardLayer.downCount == (target == "blank" ? 1 : 0))
        #expect(springboardLayer.upCount == (target == "blank" ? 1 : 0))
        #expect(host.hideCount == (target == "blank" ? 1 : 0))
        #expect(host.modalSession.upCount == 1)
        #expect(view.downPage == nil && view.downLayer == nil && view.downHitLayer == nil)
    }
}

@MainActor
private final class MouseInput: NSObject {
    @objc let host = MouseHost()
    @objc let window = MouseWindow()
    @objc let springboard = MouseSpringboard()
    @objc let layer: CALayer = {
        let layer = CALayer()
        layer.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        return layer
    }()
    @objc var downPage: NSObject?
    @objc var downLayer: CALayer?
    @objc var downHitLayer: CALayer?
    @objc var downSearch = false
    @objc(convertPoint:fromView:)
    func convertPoint(_ point: NSPoint, from view: NSObject?) -> NSPoint { point }
    @objc(nativeEvent:hitLayer:)
    func nativeEvent(_ event: NSObject, hitLayer: CALayer?) -> NSObject { event }
}

@MainActor
private final class MouseEvent: NSObject {
    @objc let locationInWindow = NSPoint(x: 30, y: 30)
}

@MainActor
private final class MouseWindow: NSObject {
    @objc func makeFirstResponder(_ responder: NSObject) -> Bool { true }
}

@MainActor
private final class MouseSpringboard: NSObject {
    @objc let layer = MouseLayer()
}

@MainActor
private final class MouseHost: NSObject {
    @objc let modalSession = MouseSession()
    private(set) var hideCount = 0
    @objc func hideLauncher() { hideCount += 1 }
    @objc func finishGroupEditing() {}
    @objc func syncGroupEditor() {}
    @objc func applyPendingItems() {}
}

@MainActor
private final class MouseSession: NSObject {
    private(set) var upCount = 0
    @objc(performMouseUpBlocksWithEvent:)
    func performMouseUpBlocks(_ event: NSObject) { upCount += 1 }
}

@MainActor
private final class MouseReceiver: NSObject {
    var acceptsMouse = false
    private(set) var downCount = 0
    private(set) var upCount = 0
    @objc(leftMouseDown:in:)
    func mouseDown(_ event: NSObject, in layer: CALayer) -> Bool {
        downCount += 1
        return acceptsMouse
    }
    @objc(leftMouseUp:in:)
    func mouseUp(_ event: NSObject, in layer: CALayer) -> Bool {
        upCount += 1
        return true
    }
}

private final class MouseLayer: CALayer {
    @objc var eventDelegate: NSObject?
    @objc let searchTextInputLayer = CALayer()
    var acceptsMouse = false
    var onMouseUp: (() -> Void)?
    private(set) var downCount = 0
    private(set) var upCount = 0
    @objc(leftMouseDown:)
    func mouseDown(_ event: NSObject) -> Bool {
        downCount += 1
        return acceptsMouse
    }
    @objc(leftMouseUp:)
    func mouseUp(_ event: NSObject) -> Bool {
        upCount += 1
        onMouseUp?()
        return true
    }
}
