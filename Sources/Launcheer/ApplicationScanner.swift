import AppKit
import Foundation

enum ApplicationScanner {
    static func scan(roots: [URL] = applicationRoots()) -> [LaunchApp] {
        var appsByKey: [String: LaunchApp] = [:]
        var seenPaths = Set<String>()

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isAliasFileKey,
                    .creationDateKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }

                defer {
                    enumerator.skipDescendants()
                }

                guard !shouldSkipApp(at: url) else { continue }
                let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
                guard resolvedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                      seenPaths.insert(resolvedURL.path).inserted,
                      !shouldSkipApp(at: resolvedURL) else { continue }

                if let app = makeApp(from: resolvedURL) {
                    let key = app.bundleIdentifier ?? app.url.standardizedFileURL.path
                    appsByKey[key] = app
                }
            }
        }

        return appsByKey.values.sorted(by: sortByAddedDate)
    }

    static func applicationRoots() -> [URL] {
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]

        var uniqueRoots: [URL] = []
        var seenPaths = Set<String>()
        for root in roots {
            let path = root.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                uniqueRoots.append(root)
            }
        }

        if let userApplications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            let path = userApplications.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                uniqueRoots.append(userApplications)
            }
        }

        return uniqueRoots
    }

    private static func makeApp(from url: URL) -> LaunchApp? {
        guard let bundle = Bundle(url: url), let info = bundle.infoDictionary else { return nil }
        guard !shouldSkipBundle(info: info, url: url) else { return nil }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = [displayName, bundleName, fileName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fileName

        return LaunchApp(
            id: url.standardizedFileURL.path,
            name: name,
            url: url,
            bundleIdentifier: bundle.bundleIdentifier,
            addedDate: addedDate(for: url)
        )
    }

    private static func addedDate(for url: URL) -> Date {
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return .distantFuture
        }
        return values.creationDate ?? values.contentModificationDate ?? .distantFuture
    }

    private static func sortByAddedDate(_ lhs: LaunchApp, _ rhs: LaunchApp) -> Bool {
        if lhs.addedDate != rhs.addedDate {
            return lhs.addedDate < rhs.addedDate
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func shouldSkipApp(at url: URL) -> Bool {
        if let resourceValues = try? url.resourceValues(forKeys: [.isAliasFileKey]) {
            if resourceValues.isAliasFile == true {
                return true
            }
        }

        let standardizedPath = url.standardizedFileURL.path
        if standardizedPath.contains("/Contents/") {
            return true
        }

        if standardizedPath.contains("/Chrome Apps.localized/") {
            return true
        }

        return false
    }

    private static func shouldSkipBundle(info: [String: Any], url: URL) -> Bool {
        if info["CrAppModeShortcutID"] != nil
            || info["CrAppModeShortcutURL"] != nil
            || info["CrAppModeUserDataDir"] != nil
            || info["CrBundleIdentifier"] != nil
            || (info["CFBundleExecutable"] as? String) == "app_mode_loader" {
            return true
        }

        if (info["LSBackgroundOnly"] as? Bool) == true {
            return true
        }

        let names = [
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String,
            url.deletingPathExtension().lastPathComponent
        ]
        let normalizedName = names
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
            .first { !$0.isEmpty } ?? ""

        if normalizedName.contains("uninstall") || normalizedName.contains("uninstaller") || normalizedName.contains("卸载") {
            return true
        }

        return false
    }
}
