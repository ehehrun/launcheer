import Foundation
import NativeLaunchpad
import Testing
@testable import Launcheer

struct AutoArrangeTests {
    @Test func settingsRoundTripAndInvalidDataIsNeverOverwritten() throws {
        let suite = "launcheer-arrange-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = try AutoArrangeSettings.load(from: defaults)
        #expect(initial.preset == .none)
        #expect(initial.customPreset == nil && initial.selectedPresetID == "none")
        #expect(initial.rules.map(\.category) == AutoArrange.categories.map(\.id))
        #expect(defaults.object(forKey: "arrange.settings") == nil)
        for preset in AutoArrangePreset.allCases {
            let saved = AutoArrangeSettings(preset: preset, rules: [rule("我的工具", category: "utilities", name: "Tools")])
            try saved.save(to: defaults)
            #expect(try AutoArrangeSettings.load(from: defaults) == saved)
            #expect(saved.customPreset == nil && saved.selectedPresetID == preset.rawValue)
        }
        let corrupt = Data("invalid JSON".utf8)
        defaults.set(corrupt, forKey: "arrange.settings")
        #expect(throws: (any Error).self) { try AutoArrangeSettings.load(from: defaults) }
        #expect(defaults.data(forKey: "arrange.settings") == corrupt)
        for invalid in [rule("  "), rule("Wrong", category: "unknown")] {
            #expect(throws: (any Error).self) {
                try AutoArrangeSettings(preset: .categories, rules: [invalid]).save(to: defaults)
            }
            #expect(defaults.data(forKey: "arrange.settings") == corrupt)
        }
    }

    @Test(arguments: AutoArrangePreset.allCases)
    func namedClassificationRoundTripsWithoutRunningItsOriginalRules(preset: AutoArrangePreset) throws {
        let suite = "launcheer-arrange-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "saved-" + UUID().uuidString
        let settings = AutoArrangeSettings(preset: preset, rules: [rule("Developer", category: "developer")], customPreset: id)
        try settings.save(to: defaults)
        let loaded = try AutoArrangeSettings.load(from: defaults)
        #expect(loaded == settings && loaded.selectedPresetID == id)
        #expect(loaded.preset == preset && loaded.rules == settings.rules)
        let apps = [app("First", category: "developer"), app("Second", category: "developer"), app("Third", category: "developer")]
        let groups = AutoArrange.groups(apps: apps, settings: AutoArrangeSettings(preset: .categories, rules: settings.rules))
        #expect(!groups.isEmpty && AutoArrange.groups(apps: apps, settings: loaded).isEmpty)
        let layout = try NativeLayout(apps: apps.map(\.url), fileURL: nil)
        let group = NativeGroup(id: "named-manual-folder", title: "手动排列", pages: [
            NativePage(items: [apps[1].url]), NativePage(items: [apps[0].url])
        ])
        let first = NativePage(items: [group])
        let second = NativePage(items: [apps[2].url])
        layout.pages.setArray([first, second])

        #expect(!AutoArrange.arrange(layout, settings: loaded, groups: groups))

        #expect(layout.pages.count == 2)
        let sameFirst = (layout.pages[0] as AnyObject) === first
        let sameSecond = (layout.pages[1] as AnyObject) === second
        let sameGroup = (first.items[0] as AnyObject) === group
        #expect(sameFirst && sameSecond && sameGroup)
        #expect((group.items as! [NativePage]).map { $0.items as? [URL] } == [[apps[1].url], [apps[0].url]])
        #expect(second.items as? [URL] == [apps[2].url])
    }

    @Test func invalidNamedClassificationIDsAreRejectedWithoutChangingSavedData() throws {
        let suite = "launcheer-arrange-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AutoArrangeSettings(preset: .system, rules: [])
        try settings.save(to: defaults)
        let original = try #require(defaults.data(forKey: "arrange.settings"))
        for invalid in ["", "none", "categories", "system", "saved-", "saved-invalid", "saved-../layout", "unknown-" + UUID().uuidString] {
            #expect(throws: (any Error).self) {
                try AutoArrangeSettings(preset: .system, rules: [], customPreset: invalid).save(to: defaults)
            }
            #expect(defaults.data(forKey: "arrange.settings") == original)
        }
        var document = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        document["customPreset"] = "saved-not-a-uuid"
        let corrupt = try JSONSerialization.data(withJSONObject: document)
        defaults.set(corrupt, forKey: "arrange.settings")
        #expect(throws: (any Error).self) { try AutoArrangeSettings.load(from: defaults) }
        #expect(defaults.data(forKey: "arrange.settings") == corrupt)
    }

    @Test func settingsWithoutTheNewOptionalFieldKeepTheirBuiltinMode() throws {
        let suite = "launcheer-arrange-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let document: [String: Any] = ["preset": "categories", "rules": []]
        let legacy = try JSONSerialization.data(withJSONObject: document)
        defaults.set(legacy, forKey: "arrange.settings")
        let loaded = try AutoArrangeSettings.load(from: defaults)
        #expect(loaded.preset == .categories && loaded.customPreset == nil && loaded.selectedPresetID == "categories")
        #expect(defaults.data(forKey: "arrange.settings") == legacy)
    }

    @Test func theRemovedPresetMigratesToNoneWithoutAcceptingDamagedSettings() throws {
        let suite = "launcheer-arrange-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AutoArrangeSettings(preset: .categories, rules: [rule("Developer", category: "developer")])
        var document = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        document["preset"] = "unused"
        let legacy = try JSONSerialization.data(withJSONObject: document)
        defaults.set(legacy, forKey: "arrange.settings")
        let migrated = try AutoArrangeSettings.load(from: defaults)
        #expect(migrated.preset == .none && migrated.rules == settings.rules && migrated.customPreset == nil)
        #expect(defaults.data(forKey: "arrange.settings") == legacy)
        let malformedDocuments: [[String: Any]] = [
            ["preset": "unused"], ["preset": "unused", "rules": "not rules"],
            ["preset": "unknown", "rules": []]
        ]
        for malformed in malformedDocuments {
            let data = try JSONSerialization.data(withJSONObject: malformed)
            defaults.set(data, forKey: "arrange.settings")
            #expect(throws: (any Error).self) { try AutoArrangeSettings.load(from: defaults) }
            #expect(defaults.data(forKey: "arrange.settings") == data)
        }
    }

    @Test func categoryRulesRespectPriorityAndRequireBothFilters() {
        let apps = [
            app("Café Editor", category: "developer"), app("Cafe Music", category: "creativity"),
            app("Terminal", category: "developer"), app("Mail", category: "social"), app("Untouched", category: "other")
        ]
        let settings = AutoArrangeSettings(preset: .categories, rules: [
            rule("编辑器", category: "developer", name: "CAFE"),
            rule("开发", category: "developer"), rule("内容", name: "music"),
            rule("内容", category: "social")
        ])
        let groups = AutoArrange.groups(apps: apps, settings: settings)
        #expect(groups.map(\.title) == ["编辑器", "开发", "内容"])
        #expect(groups.map(\.apps) == [[apps[0].url], [apps[2].url], [apps[1].url, apps[3].url]])
        #expect(!groups.flatMap(\.apps).contains(apps[4].url))
    }

    @Test func defaultCategoriesCoverPublishedApplicationTypes() {
        let samples: [(String?, String)] = [
            ("public.app-category.developer-tools", "developer"),
            ("public.app-category.finance", "productivity"),
            ("public.app-category.productivity", "productivity"),
            ("public.app-category.business", "business"),
            ("public.app-category.social-networking", "social"),
            ("public.app-category.utilities", "utilities"),
            ("public.app-category.entertainment", "entertainment"),
            ("public.app-category.role-playing-games", "entertainment"),
            ("public.app-category.news", "information"),
            ("public.app-category.books", "information"),
            ("public.app-category.reference", "information"),
            ("public.app-category.photography", "creativity"),
            ("public.app-category.music", "creativity"),
            ("public.app-category.education", "education"),
            ("public.app-category.medical", "other"),
            ("public.app-category.healthcare-fitness", "other"),
            (nil, "other"), ("not-a-category", "other")
        ]
        for (category, expected) in samples { #expect(AutoArrange.categoryID(for: category) == expected) }
        let apps = AutoArrange.categories.map { app($0.title, category: $0.id) }
        let groups = AutoArrange.groups(apps: apps, settings: AutoArrangeSettings(preset: .categories, rules: AutoArrangeSettings.defaultRules))
        #expect(groups.map(\.title) == AutoArrange.categories.map(\.title))
        #expect(groups.flatMap(\.apps) == apps.map(\.url))
    }

    @Test func metadataUsesDeclaredNameAndTypeForFiltering() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fixture.app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "vip.kodify.arrange-test", "CFBundlePackageType": "APPL",
            "CFBundleName": "Fixture Name", "CFBundleDisplayName": "Display Name",
            "LSApplicationCategoryType": "public.app-category.developer-tools"
        ], format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        let metadata = AutoArrange.readApps([url])
        #expect(metadata.count == 1)
        #expect(metadata[0].url == url && metadata[0].name == "Display Name" && metadata[0].category == "developer")
        let settings = AutoArrangeSettings(preset: .categories, rules: [rule("Tools", category: "developer", name: "display")])
        #expect(AutoArrange.groups(apps: metadata, settings: settings).first?.apps == [url])
        for mismatch in [rule("Tools", category: "social", name: "display"), rule("Tools", category: "developer", name: "different")] {
            #expect(AutoArrange.groups(apps: metadata, settings: AutoArrangeSettings(preset: .categories, rules: [mismatch])).isEmpty)
        }
        for preset in [AutoArrangePreset.none, .system] {
            #expect(AutoArrange.groups(apps: metadata, settings: AutoArrangeSettings(preset: preset, rules: settings.rules)).isEmpty)
        }
        let missing = AutoArrange.readApps([directory.appendingPathComponent("Missing.app")])
        #expect(missing[0].name == "Missing" && missing[0].category == "other")
    }

    @Test func noneFlattensAllFoldersInExpandedRootOrderWithoutSortingOrGrouping() throws {
        let apps = [url("Z"), URL(fileURLWithPath: "/System/Applications/Chess.app"), url("A"), url("C"),
                    URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), url("B")]
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let first = NativeGroup(id: "first-group", title: "手动分组", pages: [
            NativePage(items: [apps[1]]), NativePage(items: [apps[2], apps[3]])
        ])
        let second = NativeGroup(id: "second-group", title: "其他", pages: [NativePage(items: [apps[4]])])
        layout.pages.setArray([NativePage(items: [apps[0], first]), NativePage(items: [second, apps[5]])])
        let groups = [AutoArrangeGroup(title: "New Folder", apps: apps)]

        #expect(AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .none, rules: []), groups: groups))

        #expect(layout.pages.count == 1)
        #expect((layout.pages.firstObject as? NativePage)?.items as? [URL] == apps)
        #expect(flatten(layout) == apps && Set(flatten(layout)).count == apps.count)
        #expect(!AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .none, rules: []), groups: groups))
    }

    @Test(arguments: [(0, [0]), (1, [1]), (35, [35]), (36, [35, 1]), (70, [35, 35]), (71, [35, 35, 1])])
    func noneFlattensMultiPageFoldersIntoCompactPagesAndIsIdempotent(boundary: (Int, [Int])) throws {
        let (count, expectedSizes) = boundary
        let apps = (0..<count).map { url("Flat\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        if !apps.isEmpty {
            let groupPages = stride(from: 0, to: apps.count, by: 17).map { start in
                NativePage(items: Array(apps[start..<min(start + 17, apps.count)]))
            }
            let group = NativeGroup(id: "multi-page-folder", title: "All Apps", pages: groupPages)
            layout.pages.setArray([NativePage(items: [group])])
        }

        #expect(AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .none, rules: []), groups: []) == (count > 0))

        let pages = layout.pages as! [NativePage]
        #expect(pages.map { $0.items.count } == expectedSizes)
        #expect(pages.allSatisfy { $0.items.count <= 35 && $0.items.allSatisfy { $0 is URL } })
        #expect(flatten(layout) == apps)
        #expect(!AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .none, rules: []), groups: []))
    }

    @Test func noneFlatteningSavesAndReloadsWithoutLosingExistingAppRecordFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = (0..<4).map { directory.appendingPathComponent("FlatSaved\($0).app") }
        let file = directory.appendingPathComponent("native-layout.json")
        let records: [[String: Any]] = [
            ["id": "first-id", "kind": "app", "appID": apps[0].path, "title": "首项名称", "custom": "first-metadata"],
            ["id": "folder-id", "kind": "folder", "title": "分组", "appIDs": [apps[1].path, apps[2].path], "pageSizes": [1, 1]],
            ["id": "last-id", "kind": "app", "appID": apps[3].path, "title": "末项名称", "custom": "last-metadata"]
        ]
        let document: [String: Any] = ["pages": [records], "title": "布局名称"]
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let layout = try NativeLayout(apps: apps, fileURL: file)

        #expect(AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .none, rules: []), groups: []))
        try layout.save()

        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let savedPages = try #require(saved["pages"] as? [[[String: Any]]])
        #expect(savedPages.count == 1 && savedPages.first?.count == 4)
        let savedRoot = try #require(savedPages.first)
        #expect(savedRoot.compactMap { $0["appID"] as? String } == apps.map(\.path))
        #expect(savedRoot.first?["id"] as? String == "first-id" && savedRoot.first?["title"] as? String == "首项名称")
        #expect(savedRoot.first?["custom"] as? String == "first-metadata")
        #expect(savedRoot.last?["id"] as? String == "last-id" && savedRoot.last?["title"] as? String == "末项名称")
        #expect(savedRoot.last?["custom"] as? String == "last-metadata" && saved["title"] as? String == "布局名称")
        let reloaded = try NativeLayout(apps: Array(apps.reversed()), fileURL: file)
        #expect((reloaded.pages.firstObject as? NativePage)?.items as? [URL] == apps)
        #expect(!AutoArrange.arrange(reloaded, settings: AutoArrangeSettings(preset: .none, rules: []), groups: []))
    }

    @Test func systemClassificationUsesProtectedPathsInsteadOfAppleNamesOrBundleIDs() {
        for path in [
            "/System/Applications/Chess.app", "/System/Applications/Utilities/Terminal.app",
            "/System/Library/CoreServices/Finder.app", "/System/Library/CoreServices/Applications/System Information.app",
            "/System/Library/PreferencePanes/Fixture.app",
            "/System/Cryptexes/App/System/Applications/Safari.app",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        ] {
            #expect(AutoArrange.isSystemApp(URL(fileURLWithPath: path)))
        }
        for path in [
            "/Applications/AppleSomething.app", "/Applications/com.apple.Fixture.app", "/Users/example/Applications/Apple.app",
            "/System/ApplicationsFake/Fixture.app", "/System/Library/CoreServicesExtra/Fixture.app",
            "/System/Applications/../../Applications/Fixture.app", "/usr/local/Applications/Fixture.app",
            "/System/Cryptexes/App/System/ApplicationsFake/Fixture.app",
            "/System/Volumes/Preboot/Cryptexes/App/System/ApplicationsFake/Fixture.app",
            "/System/Volumes/Preboot/Other/Fixture.app"
        ] {
            #expect(!AutoArrange.isSystemApp(URL(fileURLWithPath: path)))
        }
    }

    @Test func systemModeExtractsAllFoldersAndPreservesEachSectionsOriginalAppOrder() throws {
        let system = [
            URL(fileURLWithPath: "/System/Applications/Second.app"),
            URL(fileURLWithPath: "/System/Library/CoreServices/First.app")
        ]
        let other = [url("Third"), url("First"), url("Second")]
        let apps = [other[0], other[1], system[0], system[1], other[2]]
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let group = NativeGroup(id: "mixed-folder", title: "Mixed", pages: [
            NativePage(items: [other[1], system[0]]), NativePage(items: [system[1]])
        ])
        layout.pages.setArray([NativePage(items: [other[0], group]), NativePage(items: [other[2]])])

        #expect(AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .system, rules: []), groups: [AutoArrangeGroup(title: "Ignored", apps: apps)]))

        #expect((layout.pages as! [NativePage]).map { $0.items as? [URL] } == [system, other])
        #expect(flatten(layout) == system + other && Set(flatten(layout)) == Set(apps))
        #expect(!AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .system, rules: []), groups: []))
    }

    @Test(arguments: [
        (0, 0, [0]), (0, 1, [1]), (1, 0, [1]),
        (35, 1, [35, 1]), (36, 1, [35, 1, 1]),
        (1, 35, [1, 35]), (1, 36, [1, 35, 1]),
        (36, 36, [35, 1, 35, 1]), (70, 0, [35, 35]), (0, 70, [35, 35])
    ])
    func systemModePaginatesBothSectionsWithoutMixedOrEmptyCategoryPages(boundary: (Int, Int, [Int])) throws {
        let (systemCount, otherCount, sizes) = boundary
        let system = (0..<systemCount).map { URL(fileURLWithPath: "/System/Applications/System\($0).app") }
        let other = (0..<otherCount).map { url("Other\($0)") }
        let apps = Array(other.prefix(1)) + system + Array(other.dropFirst(1))
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .system, rules: []), groups: [])

        #expect((layout.pages as! [NativePage]).map { $0.items.count } == sizes)
        #expect(flatten(layout) == system + other)
        for page in layout.pages as! [NativePage] {
            let contents = try #require(page.items as? [URL])
            #expect(contents.count <= 35)
            #expect(contents.allSatisfy(AutoArrange.isSystemApp) || contents.allSatisfy { !AutoArrange.isSystemApp($0) })
        }
        #expect(!AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .system, rules: []), groups: []))
    }

    @Test func systemModeSavesOriginalAppFieldsAndReloadsWithoutNewChanges() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = URL(fileURLWithPath: "/System/Applications/Fixture.app")
        let other = url("Apple Store Fixture")
        let file = directory.appendingPathComponent("native-layout.json")
        let records: [[String: Any]] = [
            ["id": "original-other-id", "kind": "app", "appID": other.path, "title": "自定义名称", "custom": "preserved"],
            ["id": "manual-folder", "kind": "folder", "title": "Mixed", "appIDs": [system.path], "pageSizes": [1]]
        ]
        let document: [String: Any] = ["pages": [records]]
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let layout = try NativeLayout(apps: [other, system], fileURL: file)

        #expect(AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .system, rules: []), groups: []))
        try layout.save()

        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: [[[String: Any]]]])
        let savedPages = try #require(saved["pages"])
        #expect(savedPages.count == 2)
        #expect(savedPages[1][0]["id"] as? String == "original-other-id")
        #expect(savedPages[1][0]["title"] as? String == "自定义名称")
        #expect(savedPages[1][0]["custom"] as? String == "preserved")
        let reloaded = try NativeLayout(apps: [other, system], fileURL: file)
        #expect(flatten(reloaded) == [system, other])
        #expect(!AutoArrange.arrange(reloaded, settings: AutoArrangeSettings(preset: .system, rules: []), groups: []))
    }

    @Test func arrangingReusesTargetGroupsAndPreservesUnmatchedItemAndGroupOrder() throws {
        let apps = (0..<8).map { url("App\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let source = NativeGroup(id: "source", title: "保留分组", pages: [NativePage(items: [apps[1], apps[2]]), NativePage(items: [apps[3]])])
        let target = NativeGroup(id: "target", title: "Tools", pages: [NativePage(items: [apps[5]])])
        let first = NativePage(items: [apps[0], source, apps[4]])
        let second = NativePage(items: [target, apps[6], apps[7]])
        layout.pages.setArray([first, second])
        let plan = [AutoArrangeGroup(title: "Tools", apps: [apps[2], apps[5], apps[6]])]

        #expect(AutoArrange.arrange(layout, groups: plan))
        #expect(layout.pages.count == 1)
        let root = try #require(layout.pages.firstObject as? NativePage)
        #expect(root.items.count == 5)
        let order = root.items.map { ($0 as? URL)?.path ?? ($0 as! NativeGroup).id }
        #expect(order == [apps[0].path, "source", apps[4].path, "target", apps[7].path])
        let rootGroups = root.items.compactMap { $0 as? NativeGroup }
        let keptSource = rootGroups.contains { $0 === source }
        let keptTarget = rootGroups.contains { $0 === target }
        #expect(keptSource && keptTarget)
        #expect((source.items[0] as? NativePage)?.items as? [URL] == [apps[1]])
        #expect((source.items[1] as? NativePage)?.items as? [URL] == [apps[3]])
        #expect((target.items[0] as? NativePage)?.items as? [URL] == [apps[5], apps[2], apps[6]])
        #expect(target.id == "target" && source.id == "source")
        #expect(!AutoArrange.arrange(layout, groups: plan))
        #expect((target.items[0] as? NativePage)?.items as? [URL] == [apps[5], apps[2], apps[6]])
        #expect(flatten(layout).count == apps.count && Set(flatten(layout)) == Set(apps))
    }

    @Test func reapplyingAnExistingBoxCompactsFragmentedRootPagesAndPersistsTheResult() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = (0..<5).map { url("AlreadyBoxed\($0)") }
        let destination = directory.appendingPathComponent("native-layout.json")
        let layout = try NativeLayout(apps: apps, fileURL: destination)
        let box = NativeGroup(id: "existing-box-id", title: "Tools", pages: [NativePage(items: Array(apps.prefix(2)))])
        layout.pages.setArray([NativePage(items: [box]), NativePage(items: Array(apps.dropFirst(2)))])
        let plan = [AutoArrangeGroup(title: "Tools", apps: Array(apps.prefix(2)))]

        #expect(AutoArrange.arrange(layout, groups: plan))

        #expect((layout.pages as! [NativePage]).map { $0.items.count } == [4])
        let root = try #require(layout.pages.firstObject as? NativePage)
        #expect((root.items.firstObject as? NativeGroup)?.id == "existing-box-id")
        #expect(flatten(layout) == apps)
        #expect(!AutoArrange.arrange(layout, groups: plan))
        try layout.save()
        let reloaded = try NativeLayout(apps: apps, fileURL: destination)
        #expect((reloaded.pages as! [NativePage]).map { $0.items.count } == [4])
        #expect(((reloaded.pages.firstObject as? NativePage)?.items.firstObject as? NativeGroup)?.id == "existing-box-id")
        #expect(flatten(reloaded) == apps && !AutoArrange.arrange(reloaded, groups: plan))
    }

    @Test(arguments: [(35, [35]), (36, [35, 1]), (70, [35, 35]), (71, [35, 35, 1]), (106, [35, 35, 35, 1])])
    func compactingRootPagesRespectsCapacityWithoutChangingFolderPageBoundaries(boundary: (Int, [Int])) throws {
        let (rootCount, expectedSizes) = boundary
        let apps = (0..<(rootCount + 2)).map { url("RootBoundary\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let box = NativeGroup(id: "multi-page-box", title: "Tools", pages: [
            NativePage(items: Array(apps.prefix(2))), NativePage(items: [apps[2]])
        ])
        let rootItems: [Any] = [box] + apps.dropFirst(3).map { $0 as Any }
        let fragmented = stride(from: 0, to: rootItems.count, by: 17).map { start in
            NativePage(items: Array(rootItems[start..<min(start + 17, rootItems.count)]))
        }
        layout.pages.setArray(fragmented)
        let plan = [AutoArrangeGroup(title: "Tools", apps: Array(apps.prefix(3)))]

        #expect(AutoArrange.arrange(layout, groups: plan))

        #expect((layout.pages as! [NativePage]).map { $0.items.count } == expectedSizes)
        let compactedItems = (layout.pages as! [NativePage]).flatMap { Array($0.items) }
        let compactedBox = try #require(compactedItems.first as? NativeGroup)
        #expect(compactedBox.id == "multi-page-box")
        #expect(compactedItems.dropFirst().compactMap { $0 as? URL } == Array(apps.dropFirst(3)))
        #expect((compactedBox.items as! [NativePage]).map { $0.items as! [URL] } == [Array(apps.prefix(2)), [apps[2]]])
        #expect(flatten(layout) == apps && Set(flatten(layout)).count == apps.count)
        #expect(!AutoArrange.arrange(layout, groups: plan))
    }

    @Test func aPlanWithoutExistingMatchesPreservesManualRootPageBreaks() throws {
        let apps = (0..<6).map { url("ManualPage\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let first = NativePage(items: Array(apps.prefix(1)))
        let second = NativePage(items: Array(apps.dropFirst(1).prefix(2)))
        let third = NativePage(items: Array(apps.dropFirst(3)))
        layout.pages.setArray([first, second, third])
        for plan in [[], [AutoArrangeGroup(title: "No Match", apps: [url("NotInstalled")])]] {
            #expect(!AutoArrange.arrange(layout, groups: plan))
            #expect((layout.pages as! [NativePage]).map { $0.items.count } == [1, 2, 3])
            let sameFirst = (layout.pages[0] as AnyObject) === (first as AnyObject)
            let sameSecond = (layout.pages[1] as AnyObject) === (second as AnyObject)
            let sameThird = (layout.pages[2] as AnyObject) === (third as AnyObject)
            #expect(sameFirst && sameSecond && sameThird && flatten(layout) == apps)
        }
    }

    @Test(arguments: [1, 35, 36, 75])
    func foldersHaveBoundedPagesWithoutDroppingOrDuplicatingApps(count: Int) throws {
        let apps = (0..<count).map { url("App\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        #expect(AutoArrange.arrange(layout, settings: AutoArrangeSettings(preset: .categories, rules: []), groups: [AutoArrangeGroup(title: "Tools", apps: apps)]))
        let root = try #require(layout.pages.firstObject as? NativePage)
        let group = try #require(root.items.firstObject as? NativeGroup)
        #expect(layout.pages.count == 1 && root.items.count == 1)
        #expect(group.items.count == (count + 34) / 35)
        #expect((group.items as! [NativePage]).allSatisfy { $0.items.count > 0 && $0.items.count <= 35 })
        #expect(flatten(layout) == apps)
        #expect(!AutoArrange.arrange(layout, groups: [AutoArrangeGroup(title: "Tools", apps: apps)]))
    }

    @Test func newGroupsRespectRootCapacityAndOnlyExistingAppsCanMove() throws {
        let apps = (0..<36).map { url("App\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let plan = apps.enumerated().map { AutoArrangeGroup(title: "Group\($0.offset)", apps: [$0.element]) }
        #expect(AutoArrange.arrange(layout, groups: plan + [AutoArrangeGroup(title: "Missing", apps: [url("Missing")])]))
        #expect((layout.pages as! [NativePage]).map { $0.items.count } == [35, 1])
        #expect(Set(flatten(layout)) == Set(apps) && flatten(layout).count == apps.count)
        #expect(!AutoArrange.arrange(layout, groups: []))
    }

    @Test func movingFromADuplicateNamedFolderKeepsItsUnmatchedMembers() throws {
        let apps = (0..<4).map { url("App\($0)") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let first = NativeGroup(id: "first", title: "Tools", pages: [NativePage(items: [apps[0]])])
        let second = NativeGroup(id: "second", title: "Tools", pages: [NativePage(items: [apps[1], apps[2]])])
        layout.pages.setArray([NativePage(items: [first, second, apps[3]])])
        #expect(AutoArrange.arrange(layout, groups: [AutoArrangeGroup(title: "Tools", apps: [apps[1], apps[3]])]))
        #expect((first.items[0] as? NativePage)?.items as? [URL] == [apps[0], apps[1], apps[3]])
        #expect((second.items[0] as? NativePage)?.items as? [URL] == [apps[2]])
        #expect(flatten(layout).count == 4)
    }

    @Test func savingAnArrangementKeepsExistingRecordFieldsAndFolderIDs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = (0..<3).map { directory.appendingPathComponent("App\($0).app") }
        let file = directory.appendingPathComponent("native-layout.json")
        let recordsToSave: [[String: Any]] = [
            ["id": "preserved-app-id", "kind": "app", "appID": apps[0].path, "title": "自定义名称"],
            ["id": "preserved-folder-id", "kind": "folder", "title": "Tools", "appIDs": [apps[1].path], "pageSizes": [1]],
            ["id": "moved-app-id", "kind": "app", "appID": apps[2].path]
        ]
        let documentToSave: [String: Any] = ["pages": [recordsToSave]]
        try JSONSerialization.data(withJSONObject: documentToSave).write(to: file)
        let layout = try NativeLayout(apps: apps, fileURL: file)
        #expect(AutoArrange.arrange(layout, groups: [AutoArrangeGroup(title: "Tools", apps: [apps[2]])]))
        try layout.save()
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: [[[String: Any]]]])
        let records = try #require(document["pages"]?.first)
        #expect(records[0]["id"] as? String == "preserved-app-id" && records[0]["title"] as? String == "自定义名称")
        #expect(records[1]["id"] as? String == "preserved-folder-id")
        #expect(records[1]["appIDs"] as? [String] == [apps[1].path, apps[2].path])
        let reloaded = try NativeLayout(apps: apps, fileURL: file)
        #expect(!AutoArrange.arrange(reloaded, groups: [AutoArrangeGroup(title: "Tools", apps: [apps[2]])]))
        #expect(Set(flatten(reloaded)) == Set(apps))
    }

    private func rule(_ title: String, category: String = "", name: String = "") -> AutoArrangeRule {
        AutoArrangeRule(id: UUID(), title: title, category: category, nameContains: name)
    }
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Applications/\(name).app") }
    private func app(_ name: String, category: String = "other") -> AutoArrangeApp {
        AutoArrangeApp(url: url(name), name: name, category: category)
    }
    private func flatten(_ layout: NativeLayout) -> [URL] {
        (layout.pages as! [NativePage]).flatMap { page in
            page.items.flatMap { item -> [URL] in
                if let group = item as? NativeGroup { return (group.items as! [NativePage]).flatMap { $0.items as! [URL] } }
                return [item as! URL]
            }
        }
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-arrange-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
