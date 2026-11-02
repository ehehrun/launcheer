import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeMaterialTests {
    @Test(arguments: [nil, true, false] as [Bool?], [false, true])
    func transparencyAndAccessibilityOnlyChangeTheWallpaper(enabled: Bool?, hasImage: Bool) throws {
        var reduceTransparency = false
        let restore = try interceptMaterialSettings(enabled: { enabled }) { reduceTransparency }
        defer { restore() }
        let host = NativeHost()
        let window = MaterialWindow()
        let cover = MaterialWindow()
        let slice = CALayer()
        slice.opacity = 0.3
        let coverBacking = CGColor(gray: 0.15, alpha: 1)
        cover.contentView.layer.backgroundColor = coverBacking
        cover.contentView.layer.addSublayer(slice)
        let view = MaterialContentView()
        let icon = CALayer()
        icon.frame = CGRect(x: 120, y: 160, width: 128, height: 128)
        view.layer.addSublayer(view.backdrop)
        view.layer.addSublayer(icon)
        window.contentView.layer.addSublayer(view.layer)
        view.backdrop.hasImage = hasImage
        view.backdrop.backgroundColor = CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.2)
        host.setValue(window, forKey: "window")
        host.setValue(cover, forKey: "menuBarCoverWindow")
        host.setValue(view, forKey: "view")
        let iconFrame = icon.frame

        for reduced in [false, true, false] {
            reduceTransparency = reduced
            try updateMaterial(host)

            let translucent = enabled != false && !reduced
            let backdropOpacity: Float = translucent ? 0.75 : 1
            let expectedAlpha: CGFloat = translucent ? 0 : 1
            let expectedBacking = try #require(view.backdrop.backgroundColor?.copy(alpha: expectedAlpha))
            let backing = try #require(window.contentView.layer.backgroundColor)
            let retainedCoverBacking = try #require(cover.contentView.layer.backgroundColor)
            #expect(view.backdrop.opacity == backdropOpacity)
            #expect(slice.opacity == backdropOpacity)
            #expect(host.value(forKey: "menuBarCoverWindow") as? MaterialWindow === cover)
            #expect(cover.contentView.layer.sublayers?.count == 1 && cover.contentView.layer.sublayers?.first === slice)
            #expect(cover.contentView.layer.opacity == 1 && retainedCoverBacking.alpha == 1)
            #expect(CFEqual(retainedCoverBacking, coverBacking))
            #expect(backing.alpha == expectedAlpha && CFEqual(backing, expectedBacking))
            #expect(window.alphaValue == 1 && window.contentView.alphaValue == 1 && view.alphaValue == 1)
            #expect(window.contentView.layer.opacity == 1 && view.layer.opacity == 1 && icon.opacity == 1)
            #expect(icon.frame == iconFrame && icon.superlayer === view.layer)
            #expect(window.backgroundColor.alphaComponent == 0 && !window.opaque)
        }
        #expect(NSApp == nil)
    }

    @Test func togglingTransparencyReusesTheContentWithOrWithoutAWallpaper() throws {
        var enabled = true
        let restore = try interceptMaterialSettings(enabled: { enabled }) { false }
        defer { restore() }
        let host = NativeHost()
        let window = MaterialWindow()
        let root = window.contentView
        let rootLayer = root.layer
        let cover = MaterialWindow()
        let coverLayer = cover.contentView.layer
        let coverBacking = CGColor(gray: 0.15, alpha: 1)
        coverLayer.backgroundColor = coverBacking
        let slice = CALayer()
        slice.opacity = 0.3
        coverLayer.addSublayer(slice)
        let view = MaterialContentView()
        let contentLayer = view.layer
        let icon = CALayer()
        icon.frame = CGRect(x: 120, y: 160, width: 128, height: 128)
        contentLayer.addSublayer(view.backdrop)
        contentLayer.addSublayer(icon)
        rootLayer.addSublayer(contentLayer)
        let iconFrame = icon.frame
        view.backdrop.backgroundColor = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.1)
        host.setValue(window, forKey: "window")
        host.setValue(view, forKey: "view")

        // A wallpaper request can still be pending before the menu-bar cover is created.
        try updateMaterial(host)
        #expect(view.backdrop.opacity == 0.75)
        #expect(rootLayer.backgroundColor?.alpha == 0)
        host.setValue(cover, forKey: "menuBarCoverWindow")

        let pixels = Data([0, 0, 0, 0, 96, 32, 16, 128])
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        for setting in [true, false, true] {
            enabled = setting
            for hasImage in [false, true, false] {
                view.backdrop.hasImage = hasImage
                view.backdrop.contents = hasImage ? image : nil
                try updateMaterial(host)

                let expectedOpacity: Float = setting ? 0.75 : 1
                let expectedAlpha: CGFloat = setting ? 0 : 1
                #expect(view.backdrop.opacity == expectedOpacity && slice.opacity == expectedOpacity)
                #expect(rootLayer.backgroundColor?.alpha == expectedAlpha)
                #expect(window.contentView === root && root.layer === rootLayer)
                #expect(host.value(forKey: "window") as? MaterialWindow === window)
                #expect(host.value(forKey: "view") as? MaterialContentView === view)
                #expect(host.value(forKey: "menuBarCoverWindow") as? MaterialWindow === cover)
                #expect(view.layer === contentLayer && icon.superlayer === contentLayer)
                #expect(icon.frame == iconFrame && icon.opacity == 1)
                #expect(window.alphaValue == 1 && root.alphaValue == 1 && view.alphaValue == 1)
                #expect(rootLayer.opacity == 1 && contentLayer.opacity == 1)
                #expect(coverLayer.opacity == 1 && coverLayer.backgroundColor?.alpha == 1)
                #expect(coverLayer.sublayers?.count == 1 && coverLayer.sublayers?.first === slice)
                if hasImage {
                    let retainedImage = try #require(view.backdrop.contents) as! CGImage
                    #expect(retainedImage === image)
                } else {
                    #expect(view.backdrop.contents == nil)
                }
            }
        }
        #expect(NSApp == nil)
    }

    @Test func backgroundSettingsApplyBeforeWaitingForTheWallpaper() {
        let host = MaterialRefreshHost()
        let window = MaterialWindow()
        host.setValue(window, forKey: "window")

        host.refreshBackground()

        #expect(host.steps == ["material", "wallpaper"])
        #expect(host.requestedScreen === window.screen)
        #expect(NSApp == nil)
    }
}

