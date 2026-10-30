import Foundation
import Testing
@testable import Launcheer

struct QuickSearchTests {
    @Test func exactPrefixAndSubstringMatchesUseStablePriority() {
        let urls = fixtures("Alpha Tools", "X Alpha", "Alpha", "Alpha Beta", "Alpine")
        var search = QuickSearchModel(items: urls)
        search.search("ALPHA")
        #expect(search.results.map(\.url) == [urls[2], urls[0], urls[3], urls[1]])
        #expect(search.selectedItem?.url == urls[2])
        search.search("alpine")
        #expect(search.results.map(\.url) == [urls[4]])
        search.search("alpha")
        #expect(search.results.map(\.url) == [urls[2], urls[0], urls[3], urls[1]])
    }

    @Test func accentsPinyinInitialsAndOrderedAbbreviationsAreSearchable() {
        let urls = fixtures("Café", "微信", "Visual Studio Code", "Safari")
        var search = QuickSearchModel(items: urls)
        for query in ["cafe", "ＣＡＦＥ"] {
            search.search(query)
            #expect(search.selectedItem?.url == urls[0])
        }
        for query in ["微信", "weixin", "wx"] {
            search.search(query)
            #expect(search.selectedItem?.url == urls[1])
        }
        for query in ["vsc", "v s c", "visual code"] {
            search.search(query)
            #expect(search.selectedItem?.url == urls[2])
        }
        search.search("scv")
        #expect(search.results.isEmpty && search.selectedItem == nil)
    }

    @Test func selectionStopsAtVisibleBoundariesAndEmptySearchHasNoLaunchTarget() {
        let urls = (0..<12).map { URL(fileURLWithPath: "/Applications/Fixture \($0).app") }
        var search = QuickSearchModel(items: urls)
        #expect(search.results.count == 8 && search.selectedItem?.url == urls[0])
        search.moveSelection(by: -1)
        #expect(search.selectedIndex == 0)
        for _ in 0..<20 { search.moveSelection(by: 1) }
        #expect(search.selectedIndex == 7 && search.selectedItem?.url == urls[7])
        search.select(-1)
        #expect(search.selectedItem == nil)
        search.search("does not exist")
        search.moveSelection(by: 1)
        #expect(search.selectedItem == nil && search.selectedIndex == nil)
    }

    @Test func refreshingApplicationsRemovesOldResultsAndPreservesAnExistingSelection() {
        let urls = fixtures("Alpha", "Beta", "Gamma", "Delta")
        var search = QuickSearchModel(items: Array(urls.prefix(3)))
        search.search("a")
        search.select(1)
        let selected = search.selectedItem?.url
        search.updateItems([urls[2], urls[1], urls[3]])
        #expect(!search.results.contains { $0.url == urls[0] })
        #expect(search.results.contains { $0.url == urls[3] })
        #expect(search.selectedItem?.url == selected)
        search.search("alpha")
        #expect(search.results.isEmpty && search.selectedItem == nil)
    }

    private func fixtures(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/Applications/\($0).app") }
    }
}
