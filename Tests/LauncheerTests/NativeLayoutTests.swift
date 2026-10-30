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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-layout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
