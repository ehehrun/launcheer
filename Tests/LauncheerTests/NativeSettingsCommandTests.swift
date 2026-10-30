import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeSettingsCommandTests {
    @Test func onlyTheExactSettingsCommandOpensSettingsAndOtherSearchesKeepTheirBehavior() throws {
        let host = SettingsCommandHost()
        let search = SettingsCommandText()
        let label = SettingsCommandText()
        let springboard = SettingsCommandSpringboard()
        let view = SettingsCommandContent()
        let settings = URL(fileURLWithPath: "/Applications/Settings Fixture.app")
        let other = URL(fileURLWithPath: "/Applications/Other Fixture.app")
        host.items = [settings, other]
        host.setValue(search, forKey: "search")
        host.setValue(label, forKey: "versionLabel")
        host.setValue(springboard, forKey: "springboard")
        host.setValue(view, forKey: "view")
        let selector = NSSelectorFromString("searchTextChanged:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Search = @convention(c) (AnyObject, Selector, NSString) -> Void
        let change = unsafeBitCast(method_getImplementation(method), to: Search.self)
        change(host, selector, "Settings")
        #expect(springboard.filtered == [[settings]] && host.settingsCount == 0)
        let filterCount = springboard.filtered.count
        label.hidden = false

        change(host, selector, "/settings")

        #expect(host.settingsCount == 1 && host.senderWasHost)
        #expect(search.stringValue == "/settings" && label.hidden)
        #expect(springboard.filtered.count == filterCount && springboard.clearCount == 0)
        for query in ["/Settings", "/settingsExtra", " /settings", "/settings "] {
            change(host, selector, query as NSString)
            #expect(host.settingsCount == 1 && search.stringValue == query && label.hidden)
            #expect(springboard.filtered.last == [])
        }

        change(host, selector, "/version")
        #expect(host.settingsCount == 1 && !label.hidden && !label.stringValue.isEmpty)
        #expect(springboard.filtered.last == [])
        #expect((host.value(forKey: "searchPages") as? NSArray)?.count == 0)
        change(host, selector, "Other")
        #expect(host.settingsCount == 1 && label.hidden && springboard.filtered.last == [other])
        #expect(view.needsLayout)

        let clearSelector = NSSelectorFromString("searchTextCleared")
        let clearMethod = try #require(class_getInstanceMethod(NativeHost.self, clearSelector))
        typealias Clear = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(method_getImplementation(clearMethod), to: Clear.self)(host, clearSelector)
        #expect(search.stringValue.isEmpty && label.hidden && springboard.clearCount == 1)
        #expect(host.value(forKey: "searchPages") == nil && host.settingsCount == 1)
        #expect(NSApp == nil)
    }
}

private final class SettingsCommandHost: NativeHost {
    private(set) var settingsCount = 0
    private(set) var senderWasHost = false
    override func showSettings(_ sender: Any) {
        settingsCount += 1
        senderWasHost = sender as AnyObject === self
    }
}

@MainActor
private final class SettingsCommandText: NSObject {
    @objc var hidden = true
    @objc var stringValue = ""
}

@MainActor
private final class SettingsCommandSpringboard: NSObject {
    private(set) var filtered: [[URL]] = []
    private(set) var clearCount = 0
    @objc(filterUsingItems:)
    func filter(_ items: [URL]) { filtered.append(items) }
    @objc func clearFilteredItems() { clearCount += 1 }
}

@MainActor
private final class SettingsCommandContent: NSObject {
    @objc var needsLayout = false
}
