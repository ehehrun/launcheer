import AppKit
import Testing
@testable import Launcheer

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LAUNCHEER_UI_TESTS"] == "1"))
@MainActor
struct LauncherLifecycleTests {
    @Test func nativeWindowSurvivesRepeatedAndInterruptedTransitions() async throws {
        let application = NSApplication.shared
        let previousDelegate = application.delegate
        let delegate = AppDelegate()
        delegate.verifying = true
        delegate.automatedVerification = false
        delegate.showOnlyOnMainScreen = true
        delegate.items = [URL(fileURLWithPath: "/System/Applications/Notes.app")]
        application.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let window = delegate.window
        let contentView = try #require(window.contentView)
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            application.delegate = previousDelegate
            window.close()
        }

        try await Task.sleep(for: .milliseconds(350))
        for _ in 0..<3 {
            delegate.hideLauncher()
            #expect(!delegate.wantsLauncherVisible)
            try await Task.sleep(for: .milliseconds(300))
            #expect(!window.isVisible)
            #expect(delegate.window === window)
            #expect(window.contentView === contentView)

            delegate.showLauncher()
            try await Task.sleep(for: .milliseconds(350))
            #expect(window.isVisible)
            #expect(window.alphaValue == 1)
            #expect(!window.ignoresMouseEvents)
            #expect(delegate.window === window)
            #expect(window.contentView === contentView)
        }

        // Reopening immediately must preserve the reused window's visible state.
        delegate.hideLauncher()
        #expect(!delegate.wantsLauncherVisible)
        delegate.showLauncher()
        try await Task.sleep(for: .milliseconds(400))
        #expect(window.isVisible)
        #expect(window.alphaValue == 1)
        #expect(!window.ignoresMouseEvents)
        #expect(window.contentView === contentView)

        delegate.toggleLauncher()
        delegate.toggleLauncher()
        try await Task.sleep(for: .milliseconds(400))
        #expect(window.isVisible)
        #expect(!window.ignoresMouseEvents)

        delegate.hideLauncher()
        try await Task.sleep(for: .milliseconds(250))
        delegate.showLauncher()
        delegate.hideLauncher()
        try await Task.sleep(for: .milliseconds(400))
        #expect(!window.isVisible)
        #expect(window.contentView === contentView)
    }

    @Test func resigningActiveHidesAndKeepsTheNativeWindowReusable() async throws {
        let application = NSApplication.shared
        let previousDelegate = application.delegate
        let delegate = AppDelegate()
        delegate.verifying = true
        delegate.automatedVerification = false
        delegate.showOnlyOnMainScreen = true
        delegate.items = [URL(fileURLWithPath: "/System/Applications/Notes.app")]
        application.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let window = delegate.window
        let contentView = try #require(window.contentView)
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            application.delegate = previousDelegate
            window.close()
        }

        try await Task.sleep(for: .milliseconds(350))
        delegate.perform(
            NSSelectorFromString("applicationDidResignActive:"),
            with: Notification(name: NSApplication.didResignActiveNotification)
        )
        try await Task.sleep(for: .milliseconds(250))
        #expect(!window.isVisible)

        delegate.showLauncher()
        try await Task.sleep(for: .milliseconds(350))
        #expect(window.isVisible)
        #expect(delegate.window === window)
        #expect(window.contentView === contentView)
        #expect(!window.ignoresMouseEvents)
    }
}
