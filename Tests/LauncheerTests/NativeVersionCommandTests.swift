import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeVersionCommandTests {
    @Test func versionCommandUsesTheRunningBundleAndPreservesOrdinarySearch() throws {
        let host = NativeHost()
        let search = VersionTextField()
        let label = VersionTextField()
        let springboard = VersionSpringboard()
        let view = VersionContent()
        let app = URL(fileURLWithPath: "/Applications/VersionExtra.app")
        host.items = [app]
        host.setValue(search, forKey: "search")
        host.setValue(label, forKey: "versionLabel")
        host.setValue(springboard, forKey: "springboard")
        host.setValue(view, forKey: "view")
        let selector = NSSelectorFromString("searchTextChanged:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Search = @convention(c) (AnyObject, Selector, NSString) -> Void
        let change = unsafeBitCast(method_getImplementation(method), to: Search.self)

        do {
            let bundle = VersionBundle()
            let bundleMethod = try #require(class_getClassMethod(Bundle.self, NSSelectorFromString("mainBundle")))
            let block: @convention(block) (AnyObject) -> NSObject = { _ in bundle }
            let implementation = imp_implementationWithBlock(block)
            let previous = method_setImplementation(bundleMethod, implementation)
            defer {
                method_setImplementation(bundleMethod, previous)
                imp_removeBlock(implementation)
            }

            change(host, selector, "/version")

            #expect(!label.hidden && label.stringValue == "Launcheer 9.8.7 (Build 123)")
            #expect(search.stringValue == "/version")
            #expect(springboard.filtered == [[]])
            #expect((host.value(forKey: "searchPages") as? NSArray)?.count == 0)
            #expect(view.needsLayout)
        }

        for query in ["/versionExtra", "/VERSION", " /version"] {
            label.hidden = false
            change(host, selector, query as NSString)
            #expect(label.hidden && search.stringValue == query)
            #expect(springboard.filtered.last == [])
            #expect(springboard.clearCount == 0)
        }

        change(host, selector, "Version")
        #expect(label.hidden && search.stringValue == "Version")
        #expect(springboard.filtered.last == [app])
        #expect((host.value(forKey: "searchPages") as? NSArray)?.count == 1)

        label.hidden = false
        let clearSelector = NSSelectorFromString("searchTextCleared")
        let clearMethod = try #require(class_getInstanceMethod(NativeHost.self, clearSelector))
        typealias Clear = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(method_getImplementation(clearMethod), to: Clear.self)(host, clearSelector)
        #expect(label.hidden && search.stringValue.isEmpty)
        #expect(host.value(forKey: "searchPages") == nil && springboard.clearCount == 1)
        #expect(NSApp == nil)
    }
}

@MainActor
private final class VersionTextField: NSObject {
    @objc var hidden = true
    @objc var stringValue = ""
}

@MainActor
private final class VersionSpringboard: NSObject {
    private(set) var filtered: [[URL]] = []
    private(set) var clearCount = 0
    @objc(filterUsingItems:)
    func filter(_ items: [URL]) { filtered.append(items) }
    @objc func clearFilteredItems() { clearCount += 1 }
}

@MainActor
private final class VersionContent: NSObject {
    @objc var needsLayout = false
}

private final class VersionBundle: NSObject {
    @objc let infoDictionary = ["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "123"]
}
