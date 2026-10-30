import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var searchHotKeyRef: EventHotKeyRef?
    private var searchSettings: ShortcutSettings?
    private var eventHandlerRef: EventHandlerRef?
    private let onToggle: @MainActor () -> Void
    private let onSearch: @MainActor () -> Void

    init(onToggle: @escaping @MainActor () -> Void, onSearch: @escaping @MainActor () -> Void) throws {
        self.onToggle = onToggle
        self.onSearch = onSearch
        do {
            try installHandler()
        } catch {
            stop()
            throw error
        }
    }

    func applyCurrentSettings() throws {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        hotKeyRef = try register(ShortcutSettings.load(), id: 1)
    }

    func applySearchSettings(_ settings: ShortcutSettings) throws {
        guard settings != searchSettings else { return }
        if hotKeyRef != nil && settings.conflicts(with: ShortcutSettings.load()) {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(eventHotKeyExistsErr), userInfo: [
                NSLocalizedDescriptionKey: "该快捷键已用于打开 Launcheer 启动台，请为应用搜索选择另一个组合。"
            ])
        }
        let replacement = try register(settings, id: 2)
        if let searchHotKeyRef { UnregisterEventHotKey(searchHotKeyRef) }
        searchHotKeyRef = replacement
        searchSettings = settings
    }

    func stop() {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func register(_ settings: ShortcutSettings, id: UInt32) throws -> EventHotKeyRef? {
        guard settings.isEnabled else { return nil }
        guard settings.modifiers != 0 else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError, userInfo: [
                NSLocalizedDescriptionKey: "全局快捷键需要包含修饰键。"
            ])
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("Lnch"), id: id)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            settings.keyCode,
            settings.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "无法注册快捷键，可能已被系统或其他应用占用。使用 ⌘Space 时，请先在系统设置中关闭 Spotlight 的相同快捷键。"
            ])
        }
        return newHotKeyRef
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let searchHotKeyRef {
            UnregisterEventHotKey(searchHotKeyRef)
            self.searchHotKeyRef = nil
        }
        searchSettings = nil
    }

    private func installHandler() throws {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == fourCharCode("Lnch"), let context else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(context).takeUnretainedValue()
            switch hotKeyID.id {
            case 1: DispatchQueue.main.async { manager.onToggle() }
            case 2: DispatchQueue.main.async { manager.onSearch() }
            default: return OSStatus(eventNotHandledErr)
            }
            return noErr
        }
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "无法安装启动台快捷键事件处理器。"
            ])
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
