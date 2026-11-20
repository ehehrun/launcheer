import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeSearchTests {
    @Test func theNativeGridUsesEveryRankedMatchFromTheSharedSearchHook() throws {
        let input = NativeSearchInput()
        let urls = (0..<73).map { URL(fileURLWithPath: "/Applications/Result \($0).app") }
        input.host.items = urls
        input.host.matches = Array(urls.reversed())

        try changeNativeQuery(input.host, to: "wx")

        #expect(input.host.queries == ["wx"])
        #expect(input.springboard.filtered.last == Array(urls.reversed()))
        let pages = try #require(input.host.value(forKey: "searchPages") as? [NativePage])
        #expect(pages.map { $0.items.count } == [35, 35, 3])
        #expect(pages.flatMap { $0.items as! [URL] } == Array(urls.reversed()))
        #expect(input.search.stringValue == "wx" && input.view.needsLayout)
        #expect(NSApp == nil)
    }

    @Test func refreshingAnIndexPreservesTheQueryAndMarkedTextThenClearingRestoresTheRootPage() throws {
        let input = NativeSearchInput()
        try changeNativeQuery(input.host, to: "weixin")
        #expect(input.springboard.filtered == [[]] && input.springboard.page == 0)
        input.search.markedText = "微信"
        let writes = input.search.writes
        let matches = [URL(fileURLWithPath: "/Applications/微信.app")]
        input.host.matches = matches
        input.host.refreshSearchResults()

        #expect(input.host.queries == ["weixin", "weixin"])
        #expect(input.springboard.filtered.last == matches)
        #expect(input.search.stringValue == "weixin" && input.search.markedText == "微信")
        #expect(input.search.writes == writes)

        input.host.setValue(false, forKey: "wantsLauncherVisible")
        input.host.refreshSearchResults()
        #expect(input.host.queries.count == 2 && input.springboard.filtered.count == 2)

        try changeNativeQuery(input.host, to: "")
        #expect(input.springboard.clearCount == 1 && input.springboard.page == 3)
        #expect(input.host.value(forKey: "searchPages") == nil)
        input.host.setValue(true, forKey: "wantsLauncherVisible")
        input.host.refreshSearchResults()
        try changeNativeQuery(input.host, to: "")
        #expect(input.springboard.clearCount == 1 && input.host.queries.count == 2)
        #expect(NSApp == nil)
    }

    @Test func refreshingNeverRepeatsCommandsAndSlashPrefixedOrdinaryQueriesStillRefresh() throws {
        let input = NativeSearchInput()
        for query in ["/settings", "/version", "/智能整理", "/autobuild"] {
            try changeNativeQuery(input.host, to: query)
            let counts = (input.host.settingsCount, input.host.arrangeCount, input.springboard.filtered.count)
            input.host.refreshSearchResults()
            #expect(input.host.queries.isEmpty)
            #expect(input.host.settingsCount == counts.0 && input.host.arrangeCount == counts.1)
            #expect(input.springboard.filtered.count == counts.2 && input.search.stringValue == query)
        }
        #expect(input.host.settingsCount == 1 && input.host.arrangeCount == 2)
        for query in ["/settingsExtra", "/VERSION", "/智能整理x", "/autobuild ", "/folder", " /settings"] {
            let count = input.host.queries.count
            try changeNativeQuery(input.host, to: query)
            input.host.refreshSearchResults()
            #expect(input.host.queries.count == count + 2)
            #expect(Array(input.host.queries.suffix(2)) == [query, query])
            #expect(input.host.settingsCount == 1 && input.host.arrangeCount == 2)
        }
        #expect(NSApp == nil)
    }
}

@MainActor
private func changeNativeQuery(_ host: NativeHost, to query: String) throws {
    let selector = NSSelectorFromString("searchTextChanged:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Search = @convention(c) (AnyObject, Selector, NSString) -> Void
    unsafeBitCast(method_getImplementation(method), to: Search.self)(host, selector, query as NSString)
}

@MainActor
private final class NativeSearchInput {
    let host = NativeSearchHost()
    let search = NativeSearchText()
    let label = NativeSearchText()
    let springboard = NativeSearchSpringboard()
    let view = NativeSearchContent()

    init() {
        host.items = []
        host.setValue(search, forKey: "search")
        host.setValue(label, forKey: "versionLabel")
        host.setValue(springboard, forKey: "springboard")
        host.setValue(view, forKey: "view")
        host.setValue(true, forKey: "wantsLauncherVisible")
    }
}

private final class NativeSearchHost: NativeHost {
    var matches: [URL] = []
    private(set) var queries: [String] = []
    private(set) var settingsCount = 0
    private(set) var arrangeCount = 0
    override func matchingItems(for query: String) -> [URL] {
        queries.append(query)
        return matches
    }
    override func showSettings(_ sender: Any) { settingsCount += 1 }
    override func autoArrange(_ sender: Any) { arrangeCount += 1 }
}

@MainActor
private final class NativeSearchText: NSObject {
    private var text = ""
    @objc var hidden = true
    var markedText = ""
    private(set) var writes = 0
    @objc var stringValue: String {
        get { text }
        set { text = newValue; writes += 1; markedText = "" }
    }
}

@MainActor
private final class NativeSearchSpringboard: NSObject {
    private(set) var filtered: [[URL]] = []
    private(set) var clearCount = 0
    private(set) var page = 3
    private var originalPage = 3
    private var filtering = false
    @objc(filterUsingItems:)
    func filter(_ items: [URL]) {
        if !filtering { originalPage = page }
        filtering = true
        page = 0
        filtered.append(items)
    }
    @objc func clearFilteredItems() {
        clearCount += 1
        filtering = false
        page = originalPage
    }
}

@MainActor
private final class NativeSearchContent: NSObject {
    @objc var needsLayout = false
}
