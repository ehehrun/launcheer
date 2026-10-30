import AppKit
import NativeLaunchpad
import ObjectiveC
import Testing

@Suite(.serialized)
@MainActor
struct NativeMaterialTests {
    @Test(arguments: [false, true])
    func accessibilityChangesOnlyAffectTheBackground(hasImage: Bool) throws {
        let getter = try #require(class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("accessibilityDisplayShouldReduceTransparency")))
        var reduceTransparency = false
        let block: @convention(block) (NSWorkspace) -> Bool = { _ in reduceTransparency }
        let replacement = imp_implementationWithBlock(block)
        let original = method_setImplementation(getter, replacement)
        defer {
            method_setImplementation(getter, original)
            imp_removeBlock(replacement)
        }

        let host = NativeHost()
        let window = MaterialWindow()
        let background = MaterialContentView()
        window.contentView.backdrop.hasImage = hasImage
        host.setValue(window, forKey: "window")
        host.setValue(window.contentView, forKey: "view")
        host.setValue(background, forKey: "backgroundView")
        let selector = NSSelectorFromString("updateBackgroundMaterial:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Update = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let update = unsafeBitCast(method_getImplementation(method), to: Update.self)

        update(host, selector, nil)
        #expect(background.alphaValue == 0.75)
        #expect(background.hidden == hasImage)
        #expect(window.contentView.backdrop.opacity == (hasImage ? 0.75 : 0.08))
        #expect(window.alphaValue == 1)
        #expect(window.contentView.alphaValue == 1)
        #expect(window.contentView.maskImage == nil)

        reduceTransparency = true
        update(host, selector, nil)
        #expect(background.alphaValue == 1)
        #expect(background.hidden == hasImage)
        #expect(window.contentView.backdrop.opacity == (hasImage ? 1 : 0.08))
        #expect(window.alphaValue == 1)
        #expect(window.contentView.alphaValue == 1)
        #expect(window.contentView.maskImage == nil)

        reduceTransparency = false
        update(host, selector, nil)
        #expect(background.alphaValue == 0.75)
        #expect(background.hidden == hasImage)
        #expect(window.contentView.backdrop.opacity == (hasImage ? 0.75 : 0.08))
        #expect(window.alphaValue == 1)
        #expect(window.contentView.alphaValue == 1)
        #expect(window.contentView.maskImage == nil)
    }
}

@MainActor
private final class MaterialWindow: NSObject {
    @objc var alphaValue: CGFloat = 1
    @objc let contentView = MaterialContentView()
}

@MainActor
private final class MaterialContentView: NSObject {
    @objc var alphaValue: CGFloat = 1
    @objc var hidden = false
    @objc var maskImage: NSImage?
    @objc let backdrop = MaterialBackdrop()
}

@MainActor
private final class MaterialBackdrop: NSObject {
    @objc var hasImage = false
    @objc var opacity: Float = 1
}
