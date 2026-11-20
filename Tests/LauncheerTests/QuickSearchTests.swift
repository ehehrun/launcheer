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

    @Test func chinesePinyinInitialsAndMixedNamesUseTheSameIndex() {
        let urls = fixtures("微信", "支付宝", "微信 Work", "Visual Studio Code")
        let search = QuickSearchModel(items: urls)
        for query in ["支付宝", "zhifubao", "zhi fu bao", "zfb", "ＺＦＢ"] {
            #expect(search.matchingItems(query).first?.url == urls[1])
        }
        for query in ["微信", "weixin", "w e i x i n", "wx"] {
            #expect(search.matchingItems(query).first?.url == urls[0])
        }
        for query in ["wxw", "weixinwork", "微信work"] {
            #expect(search.matchingItems(query).first?.url == urls[2])
        }
        #expect(search.matchingItems("wwx").isEmpty)
        #expect(search.matchingItems("scv").isEmpty)
    }

    @Test func asciiInitialsKeepTheirPriorityWithoutTransliteration() {
        let urls = fixtures("X Visual Studio Code", "vsc Extension", "Visual Studio Code")
        let search = QuickSearchModel(items: urls)
        #expect(search.matchingItems("vsc").map(\.url) == [urls[2], urls[1], urls[0]])
    }

    @Test func launcherMatchesAreUnlimitedWhileQuickSearchKeepsItsVisibleLimit() {
        let urls = (0..<24).map { URL(fileURLWithPath: "/Applications/微信 \($0).app") }
        var search = QuickSearchModel(items: urls)
        search.search("wx")
        search.select(3)

        let all = search.matchingItems("wx")

        #expect(all.map(\.url) == urls)
        #expect(search.results.map(\.url) == Array(urls.prefix(8)))
        #expect(search.query == "wx" && search.selectedItem?.url == urls[3])
        #expect(search.matchingItems(" \n\t ").map(\.url) == urls)
        #expect(search.matchingItems("wx", limit: 3).map(\.url) == Array(urls.prefix(3)))
    }

    @Test func replacingTheSharedIndexPreservesLocalQueryAndSelection() {
        let urls = fixtures("Alpha", "Beta", "Gamma", "Delta")
        var panel = QuickSearchModel(items: Array(urls.prefix(3)))
        panel.search("a")
        panel.select(1)
        var refreshed = QuickSearchModel(items: [urls[2], urls[1], urls[3]])
        refreshed.search("delta")

        panel.replaceIndex(with: refreshed)

        #expect(panel.query == "a" && panel.selectedItem?.url == urls[1])
        #expect(!panel.results.contains { $0.url == urls[0] })
        #expect(panel.results.contains { $0.url == urls[3] })
        #expect(refreshed.query == "delta" && refreshed.selectedItem?.url == urls[3])
        panel.replaceIndex(with: QuickSearchModel(items: [urls[2], urls[3]]))
        #expect(panel.query == "a" && panel.selectedIndex == 0 && panel.selectedItem?.url == urls[2])
        panel.search("gamma")
        #expect(refreshed.query == "delta" && refreshed.selectedItem?.url == urls[3])
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
