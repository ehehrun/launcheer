import Darwin
import Foundation

@MainActor
final class RunningApplicationMonitor {
    private let descriptor: Int32
    private let onRemoval: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onRemoval: @escaping @MainActor () -> Void) throws {
        self.onRemoval = onRemoval

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        self.descriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.delete, .rename, .revoke], queue: .main
        )
        self.source = source
        source.setEventHandler { @Sendable [weak self] in
            MainActor.assumeIsolated {
                self?.checkRemoval()
            }
        }
        source.setCancelHandler { @Sendable in close(descriptor) }
        source.resume()
    }

    deinit {
        source?.cancel()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func checkRemoval() {
        guard let source else { return }
        if !source.data.intersection([.delete, .revoke]).isEmpty {
            stop()
            onRemoval()
            return
        }

        // Resolve the watched inode, not a URL whose path may predate the move.
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &path) == 0 else {
            DebugLog.write("running application path lookup failed: errno=\(errno)")
            return
        }
        let currentURL = URL(fileURLWithFileSystemRepresentation: path, isDirectory: true, relativeTo: nil)
        do {
            var relationship = FileManager.URLRelationship.other
            try FileManager.default.getRelationship(
                &relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: currentURL
            )
            if relationship == .contains {
                stop()
                onRemoval()
            }
        } catch {
            DebugLog.write("running application location check failed: \(error.localizedDescription)")
        }
    }
}