@MainActor
private func updateMaterial(_ host: NativeHost) throws {
    let selector = NSSelectorFromString("updateBackgroundMaterial:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Update = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    unsafeBitCast(method_getImplementation(method), to: Update.self)(host, selector, nil)
}

@MainActor
private func interceptMaterialSettings(enabled: @escaping () -> Bool?, reduced: @escaping () -> Bool) throws -> () -> Void {
    let defaultsSelector = NSSelectorFromString("objectForKey:")
    let defaultsMethod = try #require(class_getInstanceMethod(UserDefaults.self, defaultsSelector))
    let accessibilityMethod = try #require(class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("accessibilityDisplayShouldReduceTransparency")))
    let originalDefaults = method_getImplementation(defaultsMethod)
    typealias ReadObject = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    let read = unsafeBitCast(originalDefaults, to: ReadObject.self)
    let defaultsBlock: @convention(block) (AnyObject, NSString) -> AnyObject? = { receiver, key in
        if key == "background.transparencyEnabled" { return enabled().map { NSNumber(value: $0) } }
        return read(receiver, defaultsSelector, key)?.takeUnretainedValue()
    }
    let defaultsImplementation = imp_implementationWithBlock(defaultsBlock)
    let accessibilityBlock: @convention(block) (AnyObject) -> Bool = { _ in reduced() }
    let accessibilityImplementation = imp_implementationWithBlock(accessibilityBlock)
    let originalAccessibility = method_setImplementation(accessibilityMethod, accessibilityImplementation)
    method_setImplementation(defaultsMethod, defaultsImplementation)
    return {
        method_setImplementation(defaultsMethod, originalDefaults)
        method_setImplementation(accessibilityMethod, originalAccessibility)
        imp_removeBlock(defaultsImplementation)
        imp_removeBlock(accessibilityImplementation)
    }
}

@MainActor
private final class MaterialWindow: NSObject {
    @objc var alphaValue: CGFloat = 1
    @objc var opaque = false
    @objc var backgroundColor = NSColor.clear
    @objc let contentView = MaterialRoot()
    @objc let screen = NSObject()
}

@MainActor
private final class MaterialRoot: NSObject {
    @objc var alphaValue: CGFloat = 1
    @objc let layer = CALayer()
}

@MainActor
private final class MaterialContentView: NSObject {
    @objc var alphaValue: CGFloat = 1
    @objc let layer = CALayer()
    @objc let backdrop = MaterialBackdrop()
}

@MainActor
private final class MaterialBackdrop: CALayer {
    @objc var hasImage = false
}

private final class MaterialRefreshHost: NativeHost {
    private(set) var steps: [String] = []
    private(set) var requestedScreen: NSObject?

    @objc(updateBackgroundMaterial:)
    func updateMaterial(_ notification: NSNotification?) { steps.append("material") }

    @objc(prepareDesktopForScreen:)
    func prepareWallpaper(_ screen: NSObject) {
        steps.append("wallpaper")
        requestedScreen = screen
    }
}
