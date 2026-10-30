import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeContextMenuTests {
    @Test(arguments: ["app", "folderApp", "folderOutside", "searchApp", "group", "blank", "drag", "capture"])
    func contextMenuUsesOnlyTheHitApplicationsOriginalURL(target: String) throws {
        let type: AnyClass = try #require(NSClassFromString("NativeView"))
        let selector = NSSelectorFromString("menuForEvent:")
        let method = try #require(class_getInstanceMethod(type, selector))
        typealias Menu = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        let menu = unsafeBitCast(method_getImplementation(method), to: Menu.self)
        let input = ContextInput()
        let url = NSURL(fileURLWithPath: "/Applications/Context Menu Fixture.app")
        if target != "blank" {
            let item = ContextItemLayer()
            item.frame = CGRect(x: 10, y: 10, width: 100, height: 100)
            item.item.clientItem = target == "group" ? NSObject() : url
            let image = CALayer()
            image.frame = item.bounds
            item.addSublayer(image)
            input.pager.layer.addSublayer(item)
        }
        if target == "folderApp" || target == "folderOutside" {
            let behind = ContextItemLayer()
            behind.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            behind.item.clientItem = NSURL(fileURLWithPath: "/Applications/Hidden Root Fixture.app")
            input.layer.insertSublayer(behind, at: 0)
        }
        input.springboard.dragging = target == "drag"
        input.downLayer = target == "capture" ? CALayer() : nil

        let point = target == "folderOutside" ? NSPoint(x: 10, y: 10) : NSPoint(x: 80, y: 95)
        let result = menu(input, selector, ContextEvent(point: point))?.takeUnretainedValue()
        let application = ["app", "folderApp", "searchApp"].contains(target)

        #expect(result === (application ? input.host.menu : nil))
        #expect(input.host.url === (application ? url : nil))
        #expect(input.host.finishCount == (application ? 1 : 0))
        #expect(NSApp == nil)
    }

    @Test func everyApplicationMenuContainsOnlyItsOriginalFinderLocation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = directory.appendingPathComponent("Target Fixture.app")
        let link = directory.appendingPathComponent("Link Fixture.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let host = ContextHost()
        let url = NSURL(fileURLWithPath: "/Applications/Context Menu Fixture.app")
        for application in [url, NSURL(fileURLWithPath: "/System/Applications/Calendar.app"), Bundle.main.bundleURL as NSURL, link as NSURL] {
            let menu = try #require(try contextMenu(for: application, host: host))
            #expect(menu.items.count == 1)
            let item = try #require(menu.items.first)
            #expect(item.title == "在 Finder 中显示" && item.action == NSSelectorFromString("revealItemInFinder:"))
            #expect(item.target === host && item.representedObject as AnyObject? === application)
            #expect(host.validateMenuItem(item))
        }
        let dock = try contextDockMenu(for: host)
        #expect(dock.items.allSatisfy { $0.action != NSSelectorFromString("moveItemToTrash:") && $0.action != NSSelectorFromString("resetTrashDeniedItems:") })
        let finder = try #require(try contextMenu(for: url, host: host)?.items.first)
        host.verifying = true
        #expect(try contextMenu(for: url, host: host) == nil)
        #expect(!host.validateMenuItem(finder))
        #expect(NSApp == nil)
    }

    @Test func revealingHidesTheLauncherBeforeRequestingFinder() throws {
        let host = ContextHost()
        let workspace = ContextWorkspace()
        workspace.onReveal = { #expect(host.hideCount == 1) }
        let restoreWorkspace = try interceptContextWorkspace(workspace)
        defer { restoreWorkspace() }
        let url = NSURL(fileURLWithPath: "/Applications/Context Menu Fixture.app")
        let menu = try #require(try contextMenu(for: url, host: host))

        try perform(menu.items[0], on: host)

        #expect(workspace.revealed.count == 1)
        #expect(workspace.revealed.first === url)
        #expect(workspace.recycled.isEmpty && host.reloads.isEmpty)
        #expect(NSApp == nil)
    }

    @Test(arguments: ["cancel", "success", "error", "otherError"])
    func nativeRemovalStillConfirmsAndWaitsForSuccessfulRecycling(result: String) async throws {
        let host = ContextHost()
        let workspace = ContextWorkspace()
        let confirmation = ContextAlert(response: result == "cancel" ? NSApplication.ModalResponse.alertSecondButtonReturn : NSApplication.ModalResponse.alertFirstButtonReturn)
        let errorAlert = ContextAlert(response: NSApplication.ModalResponse.alertFirstButtonReturn)
        let restoreWorkspace = try interceptContextWorkspace(workspace)
        defer { restoreWorkspace() }
        let alertMethod = try #require(class_getInstanceMethod(NSAlert.self, NSSelectorFromString("init")))
        let errorMethod = try #require(class_getClassMethod(NSAlert.self, NSSelectorFromString("alertWithError:")))
        // Intercept NSAlert's own init before it creates AppKit views; preserve init's +1 ownership.
        let alertBlock: @convention(block) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer = { pointer in
            Unmanaged<AnyObject>.fromOpaque(pointer).release()
            return Unmanaged.passRetained(confirmation).toOpaque()
        }
        let errorBlock: @convention(block) (AnyObject, NSError) -> NSObject = { _, error in
            errorAlert.error = error
            return errorAlert
        }
        let implementations = [imp_implementationWithBlock(alertBlock), imp_implementationWithBlock(errorBlock)]
        let methods = [alertMethod, errorMethod]
        let previous = zip(methods, implementations).map { method_setImplementation($0, $1) }
        defer {
            for (method, implementation) in zip(methods, previous) { method_setImplementation(method, implementation) }
            for implementation in implementations { imp_removeBlock(implementation) }
        }
        let url = NSURL(fileURLWithPath: "/Applications/Context Menu Fixture.app")
        let retained = URL(fileURLWithPath: "/Applications/Keep This Fixture.app")
        host.items = [url as URL, retained]
        let selector = NSSelectorFromString("performRemoveActionForItem:withEvent:sender:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Remove = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?) -> Void
        unsafeBitCast(method_getImplementation(method), to: Remove.self)(host, selector, url, nil, nil)

        #expect(confirmation.runCount == 1)
        #expect(confirmation.messageText.contains(url.lastPathComponent!))
        #expect(confirmation.buttons == ["移到废纸篓", "取消"])
        #expect(host.reloads.isEmpty && host.items == [url as URL, retained])
        #expect(host.hideCount == 0)
        if result == "cancel" {
            #expect(workspace.recycled.isEmpty && workspace.completion == nil)
        } else {
            #expect(workspace.recycled.count == 1 && workspace.recycled[0].count == 1)
            #expect(workspace.recycled[0][0] === url)
            let completion = try #require(workspace.completion)
            let error: NSError?
            switch result {
            case "error": error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            case "otherError": error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
            default: error = nil
            }
            completion(NSDictionary(), error)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(host.reloads == (result == "success" ? [[retained]] : []))
            #expect(errorAlert.runCount == (error == nil ? 0 : 1))
            #expect(errorAlert.error === error)
        }
        #expect(NSApp == nil)
    }
}

@MainActor
private func interceptContextWorkspace(_ workspace: ContextWorkspace) throws -> () -> Void {
    let methods = try ["activateFileViewerSelectingURLs:", "recycleURLs:completionHandler:"].map {
        try #require(class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString($0)))
    }
    typealias Completion = @convention(block) (NSDictionary, NSError?) -> Void
    let reveal: @convention(block) (AnyObject, [NSURL]) -> Void = { _, urls in workspace.reveal(urls) }
    let recycle: @convention(block) (AnyObject, [NSURL], @escaping Completion) -> Void = { _, urls, completion in
        workspace.recycle(urls, completion: completion)
    }
    let implementations = [imp_implementationWithBlock(reveal), imp_implementationWithBlock(recycle)]
    let previous = zip(methods, implementations).map { method_setImplementation($0, $1) }
    return {
        for (method, implementation) in zip(methods, previous) { method_setImplementation(method, implementation) }
        for implementation in implementations { imp_removeBlock(implementation) }
    }
}

@MainActor
private func contextDockMenu(for host: NativeHost) throws -> NSMenu {
    let selector = NSSelectorFromString("applicationDockMenu:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Menu = @convention(c) (AnyObject, Selector, AnyObject?) -> Unmanaged<AnyObject>?
    let result = unsafeBitCast(method_getImplementation(method), to: Menu.self)(host, selector, nil)?.takeUnretainedValue()
    return try #require(result as? NSMenu)
}

@MainActor
private func contextMenu(for url: NSURL, host: NativeHost) throws -> NSMenu? {
    let selector = NSSelectorFromString("contextMenuForItem:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Menu = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
    return unsafeBitCast(method_getImplementation(method), to: Menu.self)(host, selector, url)?.takeUnretainedValue() as? NSMenu
}

@MainActor
private func perform(_ item: NSMenuItem, on host: NativeHost) throws {
    let selector = try #require(item.action)
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Action = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    unsafeBitCast(method_getImplementation(method), to: Action.self)(host, selector, item)
}

private final class ContextHost: NativeHost {
    private(set) var hideCount = 0
    private(set) var reloads: [[URL]] = []
    override func hideLauncher() { hideCount += 1 }
    override func reloadItems(_ items: [URL]) { reloads.append(items) }
}

@MainActor
private final class ContextInput: NSObject {
    @objc let host = ContextMenuLookup()
    @objc let springboard = ContextSpringboard()
    @objc var downLayer: CALayer?
    let pager = ContextPager()
    @objc let layer: CALayer = {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        return layer
    }()
    override init() {
        super.init()
        let container = CALayer()
        container.frame = CGRect(x: 30, y: 40, width: 250, height: 250)
        pager.layer.frame = CGRect(x: 20, y: 25, width: 200, height: 200)
        container.addSublayer(pager.layer)
        layer.addSublayer(container)
    }
    @objc func activePager() -> ContextPager { pager }
    @objc(convertPoint:fromView:)
    func convertPoint(_ point: NSPoint, from view: NSObject?) -> NSPoint { point }
}

@MainActor
private final class ContextMenuLookup: NSObject {
    let menu = NSObject()
    private(set) var url: NSURL?
    private(set) var finishCount = 0
    @objc func finishGroupEditing() { finishCount += 1 }
    @objc(contextMenuForItem:)
    func contextMenu(for url: NSURL) -> NSObject { self.url = url; return menu }
}

private final class ContextSpringboard: NSObject {
    @objc var dragging = false
}

private final class ContextItemLayer: CALayer {
    @objc let item = ContextNativeItem()
}

private final class ContextNativeItem: NSObject {
    @objc var clientItem = NSObject()
}

private final class ContextPager: NSObject {
    @objc let layer = CALayer()
}

private final class ContextEvent: NSObject {
    @objc let locationInWindow: NSPoint
    init(point: NSPoint) { locationInWindow = point; super.init() }
}

@MainActor
private final class ContextWorkspace: NSObject {
    var onReveal: (() -> Void)?
    private(set) var revealed: [NSURL] = []
    private(set) var recycled: [[NSURL]] = []
    private(set) var completion: ((NSDictionary, NSError?) -> Void)?
    @objc(activateFileViewerSelectingURLs:)
    func reveal(_ urls: [NSURL]) { onReveal?(); revealed = urls }
    @objc(recycleURLs:completionHandler:)
    func recycle(_ urls: [NSURL], completion: @escaping (NSDictionary, NSError?) -> Void) {
        recycled.append(urls)
        self.completion = completion
    }
}

@MainActor
private final class ContextAlert: NSObject {
    @objc var messageText = ""
    @objc var informativeText = ""
    private(set) var buttons: [String] = []
    private(set) var runCount = 0
    var error: NSError?
    let response: NSApplication.ModalResponse
    init(response: NSApplication.ModalResponse) { self.response = response; super.init() }
    @objc(addButtonWithTitle:)
    func addButton(_ title: String) -> NSObject { buttons.append(title); return NSObject() }
    @objc func runModal() -> Int { runCount += 1; return response.rawValue }
}
