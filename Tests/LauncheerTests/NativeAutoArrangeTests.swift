import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing
@testable import Launcheer

@Suite(.serialized)
@MainActor
struct NativeAutoArrangeTests {
    @Test func savingCommitsTheNewLayoutBeforeRefreshingAndReusesLoadedIcons() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let original = input.layout
        let originalPages = original.pages
        var savedAtInvalidation: NativeLayout?
        var readError: (any Error)?
        input.springboard.onInvalidate = {
            do { savedAtInvalidation = try NativeLayout(apps: input.apps, fileURL: input.destination) }
            catch { readError = error }
        }

        try input.host.arrangeItems({ candidate in
            #expect(candidate !== original && candidate.pages !== originalPages)
            let group = candidate.pages[0] as! NativePage
            let copiedGroup = group.items[0] as! NativeGroup
            copiedGroup.title = "整理后"
            copiedGroup.items.removeAllObjects()
            copiedGroup.items.add(NativePage(items: Array(input.apps.prefix(3))))
            candidate.pages.removeAllObjects()
            candidate.pages.add(NativePage(items: [copiedGroup]))
            candidate.pages.add(NativePage(items: [input.apps[3]]))
            return true
        }, forPreset: "none")

        let committed = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        let committedPages = (input.host.value(forKey: "pages") as AnyObject) === (committed.pages as AnyObject)
        let sameIcons = (input.host.value(forKey: "icons") as AnyObject) === (input.icons as AnyObject)
        let sameIcon = (input.icons[input.apps[0]] as AnyObject) === (input.icon as AnyObject)
        #expect(committed !== original && committed.pages.count == 2)
        #expect(committedPages)
        #expect(original.pages === originalPages && original.pages.count == 3)
        let oldGroup = try #require((original.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        #expect(oldGroup.title == "原分组" && (oldGroup.items[0] as? NativePage)?.items.count == 2)
        #expect(readError == nil && savedAtInvalidation?.pages.count == 2)
        let savedGroup = try #require((savedAtInvalidation?.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        #expect(savedGroup.title == "整理后" && (savedGroup.items[0] as? NativePage)?.items as? [URL] == Array(input.apps.prefix(3)))
        #expect(input.host.value(forKey: "searchPages") == nil && input.springboard.clearCount == 1)
        #expect(input.search.stringValue.isEmpty && input.label.hidden)
        #expect(input.springboard.invalidateCount == 1 && input.springboard.closeCount == 1)
        #expect(input.springboard.pager.currentPageIndex == 1)
        #expect(input.host.value(forKey: "layoutDirty") as? Bool == false)
        #expect(sameIcons && sameIcon)
        #expect(input.host.value(forKey: "iconGeneration") as? Int == 7 && input.host.iconLoadCount == 0)
        #expect(NSApp == nil)
    }

    @Test func aFailedSaveLeavesTheLiveLayoutAndSearchUntouched() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let originalData = try Data(contentsOf: input.destination)
        try FileManager.default.removeItem(at: input.destination.deletingLastPathComponent())
        let blocker = Data("not a directory".utf8)
        try blocker.write(to: input.destination.deletingLastPathComponent())
        let pages = input.layout.pages
        let group = try #require((pages[0] as? NativePage)?.items[0] as? NativeGroup)
        let groupPages = group.items

        #expect(throws: (any Error).self) {
            try input.host.arrangeItems({ candidate in
                let copiedGroup = (candidate.pages[0] as! NativePage).items[0] as! NativeGroup
                copiedGroup.title = "不应提交"
                copiedGroup.items.removeAllObjects()
                candidate.pages.removeAllObjects()
                candidate.pages.add(NativePage(items: input.apps))
                return true
            }, forPreset: "none")
        }

        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        let samePages = (input.host.value(forKey: "pages") as AnyObject) === (pages as AnyObject)
        let sameIcons = (input.host.value(forKey: "icons") as AnyObject) === (input.icons as AnyObject)
        #expect(sameLayout && samePages)
        #expect(input.layout.pages.count == 3 && group.title == "原分组" && group.items === groupPages)
        #expect((group.items[0] as? NativePage)?.items as? [URL] == Array(input.apps.prefix(2)))
        #expect(input.host.value(forKey: "layoutDirty") as? Bool == true)
        #expect(sameIcons && input.host.iconLoadCount == 0)
        #expect(input.search.stringValue == "previous" && !input.label.hidden)
        #expect(input.host.value(forKey: "searchPages") != nil && input.springboard.pager.currentPageIndex == 0)
        #expect(input.springboard.clearCount == 0 && input.springboard.invalidateCount == 0 && input.springboard.closeCount == 0)
        #expect(try Data(contentsOf: input.destination.deletingLastPathComponent()) == blocker)
        #expect(try Data(contentsOf: input.directory.appendingPathComponent("untouched.json")) == originalData)
        #expect(NSApp == nil)
    }

    @Test func anUnchangedArrangementDoesNotSaveOrInvalidate() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        // An unwritable destination makes an accidental save observable.
        try FileManager.default.removeItem(at: input.destination.deletingLastPathComponent())
        try Data("blocked".utf8).write(to: input.destination.deletingLastPathComponent())
        var visited = false

        try input.host.arrangeItems({ _ in visited = true; return false }, forPreset: "none")

        #expect(visited && input.springboard.invalidateCount == 0 && input.springboard.closeCount == 0)
        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        #expect(sameLayout)
        #expect(input.host.value(forKey: "layoutDirty") as? Bool == true)
        #expect(input.host.iconLoadCount == 0)
        #expect(try String(contentsOf: input.destination.deletingLastPathComponent(), encoding: .utf8) == "blocked")
        #expect(NSApp == nil)
    }

    @Test(arguments: ["drag", "mouseDown", "hide"])
    func arrangingDuringAnActiveInteractionDoesNotExecuteTheChange(busy: String) throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let original = try Data(contentsOf: input.destination)
        switch busy {
        case "drag": input.springboard.dragging = true
        case "mouseDown": input.view.downLayer = CALayer()
        default:
            let task: @convention(block) () -> Void = {}
            input.host.setValue(task, forKey: "hideTask")
        }
        var visited = false

        #expect(throws: (any Error).self) {
            try input.host.arrangeItems({ _ in visited = true; return true }, forPreset: "none")
        }

        #expect(!visited && input.springboard.invalidateCount == 0 && input.springboard.clearCount == 0)
        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        #expect(sameLayout)
        #expect(try Data(contentsOf: input.destination) == original)
        #expect(NSApp == nil)
    }

    @Test func eachModeKeepsItsOwnLayoutAndSwitchingRestoresTheSavedManualOrder() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let manual = try #require((input.layout.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        manual.title = "手动编辑"
        let categoriesURL = input.destination.deletingLastPathComponent().appendingPathComponent("native-layout-categories.json")
        let systemURL = input.destination.deletingLastPathComponent().appendingPathComponent("native-layout-system.json")

        try input.host.arrangeItems({ candidate in
            #expect((candidate.pages[0] as? NativePage)?.items as? [URL] == input.apps)
            let category = NativeGroup(id: "category-id", title: "工具", pages: [NativePage(items: [input.apps[1], input.apps[0]])])
            candidate.pages.setArray([NativePage(items: [input.apps[3], category, input.apps[2]])])
            return true
        }, forPreset: "categories")

        #expect(preset.value == "categories" && preset.writes == ["categories"])
        let savedManual = try NativeLayout(apps: input.apps, fileURL: input.destination)
        #expect(((savedManual.pages[0] as? NativePage)?.items[0] as? NativeGroup)?.title == "手动编辑")
        #expect(savedManual.pages.count == 3)
        let categoriesData = try Data(contentsOf: categoriesURL)
        #expect((input.host.value(forKey: "layout") as? NativeLayout)?.destination == categoriesURL)
        let categoryOrder = [input.apps[3], input.apps[1], input.apps[0], input.apps[2]]

        try input.host.arrangeItems({ candidate in
            #expect((candidate.pages[0] as? NativePage)?.items as? [URL] == categoryOrder)
            candidate.pages.setArray([NativePage(items: Array(categoryOrder.prefix(2))), NativePage(items: Array(categoryOrder.suffix(2)))])
            return true
        }, forPreset: "system")
        let systemData = try Data(contentsOf: systemURL)
        #expect(preset.value == "system")

        try input.host.arrangeItems({ candidate in
            #expect(candidate.pages.count == 3)
            #expect(((candidate.pages[0] as? NativePage)?.items[0] as? NativeGroup)?.title == "手动编辑")
            return false
        }, forPreset: "none")
        #expect(preset.value == "none")
        #expect((input.host.value(forKey: "layout") as? NativeLayout)?.destination == input.destination)
        #expect(try Data(contentsOf: categoriesURL) == categoriesData && Data(contentsOf: systemURL) == systemData)

        try input.host.arrangeItems({ candidate in
            #expect(candidate.pages.count == 1)
            #expect(((candidate.pages[0] as? NativePage)?.items[1] as? NativeGroup)?.id == "category-id")
            return false
        }, forPreset: "categories")
        let restored = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        #expect(restored.destination == categoriesURL && preset.value == "categories")
        let sameIcons = (input.host.value(forKey: "icons") as AnyObject) === (input.icons as AnyObject)
        #expect(sameIcons && input.host.iconLoadCount == 0 && input.host.value(forKey: "iconGeneration") as? Int == 7)

        let restarted = NativeHost()
        #expect(restarted.value(forKey: "activePreset") as? String == "categories")
        restarted.setValue(restored, forKey: "layout")
        #expect(try arrangeLayoutURL(restarted, preset: "categories") == categoriesURL)

        let newApp = input.directory.appendingPathComponent("New.app")
        input.host.reloadItems([input.apps[0], input.apps[1], input.apps[3], newApp])
        let reloaded = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        #expect(reloaded.destination == categoriesURL && reloaded.pages.count == 1)
        let root = try #require(reloaded.pages.firstObject as? NativePage)
        #expect(root.items.count == 3 && root.items[0] as? URL == input.apps[3] && root.items[2] as? URL == newApp)
        #expect(((root.items[1] as? NativeGroup)?.items[0] as? NativePage)?.items as? [URL] == [input.apps[1], input.apps[0]])
        #expect(try Data(contentsOf: systemURL) == systemData)
        #expect(NSApp == nil)
    }

    @Test(arguments: ["current", "target"])
    func aFailedModeSwitchKeepsTheActiveModeAndLiveModel(failure: String) throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let target = input.destination.deletingLastPathComponent().appendingPathComponent("native-layout-system.json")
        if failure == "current" {
            try FileManager.default.removeItem(at: input.destination.deletingLastPathComponent())
            try Data("blocked".utf8).write(to: input.destination.deletingLastPathComponent())
        }
        var visited = false
        #expect(throws: (any Error).self) {
            try input.host.arrangeItems({ candidate in
                visited = true
                do { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
                catch { Issue.record(error); return false }
                candidate.pages.setArray([NativePage(items: input.apps)])
                return true
            }, forPreset: "system")
        }
        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        #expect(visited == (failure == "target") && sameLayout)
        #expect(preset.value == nil && preset.writes.isEmpty && input.host.value(forKey: "activePreset") as? String == "none")
        #expect(input.host.value(forKey: "layoutDirty") as? Bool == true)
        #expect(input.layout.pages.count == 3 && input.search.stringValue == "previous" && !input.label.hidden)
        #expect(input.springboard.invalidateCount == 0 && input.springboard.clearCount == 0 && input.host.iconLoadCount == 0)
        #expect(NSApp == nil)
    }

    @Test func firstSwitchPreservesTheUnsavedManualLayout() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let manualGroup = NativeGroup(id: "unsaved-manual-group", title: "原始分组", pages: [NativePage(items: [input.apps[1], input.apps[0]])])
        input.layout.pages.setArray([NativePage(items: [input.apps[3], manualGroup]), NativePage(items: [input.apps[2]])])
        input.host.setValue(false, forKey: "layoutDirty")
        try FileManager.default.removeItem(at: input.destination)
        let originalOrder = [input.apps[3], input.apps[1], input.apps[0], input.apps[2]]

        try input.host.arrangeItems({ candidate in
            #expect((candidate.pages[0] as? NativePage)?.items as? [URL] == originalOrder)
            candidate.pages.setArray([NativePage(items: input.apps)])
            return true
        }, forPreset: "categories")

        #expect(FileManager.default.fileExists(atPath: input.destination.path))
        try input.host.arrangeItems({ _ in false }, forPreset: "none")
        let restored = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        #expect(restored.pages.count == 2)
        let root = try #require(restored.pages.firstObject as? NativePage)
        #expect(root.items.firstObject as? URL == input.apps[3])
        let groups = root.items.compactMap { $0 as? NativeGroup }
        #expect(groups.count == 1 && groups.first?.id == "unsaved-manual-group" && groups.first?.title == "原始分组")
        #expect((groups.first?.items.firstObject as? NativePage)?.items as? [URL] == [input.apps[1], input.apps[0]])
        #expect(preset.value == "none" && input.host.iconLoadCount == 0)
        #expect(NSApp == nil)
    }

    @Test func verificationDoesNotPersistTheSelectedMode() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        input.host.verifying = true
        input.host.setValue(false, forKey: "layoutDirty")
        try input.host.arrangeItems({ _ in false }, forPreset: "system")
        #expect(preset.value == nil && preset.writes.isEmpty)
        #expect((input.host.value(forKey: "layout") as? NativeLayout)?.destination == nil)
        #expect(!FileManager.default.fileExists(atPath: input.destination.deletingLastPathComponent().appendingPathComponent("native-layout-system.json").path))
        #expect(NSApp == nil)
    }

    @Test func theGroupMenuFlattensAndSavesOnlyTheCurrentMode() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let inactive = input.destination.deletingLastPathComponent().appendingPathComponent("native-layout-categories.json")
        let inactiveData = Data("inactive fixture".utf8)
        try inactiveData.write(to: inactive)
        let group = try #require((input.layout.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        let sender = NSMenuItem()
        sender.representedObject = group
        let selector = NSSelectorFromString("flattenGroup:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Flatten = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(method_getImplementation(method), to: Flatten.self)(input.host, selector, sender)
        let flattened = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        #expect((flattened.pages[0] as? NativePage)?.items as? [URL] == Array(input.apps.prefix(2)))
        #expect(flattened.pages.count == 3 && input.springboard.invalidateCount == 1)
        let saved = try NativeLayout(apps: input.apps, fileURL: input.destination)
        #expect((saved.pages[0] as? NativePage)?.items as? [URL] == Array(input.apps.prefix(2)))
        #expect(try Data(contentsOf: inactive) == inactiveData)
        #expect(preset.writes.isEmpty && input.host.iconLoadCount == 0)
        #expect(NSApp == nil)
    }

    @Test func savingANamedPresetCopiesUnsavedEditsWithoutChangingTheActiveLayout() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let originalData = try Data(contentsOf: input.destination)
        let group = try #require((input.layout.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        group.title = "尚未写入原布局"

        let id = try input.host.saveCurrentLayoutAs("  旅行/2026 \n")

        #expect(NativeLayout.isSavedPreset(id))
        let savedURL = try #require(try arrangeLayoutURL(input.host, preset: id))
        let saved = try NativeLayout(apps: input.apps, fileURL: savedURL)
        #expect(saved.title == "旅行/2026" && saved.pages.count == 3)
        let savedGroup = try #require((saved.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        #expect(savedGroup.id == "existing" && savedGroup.title == "尚未写入原布局")
        #expect((savedGroup.items[0] as? NativePage)?.items as? [URL] == Array(input.apps.prefix(2)))
        #expect(try Data(contentsOf: input.destination) == originalData)
        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        let samePages = (input.host.value(forKey: "pages") as AnyObject) === (input.layout.pages as AnyObject)
        let sameIcons = (input.host.value(forKey: "icons") as AnyObject) === (input.icons as AnyObject)
        #expect(sameLayout && samePages && sameIcons && input.host.value(forKey: "layoutDirty") as? Bool == true)
        #expect(input.layout.title == nil && preset.value == nil && preset.writes.isEmpty)
        #expect(input.springboard.invalidateCount == 0 && input.springboard.clearCount == 0 && input.host.iconLoadCount == 0)
        let choices = try input.host.savedPresets()
        #expect(choices.count == 1 && choices[0].id == id && choices[0].title == "旅行/2026")
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: savedURL)) as? [String: Any])
        #expect(Set(document.keys) == ["pages", "title"])
        #expect(NSApp == nil)
    }

    @Test func emptyOrDuplicateNamesNeverOverwriteAnExistingSavedPreset() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        for title in ["", " \n\t "] {
            #expect(throws: (any Error).self) { try input.host.saveCurrentLayoutAs(title) }
        }
        #expect(try input.host.savedPresets().isEmpty)
        let id = try input.host.saveCurrentLayoutAs("Work")
        let savedURL = try #require(try arrangeLayoutURL(input.host, preset: id))
        let original = try Data(contentsOf: savedURL)
        for title in ["Work", " work ", "WORK"] {
            #expect(throws: (any Error).self) { try input.host.saveCurrentLayoutAs(title) }
        }
        #expect(try Data(contentsOf: savedURL) == original)
        #expect(try input.host.savedPresets().map(\.id) == [id])
        input.host.verifying = true
        #expect(try input.host.savedPresets().isEmpty)
        #expect(throws: (any Error).self) { try input.host.saveCurrentLayoutAs("Verify") }
        #expect(NSApp == nil)
    }

    @Test(arguments: ["drag", "write"])
    func savingAnUnavailableSnapshotLeavesTheCurrentStateUntouched(failure: String) throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let original = try Data(contentsOf: input.directory.appendingPathComponent("untouched.json"))
        if failure == "drag" { input.springboard.dragging = true }
        else {
            try FileManager.default.removeItem(at: input.destination.deletingLastPathComponent())
            try Data("blocked".utf8).write(to: input.destination.deletingLastPathComponent())
        }

        #expect(throws: (any Error).self) { try input.host.saveCurrentLayoutAs("Not Saved") }

        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        #expect(sameLayout && preset.value == nil && preset.writes.isEmpty)
        #expect(input.host.value(forKey: "layoutDirty") as? Bool == true && input.layout.title == nil)
        #expect(input.springboard.invalidateCount == 0 && input.host.iconLoadCount == 0)
        #expect(try Data(contentsOf: input.directory.appendingPathComponent("untouched.json")) == original)
        if failure == "drag" { #expect(try Data(contentsOf: input.destination) == original) }
        else { #expect(try String(contentsOf: input.destination.deletingLastPathComponent(), encoding: .utf8) == "blocked") }
        #expect(NSApp == nil)
    }

    @Test func restoringAndFlatteningANamedPresetPreservesItsTitleAndOtherModes() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let id = try input.host.saveCurrentLayoutAs("我的分类")
        let savedURL = try #require(try arrangeLayoutURL(input.host, preset: id))
        try input.host.arrangeItems({ candidate in
            candidate.pages.setArray([NativePage(items: Array(input.apps.reversed()))])
            return true
        }, forPreset: "system")
        let systemURL = try #require(try arrangeLayoutURL(input.host, preset: "system"))
        let systemData = try Data(contentsOf: systemURL)
        let manualData = try Data(contentsOf: input.destination)

        try input.host.arrangeItems({ _ in false }, forPreset: id)

        let named = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        #expect(named.title == "我的分类" && named.destination == savedURL && named.pages.count == 3)
        #expect(preset.value == id)
        let group = try #require((named.pages[0] as? NativePage)?.items[0] as? NativeGroup)
        try input.host.arrangeItems({ $0.flatten(group) }, forPreset: id)
        let reloaded = try NativeLayout(apps: input.apps, fileURL: savedURL)
        #expect(reloaded.title == "我的分类")
        #expect((reloaded.pages[0] as? NativePage)?.items as? [URL] == Array(input.apps.prefix(2)))
        #expect(try Data(contentsOf: systemURL) == systemData)
        #expect(try Data(contentsOf: input.destination) == manualData)
        let restarted = NativeHost()
        #expect(restarted.value(forKey: "activePreset") as? String == id)
        restarted.setValue(reloaded, forKey: "layout")
        #expect(try arrangeLayoutURL(restarted, preset: id) == savedURL)
        #expect(try input.host.savedPresets().first?.title == "我的分类" && input.host.iconLoadCount == 0)
        #expect(NSApp == nil)
    }

    @Test func flatteningTheNoneModeCannotOverwriteANamedPresetsGroupsOrPageBoundaries() throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let apps = (0..<40).map { input.directory.appendingPathComponent("NamedToNone\($0).app") }
        let group = NativeGroup(id: "saved-multipage-group", title: "保留分组", pages: [
            NativePage(items: Array(apps[1..<21])), NativePage(items: Array(apps[21..<38]))
        ])
        input.layout.pages.setArray([
            NativePage(items: [apps[0], group]), NativePage(items: [apps[38]]), NativePage(items: [apps[39]])
        ])
        input.host.items = apps
        let id = try input.host.saveCurrentLayoutAs("保留方案")
        let savedURL = try #require(try arrangeLayoutURL(input.host, preset: id))
        let savedSettings = AutoArrangeSettings(preset: .none, rules: [], customPreset: id)
        let noneSettings = AutoArrangeSettings(preset: .none, rules: [])
        try input.host.arrangeItems({ candidate in
            AutoArrange.arrange(candidate, settings: savedSettings, groups: [])
        }, forPreset: id)
        let originalSavedData = try Data(contentsOf: savedURL)

        try input.host.arrangeItems({ candidate in
            AutoArrange.arrange(candidate, settings: noneSettings, groups: [])
        }, forPreset: "none")

        let flattened = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        let flatPages = flattened.pages as! [NativePage]
        #expect(flattened.destination == input.destination && preset.value == "none")
        #expect(flatPages.map { $0.items.count } == [35, 5])
        #expect(flatPages.flatMap { $0.items.compactMap { $0 as? URL } } == apps)
        #expect(try Data(contentsOf: savedURL) == originalSavedData)
        let flattenedData = try Data(contentsOf: input.destination)

        try input.host.arrangeItems({ candidate in
            AutoArrange.arrange(candidate, settings: savedSettings, groups: [AutoArrangeGroup(title: "不可覆盖", apps: apps)])
        }, forPreset: id)

        let restored = try #require(input.host.value(forKey: "layout") as? NativeLayout)
        #expect(restored.title == "保留方案" && restored.destination == savedURL && preset.value == id)
        #expect((restored.pages as! [NativePage]).map { $0.items.count } == [2, 1, 1])
        let restoredGroups = (restored.pages as! [NativePage]).flatMap { $0.items.compactMap { $0 as? NativeGroup } }
        #expect(restoredGroups.count == 1 && restoredGroups.first?.id == "saved-multipage-group" && restoredGroups.first?.title == "保留分组")
        let restoredGroup = try #require(restoredGroups.first)
        let groupPages = restoredGroup.items as! [NativePage]
        #expect(groupPages.map { $0.items.count } == [20, 17])
        #expect(groupPages.flatMap { $0.items.compactMap { $0 as? URL } } == Array(apps[1..<38]))
        #expect(try Data(contentsOf: savedURL) == originalSavedData)
        #expect(try Data(contentsOf: input.destination) == flattenedData)
        let sameIcons = (input.host.value(forKey: "icons") as AnyObject) === (input.icons as AnyObject)
        #expect(sameIcons && input.host.iconLoadCount == 0)
        #expect(NSApp == nil)
    }

    @Test(arguments: ["missing", "corrupt", "noTitle"])
    func anUnavailableSavedPresetIsReportedWithoutRebuildingOrChangingModes(failure: String) throws {
        let preset = ArrangePresetState()
        let restore = try interceptArrangePreset(preset)
        defer { restore() }
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let id = try input.host.saveCurrentLayoutAs("Saved")
        let savedURL = try #require(try arrangeLayoutURL(input.host, preset: id))
        let damaged = failure == "noTitle" ? Data(#"{"pages":[[]]}"#.utf8) : Data("broken JSON".utf8)
        if failure == "missing" { try FileManager.default.removeItem(at: savedURL) }
        else { try damaged.write(to: savedURL) }
        var visited = false

        #expect(throws: (any Error).self) {
            try input.host.arrangeItems({ _ in visited = true; return false }, forPreset: id)
        }

        let sameLayout = (input.host.value(forKey: "layout") as AnyObject) === (input.layout as AnyObject)
        #expect(!visited && sameLayout && preset.value == nil && preset.writes.isEmpty)
        #expect(input.host.value(forKey: "layoutDirty") as? Bool == true && input.search.stringValue == "previous")
        #expect(input.springboard.invalidateCount == 0 && input.host.iconLoadCount == 0)
        if failure == "missing" { #expect(!FileManager.default.fileExists(atPath: savedURL.path)) }
        else {
            #expect(try Data(contentsOf: savedURL) == damaged)
            #expect(throws: (any Error).self) { try input.host.savedPresets() }
        }
        #expect(NSApp == nil)
    }

    @Test func savedPresetDiscoveryAcceptsOnlyExactUUIDFileNames() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let directory = input.destination.deletingLastPathComponent()
        let id = try input.host.saveCurrentLayoutAs("Valid")
        for name in ["native-layout-saved-not-a-uuid.json", "native-layout-\(id).json.backup", ".native-layout-\(id).json", "native-layout-categories.json"] {
            try Data("not a saved layout".utf8).write(to: directory.appendingPathComponent(name))
        }
        #expect(try input.host.savedPresets().map(\.id) == [id])
        for invalid in ["saved-not-a-uuid", "saved-../../native-layout", "saved-01234567-89ab-cdef-0123-456789abcdef", "saved-0123456789ABCDEF0123456789ABCDEF"] {
            #expect(!NativeLayout.isSavedPreset(invalid))
            #expect(throws: (any Error).self) { try input.host.arrangeItems({ _ in false }, forPreset: invalid) }
        }
        #expect(NSApp == nil)
    }

    @Test func aGeneratedIDCollisionCannotOverwriteAnExistingSnapshot() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let uuid = try #require(NSUUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"))
        let id = "saved-" + uuid.uuidString
        let savedURL = try #require(try arrangeLayoutURL(input.host, preset: id))
        let existing = input.layout.copy(to: savedURL)
        existing.title = "Existing"
        try existing.save()
        let original = try Data(contentsOf: savedURL)
        let originalSource = try Data(contentsOf: input.destination)
        let method = try #require(class_getClassMethod(NSUUID.self, NSSelectorFromString("UUID")))
        let block: @convention(block) (AnyObject) -> NSUUID = { _ in uuid }
        let implementation = imp_implementationWithBlock(block)
        let previous = method_setImplementation(method, implementation)
        defer { method_setImplementation(method, previous); imp_removeBlock(implementation) }

        #expect(throws: (any Error).self) { try input.host.saveCurrentLayoutAs("New Name") }

        #expect(try Data(contentsOf: savedURL) == original)
        #expect(try Data(contentsOf: input.destination) == originalSource)
        let names = try FileManager.default.contentsOfDirectory(atPath: savedURL.deletingLastPathComponent().path)
        #expect(!names.contains { $0.hasSuffix(".tmp") })
        #expect(try input.host.savedPresets().map(\.title) == ["Existing"])
        #expect(NSApp == nil)
    }

    @Test func bothCommandAliasesRequireAnExactMatch() throws {
        let input = try ArrangeInput()
        defer { input.removeFiles() }
        let selector = NSSelectorFromString("searchTextChanged:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Search = @convention(c) (AnyObject, Selector, NSString) -> Void
        let change = unsafeBitCast(method_getImplementation(method), to: Search.self)
        for (index, query) in ["/智能整理", "/autobuild"].enumerated() {
            change(input.host, selector, query as NSString)
            #expect(input.host.arrangeCount == index + 1 && input.host.senderWasHost)
            #expect(input.search.stringValue == query && input.label.hidden)
            #expect(input.springboard.filtered.isEmpty)
        }
        for query in ["/Autobuild", " /autobuild", "/autobuild ", "/autobuildExtra", " /智能整理", "/智能整理 ", "/智能整理更多"] {
            change(input.host, selector, query as NSString)
            #expect(input.host.arrangeCount == 2 && input.search.stringValue == query)
            #expect(input.springboard.filtered.last == [])
        }
        #expect(NSApp == nil)
    }
}

