import Foundation
import Testing
@testable import Launcheer

@Suite(.serialized)
@MainActor
struct GameControllerNavigationTests {
    @Test func dpadHasPriorityAndStickUsesEngageAndReleaseThresholds() {
        let source = NSObject()
        let id = ObjectIdentifier(source)
        var keys: [(UInt16, Bool, Bool)] = []
        let navigation = GameControllerNavigation { keys.append(($0, $1, $2)) }
        navigation.setActive(true)
        defer { navigation.stop() }

        navigation.receiveDirection(from: id, dpadX: 0, dpadY: 0, stickX: 0.5, stickY: 0)
        #expect(keys.isEmpty)
        navigation.receiveDirection(from: id, dpadX: 0, dpadY: 0, stickX: 0.7, stickY: 0)
        navigation.receiveDirection(from: id, dpadX: 0, dpadY: 0, stickX: 0.4, stickY: 0)
        navigation.receiveDirection(from: id, dpadX: 0, dpadY: 0, stickX: 0.7, stickY: 0.72)
        #expect(keys.map(\.0) == [124])
        navigation.receiveDirection(from: id, dpadX: 0, dpadY: 0, stickX: 0.4, stickY: 0.9)
        #expect(keys.map(\.0) == [124, 124, 126])
        #expect(keys.map(\.1) == [true, false, true])
        navigation.receiveDirection(from: id, dpadX: -1, dpadY: 0, stickX: 0, stickY: 0.9)
        #expect(keys.map(\.0) == [124, 124, 126, 126, 123])
        navigation.receiveDirection(from: id, dpadX: 0, dpadY: 0, stickX: 0, stickY: 0.34)
        #expect(keys.map(\.0) == [124, 124, 126, 126, 123, 123])
        #expect(keys.map(\.1) == [true, false, true, false, true, false])
    }

    @Test func anotherControllersNeutralEventCannotReleaseTheCurrentDirection() {
        let first = NSObject(), second = NSObject()
        var keys: [(UInt16, Bool)] = []
        let navigation = GameControllerNavigation { key, pressed, _ in keys.append((key, pressed)) }
        navigation.setActive(true)
        defer { navigation.stop() }

        navigation.receiveDirection(from: ObjectIdentifier(first), dpadX: -1, dpadY: 0, stickX: 0, stickY: 0)
        navigation.receiveDirection(from: ObjectIdentifier(second), dpadX: 0, dpadY: 0, stickX: 0, stickY: 0)
        #expect(keys.count == 1 && keys.first?.0 == 123)
        navigation.receiveDirection(from: ObjectIdentifier(second), dpadX: 1, dpadY: 0, stickX: 0, stickY: 0)
        navigation.receiveDirection(from: ObjectIdentifier(first), dpadX: 0, dpadY: 0, stickX: 0, stickY: 0)
        #expect(keys.map(\.0) == [123, 123, 124])
        navigation.setActive(false)
        #expect(keys.map(\.1) == [true, false, true, false])
        navigation.receiveDirection(from: ObjectIdentifier(first), dpadX: 1, dpadY: 0, stickX: 0, stickY: 0)
        navigation.receiveButton(keyCode: 36, pressed: true)
        #expect(keys.count == 4)
    }

    @Test func confirmAndBackSendOneBalancedPressAndStopNavigation() {
        let source = NSObject()
        var keys: [(UInt16, Bool)] = []
        let navigation = GameControllerNavigation { key, pressed, _ in keys.append((key, pressed)) }
        navigation.setActive(true)
        defer { navigation.stop() }

        navigation.receiveDirection(from: ObjectIdentifier(source), dpadX: 0, dpadY: -1, stickX: 0, stickY: 0)
        navigation.receiveButton(keyCode: 36, pressed: false)
        navigation.receiveButton(keyCode: 36, pressed: true)
        navigation.receiveButton(keyCode: 53, pressed: true)
        #expect(keys.map(\.0) == [125, 125, 36, 36, 53, 53])
        #expect(keys.map(\.1) == [true, false, true, false, true, false])
    }

    @Test func hidingDuringTheInitialPressReleasesTheKeyWithoutRepeating() async throws {
        let source = NSObject()
        var keys: [(UInt16, Bool, Bool)] = []
        let reentry = ControllerReentry()
        let navigation = GameControllerNavigation { key, pressed, repeated in
            keys.append((key, pressed, repeated))
            if pressed { reentry.navigation?.setActive(false) }
        }
        reentry.navigation = navigation
        navigation.setActive(true)
        navigation.receiveDirection(from: ObjectIdentifier(source), dpadX: 1, dpadY: 0, stickX: 0, stickY: 0)
        #expect(keys.count == 2 && keys.map(\.1) == [true, false])
        try await Task.sleep(for: .milliseconds(470))
        #expect(keys.count == 2)
        navigation.stop()
    }

    @Test func aHeldDirectionRepeatsAndStopsImmediatelyOnDeactivation() async throws {
        let source = NSObject()
        var keys: [(UInt16, Bool, Bool)] = []
        let navigation = GameControllerNavigation { keys.append(($0, $1, $2)) }
        navigation.setActive(true)
        defer { navigation.stop() }
        navigation.receiveDirection(from: ObjectIdentifier(source), dpadX: 0, dpadY: 1, stickX: 0, stickY: 0)
        #expect(keys.count == 1 && keys.first?.2 == false)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !keys.contains(where: { $0.2 }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(keys.contains { $0.0 == 126 && $0.1 && $0.2 })
        navigation.setActive(false)
        let stoppedCount = keys.count
        #expect(keys.last?.0 == 126 && keys.last?.1 == false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(keys.count == stoppedCount)
    }
}

@MainActor
private final class ControllerReentry {
    weak var navigation: GameControllerNavigation?
}
