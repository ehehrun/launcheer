import AppKit
import Darwin
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeCompatibilityTests {
    @Test func runtimeInitializerMatchesIndependentInspectionOfTheInstalledDock() throws {
        let application = NSApp
        let image = dlopen("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", RTLD_LAZY | RTLD_LOCAL)
        try #require(image != nil)
        let springboard: AnyClass = try #require(NSClassFromString("Springboard"))
        let implementation = try #require(class_getMethodImplementation(springboard, NSSelectorFromString("init")))
        let entry = unsafeBitCast(implementation, to: UnsafeRawPointer.self)
        var error: NSError?
        let initializer = try #require(NativeDockPreferenceInitializer(entry, &error))
        #expect(error == nil)
        var info = Dl_info()
        try #require(dladdr(entry, &info) != 0)
        let base = try #require(info.dli_fbase)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let inspector = Process()
        inspector.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        inspector.arguments = [root.appendingPathComponent("scripts/inspect_dock.py").path]
        let diagnostics = Pipe()
        inspector.standardOutput = diagnostics
        inspector.standardError = diagnostics
        try inspector.run()
        let message = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        inspector.waitUntilExit()
        try #require(inspector.terminationStatus == 0, "Independent Dock inspection failed: \(message)")
        let prefix = "Preferences initializer offset: 0x"
        let line = try #require(message.split(separator: "\n").first { $0.hasPrefix(prefix) })
        let expected = try #require(UInt(line.dropFirst(prefix.count), radix: 16))

        #expect(UInt(bitPattern: initializer) - UInt(bitPattern: base) == expected)
        #expect(NSApp === application)
    }

    @Test func anUnrelatedNativeMethodIsRejectedWithoutExecutingIt() throws {
        let application = NSApp
        let implementation = try #require(class_getMethodImplementation(NSObject.self, NSSelectorFromString("init")))
        let entry = unsafeBitCast(implementation, to: UnsafeRawPointer.self)
        var error: NSError?

        #expect(NativeDockPreferenceInitializer(entry, &error) == nil)
        #expect(error != nil)
        #expect(NSApp === application)
    }

    @Test func nativePreferencesCanBeInitializedRepeatedlyWithoutCreatingAnApplication() throws {
        let application = NSApp
        for _ in 0..<3 {
            var error: NSError?
            let initialized = NativeInitializeDock(&error)
            try #require(initialized, "Native Dock initialization failed: \(String(describing: error))")
            #expect(error == nil)
        }
        #expect(NSApp === application)
    }
}