@MainActor
private final class ArrangePresetState {
    var value: String?
    var writes: [String] = []
}

@MainActor
private func interceptArrangePreset(_ state: ArrangePresetState) throws -> () -> Void {
    let readSelector = NSSelectorFromString("stringForKey:")
    let writeSelector = NSSelectorFromString("setObject:forKey:")
    let readMethod = try #require(class_getInstanceMethod(UserDefaults.self, readSelector))
    let writeMethod = try #require(class_getInstanceMethod(UserDefaults.self, writeSelector))
    let previousRead = method_getImplementation(readMethod)
    let previousWrite = method_getImplementation(writeMethod)
    typealias Read = @convention(c) (AnyObject, Selector, NSString) -> NSString?
    typealias Write = @convention(c) (AnyObject, Selector, AnyObject?, NSString) -> Void
    let read = unsafeBitCast(previousRead, to: Read.self)
    let write = unsafeBitCast(previousWrite, to: Write.self)
    let readBlock: @convention(block) (AnyObject, NSString) -> NSString? = { receiver, key in
        if key == "arrange.activePreset" { return state.value as NSString? }
        return read(receiver, readSelector, key)
    }
    let writeBlock: @convention(block) (AnyObject, AnyObject?, NSString) -> Void = { receiver, value, key in
        if key == "arrange.activePreset" {
            state.value = value as? String
            if let selected = state.value { state.writes.append(selected) }
        } else { write(receiver, writeSelector, value, key) }
    }
    let implementations = [imp_implementationWithBlock(readBlock), imp_implementationWithBlock(writeBlock)]
    method_setImplementation(readMethod, implementations[0])
    method_setImplementation(writeMethod, implementations[1])
    return {
        method_setImplementation(readMethod, previousRead)
        method_setImplementation(writeMethod, previousWrite)
        implementations.forEach { imp_removeBlock($0) }
    }
}

