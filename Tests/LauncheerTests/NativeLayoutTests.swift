import Foundation
import NativeLaunchpad
import Testing

struct NativeLayoutTests {
    @Test(arguments: [false, true])
    func firstLaunchIgnoresTheLegacyFile(malformed: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = ["A", "B", "C"].map { directory.appendingPathComponent($0 + ".app") }
        let legacy = directory.appendingPathComponent("layout.json")
        let destination = directory.appendingPathComponent("native-layout.json")
        let oldData = malformed ? Data("not JSON".utf8) : try JSONSerialization.data(withJSONObject: [
            ["id": "old-folder", "kind": "folder", "title": "旧布局", "appIDs": [apps[2].path, apps[0].path]]
        ])
        try oldData.write(to: legacy)

        let layout = try NativeLayout(apps: apps, fileURL: destination)
        #expect(layout.pages.count == 1)
        let page = try #require(layout.pages.firstObject as? NativePage)
        #expect(page.items as? [URL] == apps)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try layout.save()
        #expect(try Data(contentsOf: legacy) == oldData)
    }

    @Test func currentLayoutPreservesItsOriginalFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = ["A", "B", "C"].map { directory.appendingPathComponent($0 + ".app") }
        let destination = directory.appendingPathComponent("native-layout.json")
        let data = try JSONSerialization.data(withJSONObject: ["pages": [[
            ["id": "folder-original", "kind": "folder", "title": "开发工具", "appIDs": [apps[0].path, apps[1].path], "pageSizes": [2]],
            ["id": "app-original", "kind": "app", "appID": apps[2].path]
        ]]])
        try data.write(to: destination)
        let layout = try NativeLayout(apps: apps, fileURL: destination)
        let page = try #require(layout.pages.firstObject as? NativePage)
        let folder = try #require(page.items.firstObject as? NativeGroup)
        #expect(folder.id == "folder-original")
        #expect(folder.title == "开发工具")
        try layout.save()
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [String: Any])
        let pages = try #require(document["pages"] as? [[[String: Any]]])
        #expect(pages[0][0]["id"] as? String == "folder-original")
        #expect(pages[0][0]["kind"] as? String == "folder")
        #expect(pages[0][0]["title"] as? String == "开发工具")
        #expect(pages[0][0]["appIDs"] as? [String] == Array(apps.prefix(2)).map(\.path))
        #expect(pages[0][0]["pageSizes"] as? [Int] == [2])
        #expect(pages[0][1]["id"] as? String == "app-original")
        #expect(pages[0][1]["kind"] as? String == "app")
        #expect(pages[0][1]["appID"] as? String == apps[2].path)
    }

    @Test func savingAndReloadingKeepsRootAndFolderPageBoundaries() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = ["A", "B", "C", "D", "E"].map { directory.appendingPathComponent($0 + ".app") }
        let destination = directory.appendingPathComponent("native-layout.json")
        let layout = try NativeLayout(apps: apps, fileURL: destination)
        let folder = NativeGroup(id: "folder", title: "Tools", pages: [
            NativePage(items: [apps[0]]), NativePage(items: [apps[1], apps[2]])
        ])
        layout.pages.removeAllObjects()
        layout.pages.add(NativePage(items: [folder, apps[3]]))
        layout.pages.add(NativePage(items: [apps[4]]))
        try layout.save()
        let loaded = try NativeLayout(apps: Array(apps.reversed()), fileURL: destination)
        #expect(loaded.pages.count == 2)
        let first = try #require(loaded.pages[0] as? NativePage)
        let restored = try #require(first.items[0] as? NativeGroup)
        #expect(restored.id == folder.id)
        #expect(restored.title == folder.title)
        #expect(restored.items.count == 2)
        #expect((restored.items[0] as? NativePage)?.items.count == 1)
        #expect((restored.items[1] as? NativePage)?.items.count == 2)
        #expect(first.items[1] as? URL == apps[3])
        #expect((loaded.pages[1] as? NativePage)?.items[0] as? URL == apps[4])
    }

    @Test func appChangesRemoveEmptyPagesAndAppendWithoutReordering() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = ["A", "B", "C", "D"].map { directory.appendingPathComponent($0 + ".app") }
        let destination = directory.appendingPathComponent("native-layout.json")
        let layout = try NativeLayout(apps: Array(apps.prefix(3)), fileURL: destination)
        layout.pages.removeAllObjects()
        layout.pages.add(NativePage(items: [apps[0]]))
        layout.pages.add(NativePage(items: [apps[1], apps[2]]))
        try layout.save()
        let loaded = try NativeLayout(apps: [apps[3], apps[2], apps[1]], fileURL: destination)
        #expect(loaded.pages.count == 1)
        let page = try #require(loaded.pages[0] as? NativePage)
        #expect(page.items as? [URL] == [apps[1], apps[2], apps[3]])
    }

    @Test(arguments: [
        "{",
        #"{"pages":[[{"id":"one","kind":"app","appID":"/Applications/A.app"},{"id":"two","kind":"app","appID":"/Applications/A.app"}]]}"#,
        #"{"pages":[[{"id":"folder","kind":"folder","appIDs":["/Applications/A.app"],"pageSizes":[2]}]]}"#
    ])
    func invalidLayoutIsReportedAndNeverOverwritten(json: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("native-layout.json")
        let original = Data(json.utf8)
        try original.write(to: destination)
        #expect(throws: (any Error).self) {
            try NativeLayout(apps: [URL(fileURLWithPath: "/Applications/A.app")], fileURL: destination)
        }
        #expect(try Data(contentsOf: destination) == original)
    }

    @Test func writeFailureIsReported() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("Store")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let layout = try NativeLayout(apps: [], fileURL: parent.appendingPathComponent("native-layout.json"))
        try FileManager.default.removeItem(at: parent)
        try Data("not a directory".utf8).write(to: parent)
        #expect(throws: (any Error).self) { try layout.save() }
        #expect(try String(contentsOf: parent, encoding: .utf8) == "not a directory")
    }

    @Test func flatteningReplacesOnlyTheChosenGroupAtItsOriginalPosition() throws {
        let apps = (0..<6).map { URL(fileURLWithPath: "/Applications/Flatten\($0).app") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let group = NativeGroup(id: "chosen", title: "Tools", pages: [NativePage(items: [apps[1]]), NativePage(items: [apps[2], apps[3]])])
        let other = NativeGroup(id: "untouched", title: "Other", pages: [NativePage(items: [apps[5]])])
        layout.pages.setArray([NativePage(items: [apps[0], group, apps[4], other])])

        #expect(layout.flatten(group))

        let root = try #require(layout.pages.firstObject as? NativePage)
        #expect(layout.pages.count == 1 && root.items.count == 6)
        #expect(root.items.compactMap { $0 as? URL } == Array(apps.prefix(5)))
        let sameOther = (root.items.lastObject as AnyObject) === (other as AnyObject)
        #expect(sameOther && (other.items[0] as? NativePage)?.items as? [URL] == [apps[5]])
        #expect(!layout.flatten(group))
    }

    @Test func flatteningOverflowsIntoLaterPagesWithoutCompactingEarlierPages() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = (0..<80).map { directory.appendingPathComponent("Overflow\($0).app") }
        let destination = directory.appendingPathComponent("native-layout.json")
        let layout = try NativeLayout(apps: apps, fileURL: destination)
        let first = NativePage(items: Array(apps[0..<5]))
        let group = NativeGroup(id: "large-group", title: "Large", pages: [
            NativePage(items: Array(apps[15..<35])), NativePage(items: Array(apps[35..<55]))
        ])
        var secondItems: [Any] = Array(apps[5..<15])
        secondItems.append(group)
        secondItems.append(contentsOf: apps[55..<60].map { $0 as Any })
        layout.pages.setArray([first, NativePage(items: secondItems), NativePage(items: Array(apps[60..<80]))])
        try layout.save()
        let original = try Data(contentsOf: destination)
        let candidate = try #require(layout.copy() as? NativeLayout)

        #expect(candidate.flatten(group))

        let pages = candidate.pages as! [NativePage]
        #expect(pages.map { $0.items.count } == [5, 35, 35, 5])
        #expect(pages.flatMap { $0.items as! [URL] } == apps)
        #expect(Set(pages.flatMap { $0.items as! [URL] }).count == 80)
        #expect((pages[0].items as? [URL]) == Array(apps[0..<5]))
        #expect((pages[1].items as? [URL]) == Array(apps[5..<40]))
        #expect((pages[2].items as? [URL]) == Array(apps[40..<75]))
        #expect((pages[3].items as? [URL]) == Array(apps[75..<80]))
        #expect(layout.pages.count == 3 && group.items.count == 2)
        let originalFirst = (layout.pages.firstObject as AnyObject) === (first as AnyObject)
        #expect(originalFirst)
        #expect(try Data(contentsOf: destination) == original)
        try candidate.save()
        let reloaded = try NativeLayout(apps: apps, fileURL: destination)
        #expect((reloaded.pages as! [NativePage]).map { $0.items.count } == [5, 35, 35, 5])
        #expect((reloaded.pages as! [NativePage]).flatMap { $0.items as! [URL] } == apps)
    }

    @Test func flatteningAMissingGroupDoesNotChangeManualPageBoundaries() throws {
        let apps = (0..<4).map { URL(fileURLWithPath: "/Applications/MissingGroup\($0).app") }
        let layout = try NativeLayout(apps: apps, fileURL: nil)
        let first = NativePage(items: [apps[0]])
        let second = NativePage(items: Array(apps.dropFirst()))
        layout.pages.setArray([first, second])
        let missing = NativeGroup(id: "missing", title: "Missing", pages: [NativePage(items: [apps[0]])])

        #expect(!layout.flatten(missing))

        #expect((layout.pages as! [NativePage]).map { $0.items.count } == [1, 3])
        let sameFirst = (layout.pages.firstObject as AnyObject) === (first as AnyObject)
        let sameSecond = (layout.pages.lastObject as AnyObject) === (second as AnyObject)
        #expect(sameFirst && sameSecond)
    }

    @Test func namedCopiesKeepTheOriginalRecordsAndPageBoundaries() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = (0..<4).map { directory.appendingPathComponent("Named\($0).app") }
        let source = directory.appendingPathComponent("native-layout.json")
        let pages: [[[String: Any]]] = [
            [["id": "original-app-id", "kind": "app", "appID": apps[0].path, "title": "自定义应用名"],
             ["id": "original-folder-id", "kind": "folder", "title": "自定义分组名", "appIDs": [apps[1].path, apps[2].path], "pageSizes": [1, 1]]],
            [["id": "last-app-id", "kind": "app", "appID": apps[3].path]]
        ]
        let document: [String: Any] = ["title": "源方案", "pages": pages]
        let original = try JSONSerialization.data(withJSONObject: document)
        try original.write(to: source)
        let layout = try NativeLayout(apps: apps, fileURL: source)
        let target = directory.appendingPathComponent("native-layout-saved-\(UUID().uuidString).json")

        let snapshot = layout.copy(to: target)
        #expect(snapshot.title == "源方案" && snapshot.destination == target)
        snapshot.title = "新方案"
        try snapshot.save()

        #expect(layout.title == "源方案" && layout.destination == source)
        #expect(try Data(contentsOf: source) == original)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any])
        let records = try #require(saved["pages"] as? [[[String: Any]]])
        #expect(saved["title"] as? String == "新方案" && records.map(\.count) == [2, 1])
        #expect(records[0][0]["id"] as? String == "original-app-id" && records[0][0]["title"] as? String == "自定义应用名")
        #expect(records[0][1]["id"] as? String == "original-folder-id" && records[0][1]["title"] as? String == "自定义分组名")
        #expect(records[0][1]["pageSizes"] as? [Int] == [1, 1])
        let reloaded = try NativeLayout(apps: apps, fileURL: target)
        #expect(reloaded.title == "新方案" && reloaded.pages.count == 2)
    }

    @Test(arguments: [#"{"pages":[[]]}"#, #"{"pages":[[]],"title":0}"#, #"{"pages":[[]],"title":"   "}"#])
    func aSavedPresetRequiresItsOwnNonemptyTitleWithoutRepairingTheFile(json: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("native-layout-saved-\(UUID().uuidString).json")
        let data = Data(json.utf8)
        try data.write(to: target)
        #expect(throws: (any Error).self) { try NativeLayout(apps: [], fileURL: target) }
        #expect(try Data(contentsOf: target) == data)
    }

    @Test func aMissingSavedPresetIsNeverTreatedAsANewLayout() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("native-layout-saved-\(UUID().uuidString).json")
        #expect(throws: (any Error).self) { try NativeLayout(apps: [], fileURL: target) }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-layout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
