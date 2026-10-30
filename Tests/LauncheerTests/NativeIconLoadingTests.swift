import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeIconLoadingTests {
    @Test(arguments: [(104.0, 2.0, UInt(256)), (200.0, 2.0, 400), (400.0, 2.0, 512)])
    func iconPixelBudgetFollowsTheActiveGridAndCapsMemory(size: (Double, Double, UInt)) throws {
        let host = NativeHost()
        let view = IconSizingView()
        view.pager.currentPage.item.items[0].itemLayer.imageLayer.bounds = CGRect(x: 0, y: 0, width: size.0, height: size.0)
        host.setValue(view, forKey: "view")
        let selector = NSSelectorFromString("iconPixelSizeForScale:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Size = @convention(c) (AnyObject, Selector, CGFloat) -> UInt
        let pixels = unsafeBitCast(method_getImplementation(method), to: Size.self)(host, selector, size.1)
        #expect(pixels == size.2 && NSApp == nil)
    }

    @Test func aSlowIconDoesNotBlockTheMainQueueOrOtherApplications() async throws {
        let urls = iconURLs(["Slow", "Ready", "Next"])
        let slow = IconReply(image: try iconImage(16), blocked: true)
        let ready = IconReply(image: try iconImage(32), blocked: true)
        let next = IconReply(image: try iconImage(48))
        let lookup = try IconLookup([urls[0]: [slow], urls[1]: [ready], urls[2]: [next]])
        let (host, board) = iconHost(urls)
        defer { finishIconWork(host, lookup) }
        let placeholder = try suppliedIcon(host, urls[0])
        #expect(placeholder === (try suppliedIcon(host, urls[1], key: "miniIcon")))
        #expect(placeholder.width == 256 && placeholder.height == 256)
        let searchPages = NSArray(object: NSObject())
        let group = NSObject()
        host.setValue(searchPages, forKey: "searchPages")
        host.setValue(group, forKey: "dockHiddenGroup")

        try prepareIcons(host, urls)
        #expect(await iconSignal(slow.entered))
        #expect(await iconSignal(ready.entered))
        #expect(lookup.maximumActive == 2)
        #expect(await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: Thread.isMainThread) }
        })
        ready.release.signal()
        #expect(await iconSignal(board.completed(urls[1])))
        #expect(try iconCenter(try suppliedIcon(host, urls[1])) == [32, 80, 160, 255])
        #expect(try suppliedIcon(host, urls[0]) === placeholder)
        #expect(board.updates.filter { $0.url == urls[0] }.isEmpty)

        slow.release.signal()
        await drainIconWork(host)
        for url in urls { #expect(board.updates.filter { $0.url == url }.map(\.key) == ["icon", "miniIcon"]) }
        #expect(board.updates.allSatisfy(\.onMain) && lookup.readsOnMain == 0 && lookup.maximumActive == 2)
        #expect(board.invalidateCount == 0 && board.currentPageIndex == 2)
        #expect((host.value(forKey: "searchPages") as? NSArray) === searchPages)
        #expect(host.value(forKey: "dockHiddenGroup") as AnyObject? === group)
        #expect(NSApp == nil)
    }

    @Test func anOlderGenerationCannotOverwriteTheSameApplicationsNewIcon() async throws {
        let url = iconURLs(["Replaced"])[0]
        let old = IconReply(image: try iconImage(16), blocked: true)
        let latest = IconReply(image: try iconImage(64))
        let lookup = try IconLookup([url: [old, latest]])
        let (host, board) = iconHost([url])
        defer { finishIconWork(host, lookup) }
        try prepareIcons(host, [url])
        #expect(await iconSignal(old.entered))
        try prepareIcons(host, [url])
        #expect(await iconSignal(board.completed(url)))
        let delivered = try suppliedIcon(host, url)
        #expect(try iconCenter(delivered) == [64, 80, 160, 255])
        old.release.signal()
        await drainIconWork(host)
        #expect(try suppliedIcon(host, url) === delivered)
        #expect(board.updates.count == 2 && board.updates.allSatisfy { $0.image === delivered })
        #expect(NSApp == nil)
    }

    @Test func cancelledWorkCannotReplaceThePlaceholder() async throws {
        let url = iconURLs(["Cancelled"])[0]
        let pending = IconReply(image: try iconImage(16), blocked: true)
        let lookup = try IconLookup([url: [pending]])
        let (host, board) = iconHost([url])
        defer { finishIconWork(host, lookup) }
        let placeholder = try suppliedIcon(host, url)
        try prepareIcons(host, [url])
        #expect(await iconSignal(pending.entered))
        cancelIcons(host)
        pending.release.signal()
        await drainIconWork(host)
        #expect(try suppliedIcon(host, url) === placeholder)
        #expect(board.updates.isEmpty && NSApp == nil)
    }

    @Test func anUndecodableIconKeepsItsPlaceholderWhileOtherIconsComplete() async throws {
        let urls = iconURLs(["Invalid", "Valid"])
        let valid = IconReply(image: try iconImage(32))
        let lookup = try IconLookup([urls[0]: [IconReply(image: nil)], urls[1]: [valid]])
        let (host, board) = iconHost(urls)
        defer { finishIconWork(host, lookup) }
        let placeholder = try suppliedIcon(host, urls[0])
        try prepareIcons(host, urls)
        await drainIconWork(host)
        #expect(try suppliedIcon(host, urls[0]) === placeholder)
        #expect(try iconCenter(try suppliedIcon(host, urls[1])) == [32, 80, 160, 255])
        #expect(board.updates.count == 2 && board.updates.allSatisfy { $0.url == urls[1] })
        #expect(lookup.calls(for: urls[0]) == 1 && NSApp == nil)
    }
}