@MainActor
private func arrangeLayoutURL(_ host: NativeHost, preset: String) throws -> URL? {
    let selector = NSSelectorFromString("layoutURLForPreset:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias URLForPreset = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    return unsafeBitCast(method_getImplementation(method), to: URLForPreset.self)(host, selector, preset as NSString)?.takeUnretainedValue() as? URL
}

@MainActor
private final class ArrangeInput {
    let host = ArrangeHost()
    let search = ArrangeText()
    let label = ArrangeText()
    let view = ArrangeView()
    let springboard = ArrangeSpringboard()
    let icon = CALayer()
    let icons = NSMutableDictionary()
    let directory: URL
    let destination: URL
    let apps: [URL]
    let layout: NativeLayout

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-arrange-" + UUID().uuidString)
        self.directory = directory
        destination = directory.appendingPathComponent("support/native-layout.json")
        apps = ["A", "B", "C", "D"].map { directory.appendingPathComponent($0 + ".app") }
        layout = try NativeLayout(apps: apps, fileURL: destination)
        layout.pages.removeAllObjects()
        layout.pages.add(NativePage(items: [NativeGroup(id: "existing", title: "原分组", pages: [NativePage(items: Array(apps.prefix(2)))])]))
        layout.pages.add(NativePage(items: [apps[2]]))
        layout.pages.add(NativePage(items: [apps[3]]))
        try layout.save()
        try Data(contentsOf: destination).write(to: directory.appendingPathComponent("untouched.json"))
        search.stringValue = "previous"
        label.hidden = false
        icons[apps[0]] = icon
        host.items = apps
        host.setValue("none", forKey: "activePreset")
        host.setValue(layout, forKey: "layout")
        host.setValue(layout.pages, forKey: "pages")
        host.setValue([NativePage(items: [apps[0]])], forKey: "searchPages")
        host.setValue(true, forKey: "layoutDirty")
        host.setValue(icons, forKey: "icons")
        host.setValue(7, forKey: "iconGeneration")
        host.setValue(search, forKey: "search")
        host.setValue(label, forKey: "versionLabel")
        host.setValue(view, forKey: "view")
        host.setValue(springboard, forKey: "springboard")
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

private final class ArrangeHost: NativeHost {
    private(set) var iconLoadCount = 0
    private(set) var arrangeCount = 0
    private(set) var senderWasHost = false
    override func autoArrange(_ sender: Any) {
        arrangeCount += 1
        senderWasHost = sender as AnyObject === self
    }
    @objc(prepareIconsForItems:pixelSize:)
    func prepareIcons(_ items: [URL], pixelSize: UInt) { iconLoadCount += 1 }
}

@MainActor
private final class ArrangeText: NSObject {
    @objc var hidden = true
    @objc var stringValue = ""
}

@MainActor
private final class ArrangeView: NSObject {
    @objc var downLayer: CALayer?
    @objc var needsLayout = false
}

@MainActor
private final class ArrangePager: NSObject {
    @objc var currentPageIndex: UInt = 0
}

private final class ArrangeLayer: CALayer {
    @MainActor @objc let searchTextInputLayer = ArrangeText()
}

@MainActor
private final class ArrangeSpringboard: NSObject {
    @objc let layer = ArrangeLayer()
    @objc let pager = ArrangePager()
    @objc var eventHandler: ArrangeSpringboard { self }
    @objc var dragCapture: ArrangeSpringboard { self }
    @objc var dragging = false
    private(set) var clearCount = 0
    private(set) var invalidateCount = 0
    private(set) var closeCount = 0
    private(set) var filtered: [[URL]] = []
    var onInvalidate: (() -> Void)?
    @objc func clearFilteredItems() { clearCount += 1; pager.currentPageIndex = 2 }
    @objc(filterUsingItems:) func filter(_ items: [URL]) { filtered.append(items) }
    @objc func setGroupShown(_ shown: Bool) { if !shown { closeCount += 1 } }
    @objc func invalidate() { invalidateCount += 1; pager.currentPageIndex = 0; onInvalidate?() }
}
