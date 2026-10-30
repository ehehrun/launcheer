import AppKit
import NativeLaunchpad
import Testing

@Suite(.serialized)
@MainActor
struct NativeVisibilityTests {
    @Test func hidingRemovesTheWindowBeforeCleaningNativeState() {
        let host = NativeHost()
        let window = VisibilityWindow()
        let cover = VisibilityWindow()
        let springboard = VisibilitySpringboard(window: window, cover: cover)
        host.setValue(window, forKey: "window")
        host.setValue(cover, forKey: "menuBarCoverWindow")
        host.setValue(springboard, forKey: "springboard")
        host.setValue(true, forKey: "wantsLauncherVisible")

        host.hideLauncher()

        #expect(window.orderOutCount == 1)
        #expect(cover.orderOutCount == 1)
        #expect(window.ignoresMouseEvents)
        #expect(springboard.cleanedAfterOrderOut)
        #expect(springboard.visible == false)
        #expect(host.value(forKey: "wantsLauncherVisible") as? Bool == false)

        host.hideLauncher()
        #expect(window.orderOutCount == 1)
        #expect(cover.orderOutCount == 1)
    }
}

@MainActor
private final class VisibilityWindow: NSObject {
    @objc var ignoresMouseEvents = false
    @objc var isKeyWindow: Bool { false }
    private(set) var orderOutCount = 0

    @objc func orderOut(_ sender: Any?) { orderOutCount += 1 }
}

@MainActor
private final class VisibilitySpringboard: NSObject {
    let window: VisibilityWindow
    let cover: VisibilityWindow
    private(set) var cleanedAfterOrderOut = false
    private(set) var visible = true
    @objc var pager: NSObject? { nil }
    @objc var layer: CALayer? { nil }

    init(window: VisibilityWindow, cover: VisibilityWindow) {
        self.window = window
        self.cover = cover
    }

    @objc func cancelDrag(_ animated: Bool) {
        cleanedAfterOrderOut = window.orderOutCount == 1 && cover.orderOutCount == 1
    }

    @objc func setGroupShown(_ shown: Bool) {}
    @objc func setVisible(_ visible: Bool) { self.visible = visible }
}
