import Foundation
import Carbon.HIToolbox

struct ShortcutSettings: Equatable {
    var isEnabled: Bool
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShortcut = ShortcutSettings(
        isEnabled: true,
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    static let defaultSearchShortcut = ShortcutSettings(
        isEnabled: false,
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | shiftKey)
    )

    static func loadSearch(from defaults: UserDefaults = .standard) -> ShortcutSettings {
        guard defaults.object(forKey: "search.isEnabled") != nil else { return defaultSearchShortcut }
        return ShortcutSettings(
            isEnabled: defaults.bool(forKey: "search.isEnabled"),
            keyCode: UInt32(defaults.integer(forKey: "search.keyCode")),
            modifiers: UInt32(defaults.integer(forKey: "search.modifiers"))
        )
    }

    func saveSearch(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: "search.isEnabled")
        defaults.set(Int(keyCode), forKey: "search.keyCode")
        defaults.set(Int(modifiers), forKey: "search.modifiers")
    }

    func conflicts(with other: ShortcutSettings) -> Bool {
        isEnabled && other.isEnabled && keyCode == other.keyCode && modifiers == other.modifiers
    }

    var keyLabel: String {
        let symbols = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
        return symbols + (keyCode == UInt32(kVK_Space) ? "Space" : "键码 \(keyCode)")
    }

    static func load() -> ShortcutSettings {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.isEnabled) == nil {
            defaultShortcut.save()
            return defaultShortcut
        }
        return ShortcutSettings(
            isEnabled: defaults.bool(forKey: Keys.isEnabled),
            keyCode: UInt32(defaults.integer(forKey: Keys.keyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.modifiers))
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(Int(keyCode), forKey: Keys.keyCode)
        defaults.set(Int(modifiers), forKey: Keys.modifiers)
    }

    private enum Keys {
        static let isEnabled = "shortcut.isEnabled"
        static let keyCode = "shortcut.keyCode"
        static let modifiers = "shortcut.modifiers"
    }
}

struct DisplaySettings: Equatable {
    var showOnlyOnMainScreen: Bool

    static let defaultSettings = DisplaySettings(showOnlyOnMainScreen: true)

    static func load() -> DisplaySettings {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.showOnlyOnMainScreen) == nil {
            defaultSettings.save()
            return defaultSettings
        }
        return DisplaySettings(
            showOnlyOnMainScreen: defaults.bool(forKey: Keys.showOnlyOnMainScreen)
        )
    }

    func save() {
        UserDefaults.standard.set(showOnlyOnMainScreen, forKey: Keys.showOnlyOnMainScreen)
    }

    private enum Keys {
        static let showOnlyOnMainScreen = "display.showOnlyOnMainScreen"
    }
}
