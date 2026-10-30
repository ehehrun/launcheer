import Carbon.HIToolbox
import Foundation
import Testing
@testable import Launcheer

struct ShortcutSettingsTests {
    @Test func searchPreferencesStaySeparateFromTheLauncherShortcut() throws {
        let domain = "Launcheer.ShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(42, forKey: "shortcut.keyCode")
        #expect(ShortcutSettings.loadSearch(from: defaults) == .defaultSearchShortcut)
        #expect(defaults.object(forKey: "search.isEnabled") == nil)

        let custom = ShortcutSettings(isEnabled: true, keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
        custom.saveSearch(to: defaults)
        #expect(ShortcutSettings.loadSearch(from: defaults) == custom)
        #expect(defaults.integer(forKey: "shortcut.keyCode") == 42)
        var disabled = custom
        disabled.isEnabled = false
        disabled.saveSearch(to: defaults)
        #expect(ShortcutSettings.loadSearch(from: defaults) == disabled)
    }

    @Test func onlyActiveIdenticalCombinationsConflict() {
        let launcher = ShortcutSettings.defaultShortcut
        var search = launcher
        #expect(search.conflicts(with: launcher))
        search.isEnabled = false
        #expect(!search.conflicts(with: launcher))
        search.isEnabled = true
        search.keyCode = UInt32(kVK_ANSI_K)
        #expect(!search.conflicts(with: launcher))
        search.keyCode = launcher.keyCode
        search.modifiers |= UInt32(shiftKey)
        #expect(!search.conflicts(with: launcher))
        #expect(ShortcutSettings.defaultSearchShortcut.keyLabel == "⌥⇧Space")
    }
}
