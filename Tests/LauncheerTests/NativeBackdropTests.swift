import AppKit
import ImageIO
import ObjectiveC
import QuartzCore
import Testing
import UniformTypeIdentifiers

@Suite(.serialized)
@MainActor
struct NativeBackdropTests {
    @Test func aCustomImageDoesNotReadTheSystemWallpaperAndRestoresItWhenCleared() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let systemURL = directory.appendingPathComponent("system.png")
        let customURL = directory.appendingPathComponent("custom.png")
        try writeImage(to: systemURL, type: .png)
        try writeImage(to: customURL, type: .png, width: 96)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: systemURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: systemURL.path) }
        let backdrop = try makeBackdrop(in: directory)
        backdrop.bounds = BackdropTestScreen().frame
        try withDesktopURL(systemURL, customImagePath: customURL.path) {
            try update(backdrop)
            let image = try contents(of: backdrop)
            #expect(image.width == 96)
            backdrop.layoutIfNeeded()
            let frame = try #require(backdrop.sublayers?.first?.frame)
            #expect(frame.width == 2946 && frame.height == 982)
            #expect(frame.minX < 0 && frame.minY == 0)
            try update(backdrop)
            #expect(try contents(of: backdrop) === image)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: systemURL.path)
        try withDesktopURL(systemURL) {
            try update(backdrop)
            #expect(try contents(of: backdrop).width == 64)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("cache").path))
        #expect(NSApp == nil)
    }

    @Test(arguments: [false, true])
    func aMissingOrCorruptCustomImageDoesNotUseTheSystemOrAuthorizedCache(missing: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let systemURL = directory.appendingPathComponent("system.png")
        let customURL = directory.appendingPathComponent("custom.png")
        try writeImage(to: systemURL, type: .png)
        try writeImage(to: customURL, type: .png, width: 96)
        let attributes = try FileManager.default.attributesOfItem(atPath: customURL.path)
        let date = try #require(attributes[.modificationDate] as? Date)
        let backdrop = try makeBackdrop(in: directory)
        var cacheError: NSError?
        try #require(cacheImage(backdrop, at: customURL, error: &cacheError))
        try withDesktopURL(systemURL) { try update(backdrop) }
        let original = try contents(of: backdrop)
        if missing {
            try FileManager.default.removeItem(at: customURL)
        } else {
            try Data("not an image".utf8).write(to: customURL)
            try (customURL as NSURL).setResourceValue(date, forKey: .contentModificationDateKey)
        }
        try withDesktopURL(systemURL, customImagePath: customURL.path) {
            var error: NSError?
            #expect(try !callUpdate(backdrop, error: &error))
            #expect(error?.domain == NSCocoaErrorDomain)
            #expect(error?.code == (missing ? CocoaError.Code.fileReadNoSuchFile.rawValue : CocoaError.Code.fileReadCorruptFile.rawValue))
            #expect(try contents(of: backdrop) === original)
            try useBackgroundColor(backdrop)
            #expect(backdrop.value(forKey: "hasImage") as? Bool == false)
        }
    }

    @Test(arguments: ["jpeg", "png", "heic"])
    func stillImagesDecodeAndReuseContents(format: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper." + format)
        try writeImage(to: imageURL, type: try #require(UTType(filenameExtension: format)))
        try withDesktopURL(imageURL) {
            let backdrop = try makeBackdrop(in: directory)
            try update(backdrop)
            let image = try contents(of: backdrop)
            #expect(image.width == 64 && image.height == 32)
            try update(backdrop)
            #expect(try contents(of: backdrop) === image)
        }
    }

    @Test func desktopDescriptionDecodesItsDeclaredImageAndReusesContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("thumbnail.heic")
        let desktopURL = directory.appendingPathComponent("wallpaper.madesktop")
        try writeImage(to: imageURL, type: .heic)
        try PropertyListSerialization.data(fromPropertyList: ["thumbnailPath": imageURL.path], format: .xml, options: 0).write(to: desktopURL)
        if let source = CGImageSourceCreateWithURL(desktopURL as CFURL, nil) {
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary
            #expect(CGImageSourceCreateThumbnailAtIndex(source, 0, options) == nil)
        }
        try withDesktopURL(desktopURL) {
            let backdrop = try makeBackdrop(in: directory)
            try update(backdrop)
            let image = try contents(of: backdrop)
            #expect(image.width == 64 && image.height == 32)
            try update(backdrop)
            #expect(try contents(of: backdrop) === image)
        }
    }

    @Test(arguments: ["invalidDescription", "missingPath", "missingImage", "corruptImage"])
    func invalidDesktopResourcesReportFailure(fixture: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("thumbnail.jpeg")
        let desktopURL = directory.appendingPathComponent("wallpaper.madesktop")
        if fixture == "invalidDescription" {
            try Data("not a property list".utf8).write(to: desktopURL)
        } else {
            let document = fixture == "missingPath" ? [:] : ["thumbnailPath": imageURL.path]
            try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0).write(to: desktopURL)
            if fixture == "corruptImage" { try Data("not an image".utf8).write(to: imageURL) }
        }
        try withDesktopURL(desktopURL) {
            let backdrop = try makeBackdrop(in: directory)
            var error: NSError?
            let success = try callUpdate(backdrop, error: &error)
            #expect(!success)
            #expect(error != nil)
            #expect(error?.localizedDescription.contains("Live wallpaper playback is unsupported") == false)
            try useBackgroundColor(backdrop)
            #expect(backdrop.sublayers?.first?.contents == nil)
            #expect(backdrop.backgroundColor != nil)
        }
    }

    @Test func deniedImageUsesColorAndCanRecoverThePreviousImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.jpeg")
        let deniedURL = directory.appendingPathComponent("denied.jpeg")
        try writeImage(to: imageURL, type: .jpeg)
        try FileManager.default.copyItem(at: imageURL, to: deniedURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: deniedURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: deniedURL.path) }
        let backdrop = try makeBackdrop(in: directory)
        try withDesktopURL(imageURL) {
            try update(backdrop)
            let image = try contents(of: backdrop)
            try withDesktopURL(deniedURL) {
                var error: NSError?
                let success = try callUpdate(backdrop, error: &error)
                #expect(!success)
                #expect(error?.domain == NSCocoaErrorDomain)
                #expect(error?.code == CocoaError.Code.fileReadNoPermission.rawValue)
                try useBackgroundColor(backdrop)
                #expect(backdrop.sublayers?.first?.contents == nil)
                #expect(backdrop.backgroundColor != nil)
            }
            try update(backdrop)
            let restored = try contents(of: backdrop)
            #expect(restored.width == 64 && restored.height == 32)
            #expect(restored !== image)
        }
    }

    @Test func authorizedImageCacheSurvivesUnreadableSourceAndNewBackdrop() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.jpeg")
        try writeImage(to: imageURL, type: .jpeg)
        // This subsecond value exposed a lossy FileManager mtime round-trip.
        let sourceTimestamp = Date(timeIntervalSinceReferenceDate: 814_851_236.10542917)
        try (imageURL as NSURL).setResourceValue(sourceTimestamp, forKey: .contentModificationDateKey)
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        let sourceDate = try #require(sourceAttributes[.modificationDate] as? Date)
        try #require(sourceDate == sourceTimestamp)
        let backdrop = try makeBackdrop(in: directory)
        var error: NSError?
        #expect(try cacheImage(backdrop, at: imageURL, error: &error))
        #expect(error == nil)
        let cached = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("cache"), includingPropertiesForKeys: nil)
        #expect(cached.count == 1)
        let cachedImage = try #require(cached.first)
        #expect(try Data(contentsOf: cachedImage) == Data(contentsOf: imageURL))
        let cachedAttributes = try FileManager.default.attributesOfItem(atPath: cachedImage.path)
        let cachedDate = try #require(cachedAttributes[.modificationDate] as? Date)
        #expect(cachedDate == sourceDate)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: imageURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: imageURL.path) }
        let relaunched = try makeBackdrop(in: directory)
        try withDesktopURL(imageURL) {
            try update(relaunched)
            let image = try contents(of: relaunched)
            #expect(image.width == 64 && image.height == 32)
        }
    }

    @Test func reauthorizingTheSameURLImmediatelyReloadsTheSavedImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.png")
        try writeImage(to: imageURL, type: .png)
        let attributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        let date = try #require(attributes[.modificationDate] as? Date)
        let backdrop = try makeBackdrop(in: directory)
        try withDesktopURL(imageURL) {
            try update(backdrop)
            #expect(try contents(of: backdrop).width == 64)
            try writeImage(to: imageURL, type: .png, width: 96)
            try (imageURL as NSURL).setResourceValue(date, forKey: .contentModificationDateKey)
            var error: NSError?
            try #require(cacheImage(backdrop, at: imageURL, error: &error))
            #expect(error == nil)
            try update(backdrop)
            #expect(try contents(of: backdrop).width == 96)
            #expect(backdrop.value(forKey: "hasImage") as? Bool == true)
            try useBackgroundColor(backdrop)
            #expect(backdrop.value(forKey: "hasImage") as? Bool == false)
        }
    }

    @Test(arguments: [false, true])
    func changedOrMissingSourceDoesNotUseAuthorizedCache(missing: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.jpeg")
        try writeImage(to: imageURL, type: .jpeg)
        let backdrop = try makeBackdrop(in: directory)
        var error: NSError?
        #expect(try cacheImage(backdrop, at: imageURL, error: &error))
        #expect(error == nil)

        if missing {
            try FileManager.default.removeItem(at: imageURL)
        } else {
            let values = try imageURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = try #require(values.contentModificationDate).addingTimeInterval(10)
            try FileManager.default.setAttributes([.modificationDate: modified, .posixPermissions: 0o000], ofItemAtPath: imageURL.path)
        }
        defer {
            if !missing { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: imageURL.path) }
        }
        let relaunched = try makeBackdrop(in: directory)
        try withDesktopURL(imageURL) {
            var readError: NSError?
            let success = try callUpdate(relaunched, error: &readError)
            #expect(!success)
            #expect(readError != nil)
            if !missing { #expect(readError?.code == CocoaError.Code.fileReadNoPermission.rawValue) }
            #expect(relaunched.sublayers?.first?.contents == nil)
        }
    }

    @Test func corruptImageIsNotImportedIntoTheAuthorizedCache() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("corrupt.jpeg")
        try Data("not an image".utf8).write(to: imageURL)
        let backdrop = try makeBackdrop(in: directory)
        var error: NSError?
        let success = try cacheImage(backdrop, at: imageURL, error: &error)
        #expect(!success)
        #expect(error != nil)
        let cacheDirectory = directory.appendingPathComponent("cache")
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            #expect(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).isEmpty)
        }
    }

    @Test func aCorruptMatchingCacheDoesNotSilentlyReadTheSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.jpeg")
        try writeImage(to: imageURL, type: .jpeg)
        let backdrop = try makeBackdrop(in: directory)
        var error: NSError?
        #expect(try cacheImage(backdrop, at: imageURL, error: &error))
        let cached = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("cache"), includingPropertiesForKeys: nil)
        let cachedImage = try #require(cached.first)
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        let sourceDate = try #require(sourceAttributes[.modificationDate] as? Date)
        let attributes = try FileManager.default.attributesOfItem(atPath: cachedImage.path)
        let date = try #require(attributes[.modificationDate] as? Date)
        try #require(date == sourceDate)
        try Data("not an image".utf8).write(to: cachedImage)
        try (cachedImage as NSURL).setResourceValue(sourceDate, forKey: .contentModificationDateKey)
        let corruptedAttributes = try FileManager.default.attributesOfItem(atPath: cachedImage.path)
        let corruptedDate = try #require(corruptedAttributes[.modificationDate] as? Date)
        let times = String(format: "source=%.17g initialCache=%.17g corruptCache=%.17g", sourceDate.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate, corruptedDate.timeIntervalSinceReferenceDate)
        try #require(corruptedDate == sourceDate, Comment(rawValue: times))

        let relaunched = try makeBackdrop(in: directory)
        try withDesktopURL(imageURL) {
            var readError: NSError?
            let success = try callUpdate(relaunched, error: &readError)
            #expect(!success)
            #expect(readError?.code == CocoaError.Code.fileReadCorruptFile.rawValue)
            #expect(relaunched.sublayers?.first?.contents == nil)
        }
    }

    @Test func anImageChangedDuringImportIsNotCached() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.jpeg")
        try writeImage(to: imageURL, type: .jpeg)
        let attributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        let changedDate = try #require(attributes[.modificationDate] as? Date).addingTimeInterval(10)
        let selector = NSSelectorFromString("dataWithContentsOfURL:options:error:")
        let method = try #require(class_getClassMethod(NSData.self, selector))
        let original = method_getImplementation(method)
        typealias ReadData = @convention(c) (AnyObject, Selector, NSURL, UInt, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSData?
        let readData = unsafeBitCast(original, to: ReadData.self)
        var changed = false
        var mutationError: Error?
        let block: @convention(block) (AnyObject, NSURL, UInt, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSData? = { receiver, url, options, error in
            let data = readData(receiver, selector, url, options, error)
            if url as URL == imageURL && !changed {
                do {
                    try FileManager.default.setAttributes([.modificationDate: changedDate], ofItemAtPath: imageURL.path)
                    changed = true
                } catch { mutationError = error }
            }
            return data
        }
        let replacement = imp_implementationWithBlock(block)
        method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        let backdrop = try makeBackdrop(in: directory)
        var error: NSError?
        let success = try cacheImage(backdrop, at: imageURL, error: &error)
        #expect(changed && mutationError == nil)
        #expect(!success)
        #expect(error != nil)
        let cacheDirectory = directory.appendingPathComponent("cache")
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            #expect(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).isEmpty)
        }
    }

    @Test func aDelayedImageReadLeavesTheMainQueueFreeAndReusesTheResult() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wallpaper.png")
        let desktopURL = directory.appendingPathComponent("wallpaper.madesktop")
        try writeImage(to: imageURL, type: .png)
        try PropertyListSerialization.data(fromPropertyList: ["thumbnailPath": imageURL.path], format: .xml, options: 0).write(to: desktopURL)
        let backdrop = try makeBackdrop(in: directory)
        let delayedRead = try DelayedBackdropRead(url: imageURL)
        defer { delayedRead.release.signal() }
        let started = ContinuousClock.now
        let request = try beginUpdate(backdrop, desktopURL: desktopURL)
        #expect(started.duration(to: .now) < .seconds(1))
        let entered = delayedRead.entered
        let reading = await Task.detached { backdropReadSignalled(entered, timeout: .now() + 2) }.value
        #expect(reading)
        let mainQueueFree = await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: Thread.isMainThread) }
        }
        #expect(mainQueueFree)
        #expect(!backdropReadSignalled(delayedRead.readOnMain))
        #expect(backdrop.value(forKey: "hasImage") as? Bool == false)
        delayedRead.release.signal()
        let result = try await completed(request)
        #expect(result.success && result.error == nil && result.onMain)
        let image = try contents(of: backdrop)
        let reused = try await completed(beginUpdate(backdrop, desktopURL: desktopURL))
        #expect(reused.success && reused.error == nil && reused.onMain)
        #expect(try contents(of: backdrop) === image)
        #expect(!backdropReadSignalled(delayedRead.entered))
    }

    @Test(arguments: [false, true], [false, true])
    func aSupersededOrCancelledReadCannotReplaceTheCurrentImage(cancel: Bool, custom: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let currentURL = directory.appendingPathComponent("current.png")
        let slowURL = directory.appendingPathComponent("slow.png")
        let nextURL = directory.appendingPathComponent("next.png")
        try writeImage(to: currentURL, type: .png)
        try writeImage(to: slowURL, type: .png, width: 96)
        try writeImage(to: nextURL, type: .png, width: 128)
        let backdrop = try makeBackdrop(in: directory)
        try withDesktopURL(currentURL) { try update(backdrop) }
        let original = try contents(of: backdrop)
        let delayedRead = try DelayedBackdropRead(url: slowURL)
        defer { delayedRead.release.signal() }
        let pending = try beginUpdate(backdrop, desktopURL: slowURL, customImagePath: custom ? slowURL.path : nil)
        let entered = delayedRead.entered
        #expect(await Task.detached { backdropReadSignalled(entered, timeout: .now() + 2) }.value)
        var replacement: AsyncStream<BackdropUpdateResult>?
        if cancel { backdrop.perform(NSSelectorFromString("cancelPendingUpdate")) }
        else { replacement = try beginUpdate(backdrop, desktopURL: nextURL) }
        delayedRead.release.signal()
        let cancelled = try await completed(pending)
        #expect(!cancelled.success && cancelled.onMain)
        #expect(cancelled.error?.domain == NSCocoaErrorDomain)
        #expect(cancelled.error?.code == CocoaError.Code.userCancelled.rawValue)
        if let replacement {
            let latest = try await completed(replacement)
            #expect(latest.success && latest.error == nil && latest.onMain)
            #expect(try contents(of: backdrop).width == 128)
        } else {
            #expect(try contents(of: backdrop) === original)
        }
    }

    private func beginUpdate(_ backdrop: CALayer, desktopURL: URL, customImagePath: String? = nil) throws -> AsyncStream<BackdropUpdateResult> {
        let selector = NSSelectorFromString("updateForScreen:completion:")
        let method = try #require(class_getInstanceMethod(type(of: backdrop), selector))
        typealias Completion = @convention(block) (Bool, NSError?) -> Void
        typealias Update = @convention(c) (AnyObject, Selector, NSScreen, Completion) -> Void
        let update = unsafeBitCast(method_getImplementation(method), to: Update.self)
        let (stream, continuation) = AsyncStream<BackdropUpdateResult>.makeStream()
        let completion: Completion = { success, error in
            continuation.yield((success, error, Thread.isMainThread))
            continuation.finish()
        }
        try withDesktopURL(desktopURL, customImagePath: customImagePath) { update(backdrop, selector, BackdropTestScreen(), completion) }
        return stream
    }

    private func completed(_ stream: AsyncStream<BackdropUpdateResult>) async throws -> BackdropUpdateResult {
        var iterator = stream.makeAsyncIterator()
        return try #require(await iterator.next())
    }

    private func makeBackdrop(in directory: URL) throws -> CALayer {
        let type = try #require(NSClassFromString("NativeBackdrop") as? CALayer.Type)
        let backdrop = type.init()
        backdrop.setValue(directory.appendingPathComponent("cache"), forKey: "imageCacheDirectory")
        return backdrop
    }

    private func cacheImage(_ backdrop: CALayer, at url: URL, error: inout NSError?) throws -> Bool {
        let selector = NSSelectorFromString("cacheAuthorizedImageAtURL:error:")
        let method = try #require(class_getInstanceMethod(type(of: backdrop), selector))
        typealias CacheImage = @convention(c) (AnyObject, Selector, NSURL, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        let implementation = unsafeBitCast(method_getImplementation(method), to: CacheImage.self)
        return implementation(backdrop, selector, url as NSURL, &error)
    }

    private func update(_ backdrop: CALayer) throws {
        var error: NSError?
        let success = try callUpdate(backdrop, error: &error)
        #expect(success, "\(String(describing: error))")
        #expect(error == nil)
    }

    private func callUpdate(_ backdrop: CALayer, error: inout NSError?) throws -> Bool {
        let selector = NSSelectorFromString("updateForScreen:error:")
        let method = try #require(class_getInstanceMethod(type(of: backdrop), selector))
        typealias Update = @convention(c) (AnyObject, Selector, NSScreen, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        let implementation = unsafeBitCast(method_getImplementation(method), to: Update.self)
        return implementation(backdrop, selector, BackdropTestScreen(), &error)
    }

    private func useBackgroundColor(_ backdrop: CALayer) throws {
        let selector = NSSelectorFromString("useBackgroundColorForScreen:")
        let method = try #require(class_getInstanceMethod(type(of: backdrop), selector))
        typealias UseColor = @convention(c) (AnyObject, Selector, NSScreen) -> Void
        let implementation = unsafeBitCast(method_getImplementation(method), to: UseColor.self)
        implementation(backdrop, selector, BackdropTestScreen())
    }

    private func contents(of backdrop: CALayer) throws -> CGImage {
        let contents = try #require(backdrop.sublayers?.first?.contents)
        return contents as! CGImage
    }

    private func withDesktopURL(_ url: URL, customImagePath: String? = nil, operation: () throws -> Void) throws {
        let pathSelector = NSSelectorFromString("stringForKey:")
        let pathMethod = try #require(class_getInstanceMethod(UserDefaults.self, pathSelector))
        let originalPath = method_getImplementation(pathMethod)
        typealias ReadPath = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
        let readPath = unsafeBitCast(originalPath, to: ReadPath.self)
        let pathBlock: @convention(block) (AnyObject, NSString) -> AnyObject? = { receiver, key in
            if key == "background.customImagePath" { return customImagePath as NSString? }
            return readPath(receiver, pathSelector, key)?.takeUnretainedValue()
        }
        let urlMethod = try #require(class_getInstanceMethod(NSWorkspace.self, #selector(NSWorkspace.desktopImageURL(for:))))
        let optionsMethod = try #require(class_getInstanceMethod(NSWorkspace.self, #selector(NSWorkspace.desktopImageOptions(for:))))
        let urlBlock: @convention(block) (NSWorkspace, NSScreen) -> NSURL = { _, _ in
            #expect(customImagePath == nil)
            return url as NSURL
        }
        let options: NSDictionary = [
            NSWorkspace.DesktopImageOptionKey.fillColor: NSColor.black,
            NSWorkspace.DesktopImageOptionKey.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            NSWorkspace.DesktopImageOptionKey.allowClipping: true
        ]
        let optionsBlock: @convention(block) (NSWorkspace, NSScreen) -> NSDictionary = { _, _ in
            #expect(customImagePath == nil)
            return options
        }
        let pathImplementation = imp_implementationWithBlock(pathBlock)
        let urlImplementation = imp_implementationWithBlock(urlBlock)
        let optionsImplementation = imp_implementationWithBlock(optionsBlock)
        method_setImplementation(pathMethod, pathImplementation)
        let originalURL = method_setImplementation(urlMethod, urlImplementation)
        let originalOptions = method_setImplementation(optionsMethod, optionsImplementation)
        defer {
            method_setImplementation(pathMethod, originalPath)
            method_setImplementation(urlMethod, originalURL)
            method_setImplementation(optionsMethod, originalOptions)
            imp_removeBlock(pathImplementation)
            imp_removeBlock(urlImplementation)
            imp_removeBlock(optionsImplementation)
        }
        try operation()
    }

    private func writeImage(to url: URL, type: UTType, width: Int = 64) throws {
        let provider = try #require(CGDataProvider(data: Data(repeating: 255, count: width * 32 * 4) as CFData))
        let image = try #require(CGImage(width: width, height: 32, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-backdrop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private typealias BackdropUpdateResult = (success: Bool, error: NSError?, onMain: Bool)

private func backdropReadSignalled(_ semaphore: DispatchSemaphore, timeout: DispatchTime = .now()) -> Bool {
    semaphore.wait(timeout: timeout) == .success
}

private final class DelayedBackdropRead {
    let entered: DispatchSemaphore
    let release: DispatchSemaphore
    let readOnMain: DispatchSemaphore
    private let method: Method
    private let original: IMP
    private let replacement: IMP

    init(url: URL) throws {
        let selector = NSSelectorFromString("dataWithContentsOfURL:options:error:")
        let method = try #require(class_getClassMethod(NSData.self, selector))
        let original = method_getImplementation(method)
        typealias Read = @convention(c) (AnyObject, Selector, NSURL, UInt, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSData?
        let read = unsafeBitCast(original, to: Read.self)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let readOnMain = DispatchSemaphore(value: 0)
        let block: @convention(block) (AnyObject, NSURL, UInt, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSData? = { receiver, target, options, error in
            if target as URL == url {
                if Thread.isMainThread { readOnMain.signal() }
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
            }
            return read(receiver, selector, target, options, error)
        }
        self.method = method
        self.original = original
        self.entered = entered
        self.release = release
        self.readOnMain = readOnMain
        replacement = imp_implementationWithBlock(block)
        method_setImplementation(method, replacement)
    }

    deinit {
        method_setImplementation(method, original)
        imp_removeBlock(replacement)
    }
}

private final class BackdropTestScreen: NSScreen {
    override var frame: NSRect { NSRect(x: 0, y: 0, width: 1512, height: 982) }
    override var backingScaleFactor: CGFloat { 2 }
}
