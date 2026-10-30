import AppKit
import ObjectiveC
import Testing
@testable import Launcheer

struct ApplicationScannerTests {
    @Test @MainActor func scanningMetadataDoesNotLoadIcons() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: root.appendingPathComponent("Metadata.app"))
        let method = try #require(class_getInstanceMethod(NSWorkspace.self, #selector(NSWorkspace.icon(forFile:))))
        var requests = 0
        let image = NSImage(size: NSSize(width: 128, height: 128))
        let block: @convention(block) (NSWorkspace, NSString) -> NSImage = { _, _ in
            requests += 1
            return image
        }
        let replacement = imp_implementationWithBlock(block)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        let apps = ApplicationScanner.scan(roots: [root])
        let app = try #require(apps.first)
        #expect(requests == 0)
        #expect(app.icon === image)
        #expect(requests == 1)
    }

    @Test func includesMenuBarAppsButNotBackgroundProcesses() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: root.appendingPathComponent("Menu.app"), info: ["LSUIElement": true])
        try makeApp(at: root.appendingPathComponent("Regular.app"))
        try makeApp(at: root.appendingPathComponent("Daemon.app"), info: ["LSBackgroundOnly": true])

        let apps = ApplicationScanner.scan(roots: [root])
        #expect(Set(apps.map(\.name)) == ["Menu", "Regular"])
    }

    @Test func localizedNamesDoNotReplaceStructuralMetadata() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: root.appendingPathComponent("Agent.app"), info: ["LSUIElement": true], localizedName: "Localized Agent")
        try makeApp(at: root.appendingPathComponent("Web.app"), info: ["CrAppModeShortcutID": "shortcut"], localizedName: "Localized Web")
        try makeApp(at: root.appendingPathComponent("Daemon.app"), info: ["LSBackgroundOnly": true], localizedName: "Localized Daemon")

        let apps = ApplicationScanner.scan(roots: [root])
        #expect(apps.count == 1)
        #expect(apps.first?.name == "Localized Agent")
    }

    @Test func followsAppSymlinksWithoutDuplicatesOrBrokenLinks() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications")
        let target = root.appendingPathComponent("Installed/Real.app")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try makeApp(at: target)
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Linked.app"), withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Broken.app"), withDestinationURL: root.appendingPathComponent("Missing.app"))

        let apps = ApplicationScanner.scan(roots: [applications, target.deletingLastPathComponent()])
        #expect(apps.count == 1)
        #expect(apps.first?.url == target.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test func continuesExcludingChromeShortcutsAndBundledHelpers() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(at: root.appendingPathComponent("Parent.app"))
        try makeApp(at: root.appendingPathComponent("Parent.app/Contents/Helper.app"), info: ["LSUIElement": true])
        try makeApp(at: root.appendingPathComponent("Chrome Apps.localized/Gmail.app"))
        try makeApp(at: root.appendingPathComponent("Web.app"), info: ["CFBundleExecutable": "app_mode_loader"])
        try makeApp(at: root.appendingPathComponent("Uninstaller.app"))
        let apps = ApplicationScanner.scan(roots: [root])
        #expect(apps.map(\.name) == ["Parent"])
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeApp(at url: URL, info extra: [String: Any] = [:], localizedName: String? = nil) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": "com.launcheer.scan-test." + UUID().uuidString,
            "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en"]
        ]
        info.merge(extra) { _, value in value }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let localizedName {
            let localization = contents.appendingPathComponent("Resources/en.lproj")
            try FileManager.default.createDirectory(at: localization, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": localizedName], format: .xml, options: 0)
                .write(to: localization.appendingPathComponent("InfoPlist.strings"))
        }
    }
}
