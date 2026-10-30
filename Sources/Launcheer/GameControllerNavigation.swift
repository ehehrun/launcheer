import Foundation
import GameController

@MainActor
final class GameControllerNavigation {
    private let onKey: @MainActor (UInt16, Bool, Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var controllers: [GCController] = []
    private var started = false
    private var active = false
    private var direction: UInt16?
    private var directionController: ObjectIdentifier?
    private var usingDpad = false
    private var repeatTask: Task<Void, Never>?

    init(onKey: @escaping @MainActor (UInt16, Bool, Bool) -> Void) {
        self.onKey = onKey
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshControllers() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshControllers() }
        })
        refreshControllers()
    }

    func stop() {
        setActive(false)
        started = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        for controller in controllers { removeHandlers(controller) }
        controllers.removeAll()
    }

    func setActive(_ active: Bool) {
        self.active = active
        if !active { releaseDirection() }
    }

    func receiveDirection(from controller: ObjectIdentifier, dpadX: Float, dpadY: Float, stickX: Float, stickY: Float) {
        guard active else { return }
        let sameController = directionController == controller
        let dpad = selectedDirection(x: dpadX, y: dpadY, keeping: sameController && usingDpad ? direction : nil)
        let next = dpad ?? selectedDirection(x: stickX, y: stickY, keeping: sameController && !usingDpad ? direction : nil)
        if next == nil && !sameController { return }
        if next == direction && sameController {
            usingDpad = dpad != nil
            return
        }
        releaseDirection()
        guard active, let next else { return }
        direction = next
        directionController = controller
        usingDpad = dpad != nil
        onKey(next, true, false)
        // Sending a key can launch an app or hide the window synchronously.
        guard active, direction == next, directionController == controller else { return }
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                while !Task.isCancelled {
                    guard self?.active == true, let key = self?.direction else { return }
                    self?.onKey(key, true, true)
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch { return }
        }
    }

    func receiveButton(keyCode: UInt16, pressed: Bool) {
        guard active, pressed else { return }
        releaseDirection()
        guard active else { return }
        onKey(keyCode, true, false)
        onKey(keyCode, false, false)
    }

    private func selectedDirection(x: Float, y: Float, keeping: UInt16?) -> UInt16? {
        let horizontal = abs(x) >= abs(y)
        let magnitude = max(abs(x), abs(y))
        let next: UInt16 = horizontal ? (x > 0 ? 124 : 123) : (y > 0 ? 126 : 125)
        if let keeping {
            let held: Float
            switch keeping {
            case 123: held = -x
            case 124: held = x
            case 125: held = -y
            default: held = y
            }
            if held >= 0.35 && (next == keeping || magnitude < 0.55 || magnitude < held * 1.25) { return keeping }
        }
        return magnitude >= 0.55 ? next : nil
    }

    private func releaseDirection() {
        repeatTask?.cancel()
        repeatTask = nil
        let key = direction
        direction = nil
        directionController = nil
        usingDpad = false
        if let key { onKey(key, false, false) }
    }

    private func refreshControllers() {
        guard started else { return }
        let current = GCController.controllers()
        for controller in controllers where !current.contains(where: { $0 === controller }) {
            disconnect(controller)
        }
        for controller in current { attach(controller) }
    }

    private func attach(_ controller: GCController) {
        guard started, !controllers.contains(where: { $0 === controller }),
              controller.extendedGamepad != nil || controller.microGamepad != nil else { return }
        controllers.append(controller)
        controller.handlerQueue = .main
        let moved: GCControllerDirectionPadValueChangedHandler = { [weak self, weak controller] _, _, _ in
            MainActor.assumeIsolated {
                if let controller { self?.readDirection(controller) }
            }
        }
        let confirm: GCControllerButtonValueChangedHandler = { [weak self, weak controller] _, _, pressed in
            MainActor.assumeIsolated {
                guard let self, let controller, self.controllers.contains(where: { $0 === controller }) else { return }
                self.receiveButton(keyCode: 36, pressed: pressed)
            }
        }
        let back: GCControllerButtonValueChangedHandler = { [weak self, weak controller] _, _, pressed in
            MainActor.assumeIsolated {
                guard let self, let controller, self.controllers.contains(where: { $0 === controller }) else { return }
                self.receiveButton(keyCode: 53, pressed: pressed)
            }
        }
        if let gamepad = controller.extendedGamepad {
            gamepad.dpad.valueChangedHandler = moved
            gamepad.leftThumbstick.valueChangedHandler = moved
            gamepad.buttonA.pressedChangedHandler = confirm
            gamepad.buttonB.pressedChangedHandler = back
        } else if let gamepad = controller.microGamepad {
            gamepad.dpad.valueChangedHandler = moved
            gamepad.buttonA.pressedChangedHandler = confirm
            gamepad.buttonX.pressedChangedHandler = back
        }
    }

    private func readDirection(_ controller: GCController) {
        guard controllers.contains(where: { $0 === controller }) else { return }
        let id = ObjectIdentifier(controller)
        if let gamepad = controller.extendedGamepad {
            receiveDirection(from: id, dpadX: gamepad.dpad.xAxis.value, dpadY: gamepad.dpad.yAxis.value,
                             stickX: gamepad.leftThumbstick.xAxis.value, stickY: gamepad.leftThumbstick.yAxis.value)
        } else if let gamepad = controller.microGamepad {
            receiveDirection(from: id, dpadX: gamepad.dpad.xAxis.value, dpadY: gamepad.dpad.yAxis.value, stickX: 0, stickY: 0)
        }
    }

    private func disconnect(_ controller: GCController) {
        removeHandlers(controller)
        controllers.removeAll { $0 === controller }
        if directionController == ObjectIdentifier(controller) { releaseDirection() }
    }

    private func removeHandlers(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            gamepad.dpad.valueChangedHandler = nil
            gamepad.leftThumbstick.valueChangedHandler = nil
            gamepad.buttonA.pressedChangedHandler = nil
            gamepad.buttonB.pressedChangedHandler = nil
        } else if let gamepad = controller.microGamepad {
            gamepad.dpad.valueChangedHandler = nil
            gamepad.buttonA.pressedChangedHandler = nil
            gamepad.buttonX.pressedChangedHandler = nil
        }
    }
}
