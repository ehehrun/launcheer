import AppKit

@main
@MainActor
enum RemovalProbe {
    private static var monitor: RunningApplicationMonitor?

    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let bundle = Bundle.main
        let ownApp = LaunchApp(
            id: bundle.bundleURL.path, name: "Launcheer", url: bundle.bundleURL,
            bundleIdentifier: bundle.bundleIdentifier, addedDate: .now
        )
        guard !ownApp.canMoveToTrash, !ownApp.needsFinderForDeletion else { exit(10) }

        // The same bundle identity must remain protected after moving the app.
        let installedURL = URL(fileURLWithPath: "/Applications/Launcheer.app")
        let installedSelf = LaunchApp(
            id: installedURL.path, name: "Launcheer", url: installedURL,
            bundleIdentifier: bundle.bundleIdentifier, addedDate: .now
        )
        guard bundle.bundleIdentifier != nil, !installedSelf.canMoveToTrash else { exit(11) }
        let unrelatedApp = LaunchApp(
            id: installedURL.path, name: "Launcheer", url: installedURL,
            bundleIdentifier: "com.launcheer.unrelated-test", addedDate: .now
        )
        guard unrelatedApp.canMoveToTrash else { exit(12) }

        monitor = try RunningApplicationMonitor(url: bundle.bundleURL) {
            application.terminate(nil)
        }
        try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        application.run()
    }
}