@MainActor
private func iconHost(_ urls: [URL]) -> (NativeHost, IconBoard) {
    let host = NativeHost()
    host.items = urls
    let board = IconBoard()
    host.setValue(board, forKey: "springboard")
    return (host, board)
}

@MainActor
private func prepareIcons(_ host: NativeHost, _ urls: [URL]) throws {
    let selector = NSSelectorFromString("prepareIconsForItems:pixelSize:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Prepare = @convention(c) (AnyObject, Selector, NSArray, UInt) -> Void
    unsafeBitCast(method_getImplementation(method), to: Prepare.self)(host, selector, urls as NSArray, 256)
}

@MainActor
private func suppliedIcon(_ host: NativeHost, _ url: URL, key: String = "icon") throws -> CGImage {
    let selector = NSSelectorFromString("valueForKey:ofItem:withInfo:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Value = @convention(c) (AnyObject, Selector, NSString, NSURL, NSDictionary) -> Unmanaged<AnyObject>?
    let value = unsafeBitCast(method_getImplementation(method), to: Value.self)(host, selector, key as NSString, url as NSURL, [:])
    return try #require(value?.takeUnretainedValue()) as! CGImage
}

@MainActor
private func cancelIcons(_ host: NativeHost) {
    let selector = NSSelectorFromString("cancelIconLoading")
    typealias Cancel = @convention(c) (AnyObject, Selector) -> Void
    unsafeBitCast(class_getMethodImplementation(NativeHost.self, selector), to: Cancel.self)(host, selector)
}

@MainActor
private func finishIconWork(_ host: NativeHost, _ lookup: IconLookup) {
    cancelIcons(host)
    lookup.releaseAll()
    (host.value(forKey: "iconQueue") as? OperationQueue)?.waitUntilAllOperationsAreFinished()
    lookup.restore()
}

@MainActor
private func drainIconWork(_ host: NativeHost) async {
    let queue = host.value(forKey: "iconQueue") as! OperationQueue
    await Task.detached { waitForIcons(queue) }.value
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
}

private func waitForIcons(_ queue: OperationQueue) { queue.waitUntilAllOperationsAreFinished() }
private func iconSignalled(_ signal: DispatchSemaphore, timeout: DispatchTime = .now()) -> Bool { signal.wait(timeout: timeout) == .success }
private func iconSignal(_ signal: DispatchSemaphore) async -> Bool { await Task.detached { iconSignalled(signal, timeout: .now() + 3) }.value }
private func iconURLs(_ names: [String]) -> [URL] {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-icons-" + UUID().uuidString)
    return names.map { root.appendingPathComponent($0 + ".app") }
}
private func iconImage(_ width: Int) throws -> CGImage {
    let pixels = Data((0..<(width * width)).flatMap { _ in [UInt8(width), 80, 160, 255] })
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let color = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    return try #require(CGImage(width: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: color,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}
private func iconCenter(_ image: CGImage) throws -> [UInt8] {
    try #require(image.width == 256 && image.height == 256 && image.bitsPerComponent == 8 && image.bitsPerPixel == 32)
    let data = try #require(image.dataProvider?.data) as Data
    let offset = image.bytesPerRow * (image.height / 2) + (image.width / 2) * 4
    return Array(data[offset..<(offset + 4)])
}

@MainActor
private final class IconBoard: NSObject {
    private(set) var updates: [(url: URL, key: String, image: CGImage, onMain: Bool)] = []
    private var signals: [URL: DispatchSemaphore] = [:]
    @objc var currentPageIndex = 2
    private(set) var invalidateCount = 0
    func completed(_ url: URL) -> DispatchSemaphore {
        if let signal = signals[url] { return signal }
        let signal = DispatchSemaphore(value: 0)
        signals[url] = signal
        return signal
    }
    @objc(setValue:forKey:ofItem:)
    func set(_ value: AnyObject, forKey key: String, ofItem item: URL) {
        updates.append((item, key, value as! CGImage, Thread.isMainThread))
        if key == "miniIcon" { completed(item).signal() }
    }
    @objc func invalidate() { invalidateCount += 1 }
}

private final class IconReply {
    let image: CGImage?
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let blocked: Bool
    init(image: CGImage?, blocked: Bool = false) { self.image = image; self.blocked = blocked }
}

private final class IconLookup {
    private let replies: [URL: [IconReply]]
    private let lock = NSLock()
    private var reads: [URL: Int] = [:]
    private var active = 0
    private var maximum = 0
    private var onMain = 0
    private let method: Method
    private let original: IMP
    private var replacement: IMP!
    private var restored = false
    var maximumActive: Int { lock.withLock { maximum } }
    var readsOnMain: Int { lock.withLock { onMain } }
    init(_ replies: [URL: [IconReply]]) throws {
        self.replies = replies
        let selector = #selector(NSWorkspace.icon(forFile:))
        method = try #require(class_getInstanceMethod(NSWorkspace.self, selector))
        original = method_getImplementation(method)
        typealias Read = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>
        let read = unsafeBitCast(original, to: Read.self)
        let block: @convention(block) (AnyObject, NSString) -> NSObject = { [self] receiver, path in
            let url = URL(fileURLWithPath: path as String)
            guard let options = replies[url] else { return read(receiver, selector, path).takeUnretainedValue() as! NSObject }
            let index = lock.withLock {
                let index = reads[url, default: 0]
                reads[url] = index + 1
                active += 1
                maximum = max(maximum, active)
                if Thread.isMainThread { onMain += 1 }
                return index
            }
            defer { lock.withLock { active -= 1 } }
            guard index < options.count else { Issue.record("Unexpected repeated icon lookup: \(path)"); return IconImage(nil) }
            let reply = options[index]
            reply.entered.signal()
            if reply.blocked { reply.release.wait() }
            return IconImage(reply.image)
        }
        replacement = imp_implementationWithBlock(block)
        method_setImplementation(method, replacement)
    }
    func calls(for url: URL) -> Int { lock.withLock { reads[url, default: 0] } }
    func releaseAll() { for reply in replies.values.flatMap({ $0 }) { reply.release.signal() } }
    func restore() {
        guard !restored else { return }
        restored = true
        method_setImplementation(method, original)
        imp_removeBlock(replacement)
    }
    deinit { restore() }
}

private final class IconImage: NSObject, NSCopying {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image; super.init() }
    func copy(with zone: NSZone? = nil) -> Any { self }
    @objc(CGImageForProposedRect:context:hints:)
    func cgImage(_ rect: UnsafeMutablePointer<NSRect>?, context: NSObject?, hints: NSDictionary?) -> CGImage? {
        rect?.pointee = NSRect(x: 7, y: 9, width: 32, height: 32)
        return image
    }
}

private final class IconSizingView: NSObject {
    let pager = IconSizingPager()
    @objc func activePager() -> IconSizingPager { pager }
}
private final class IconSizingPager: NSObject {
    @objc let currentPage = IconSizingPage()
}
private final class IconSizingPage: NSObject {
    @objc let item = IconSizingContainer()
}
private final class IconSizingContainer: NSObject {
    @objc let items = [IconSizingItem()]
}
private final class IconSizingItem: NSObject {
    @objc let itemLayer = IconSizingLayer()
}
private final class IconSizingLayer: NSObject {
    @objc let imageLayer = CALayer()
}
