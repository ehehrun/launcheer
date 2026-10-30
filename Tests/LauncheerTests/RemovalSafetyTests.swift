import AppKit
import Testing
import NativeLaunchpad
@testable import Launcheer

@Suite(.serialized)
@MainActor
struct RemovalSafetyTests {
    @Test(arguments: ["delete", "trash", "moveThenTrash"])
    func runningBundleRemovalExitsNormally(operation: String) async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appURL = directory.appendingPathComponent("Launcheer.app")
        let contents = appURL.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/RemovalProbe")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        var trashedURL: NSURL?
        let process = Process()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            if let trashedURL { try? fileManager.removeItem(at: trashedURL as URL) }
            try? fileManager.removeItem(at: directory)
        }

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "swiftc", "-swift-version", "6", "-O",
            root.appendingPathComponent("Tests/Fixtures/RemovalProbe.swift").path,
            root.appendingPathComponent("Sources/Launcheer/RunningApplicationMonitor.swift").path,
            root.appendingPathComponent("Sources/Launcheer/LaunchApp.swift").path,
            root.appendingPathComponent("Sources/Launcheer/DebugLog.swift").path,
            "-o", executable.path
        ]
        try compiler.run()
        defer { if compiler.isRunning { compiler.terminate() } }
        while compiler.isRunning {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(compiler.terminationStatus == 0)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.launcheer.removal-test." + UUID().uuidString,
            "CFBundleExecutable": "RemovalProbe",
            "CFBundlePackageType": "APPL",
            "LSBackgroundOnly": true
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let readyURL = directory.appendingPathComponent("ready")
        process.executableURL = executable
        process.arguments = [readyURL.path]
        try process.run()
        for _ in 0..<150 {
            if fileManager.fileExists(atPath: readyURL.path) || !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let probeState = process.isRunning
            ? "still running without readiness signal (pid=\(process.processIdentifier))"
            : "exit=\(process.terminationStatus) reason=\(process.terminationReason)"
        try #require(fileManager.fileExists(atPath: readyURL.path), "Removal probe not ready: \(probeState)")
        try #require(process.isRunning)

        // Editing bundle contents must not be mistaken for removing the bundle.
        try Data("updated".utf8).write(to: contents.appendingPathComponent("test-resource"))
        try await Task.sleep(for: .milliseconds(150))
        #expect(process.isRunning)

        switch operation {
        case "delete":
            try fileManager.removeItem(at: appURL)
        case "trash":
            try fileManager.trashItem(at: appURL, resultingItemURL: &trashedURL)
        case "moveThenTrash":
            let movedURL = directory.appendingPathComponent("Renamed.app")
            try fileManager.moveItem(at: appURL, to: movedURL)
            try await Task.sleep(for: .milliseconds(250))
            #expect(process.isRunning)
            try fileManager.trashItem(at: movedURL, resultingItemURL: &trashedURL)
        default:
            Issue.record("Unknown test operation")
        }

        for _ in 0..<150 {
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!process.isRunning, "Removing the running bundle must terminate the process")
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 0)
    }

    @Test func stoppingMonitorDoesNotReportRemoval() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        var removalCount = 0
        let monitor = try RunningApplicationMonitor(url: url) { removalCount += 1 }
        monitor.stop()
        try FileManager.default.removeItem(at: url)
        try await Task.sleep(for: .milliseconds(200))
        #expect(removalCount == 0)
    }

    @Test func missingBundleCannotStartMonitoring() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        #expect(throws: (any Error).self) {
            try RunningApplicationMonitor(url: url) {}
        }
    }

    @Test func protectedAppDeletionIsRejected() async throws {
        let url = URL(fileURLWithPath: "/System/Applications/" + UUID().uuidString + ".app")
        let app = LaunchApp(
            id: url.path, name: "Protected App", url: url, bundleIdentifier: nil,
            addedDate: .now
        )
        #expect(!app.canMoveToTrash)
        #expect(!NativeHost().canMoveItem(toTrash: url))
    }
}
