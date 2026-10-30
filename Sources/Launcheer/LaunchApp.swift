import AppKit
import Darwin
import Foundation

struct LaunchApp: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let addedDate: Date

    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        return image
    }

    var searchText: String {
        "\(name) \(bundleIdentifier ?? "")".localizedLowercase
    }

    var canMoveToTrash: Bool {
        guard url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else { return false }
        if let bundleIdentifier, bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }
        let path = url.standardizedFileURL.path
        guard !path.hasPrefix("/System/Applications/") else { return false }

        let userApplications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first?
            .standardizedFileURL
            .path
        if let userApplications, path.hasPrefix(userApplications + "/") {
            return true
        }

        if path.hasPrefix("/Applications/") {
            return true
        }

        return false
    }

    var needsFinderForDeletion: Bool {
        let path = url.standardizedFileURL.path
        guard canMoveToTrash else { return false }
        if path.hasPrefix("/Applications/"), !isOwnedByCurrentUser {
            return true
        }
        return !FileManager.default.isDeletableFile(atPath: path)
    }

    private var isOwnedByCurrentUser: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.standardizedFileURL.path),
              let ownerID = attributes[.ownerAccountID] as? NSNumber
        else { return false }
        return ownerID.uint32Value == getuid()
    }
}
