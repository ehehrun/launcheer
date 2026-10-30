import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeMenuBarCoverTests {
    @Test(arguments: [24.0, 38.0])
    func coverSharesThePreparedImageAndClipsOnlyTheTopEdge(height: Double) throws {
        let (source, sourceImage, image) = try makeBackdrop(size: CGSize(width: 1512, height: 982))
        let cover = CALayer()
        cover.bounds = CGRect(x: 0, y: 0, width: 1512, height: height)

        try updateCover(cover, from: source)

        let slice = try #require(cover.sublayers?.first)
        let copied = try #require(slice.sublayers?.first)
        let color = try #require(slice.backgroundColor)
        #expect(cover.masksToBounds)
        #expect(cover.sublayers?.count == 1)
        #expect(cover.opacity == 1)
        #expect(slice.opacity == 1)
        #expect(copied.opacity == 1)
        #expect(color.alpha == 1)
        #expect(slice.frame == CGRect(x: 0, y: -36, width: 1512, height: height + 36))
        #expect(slice.bounds.height < source.bounds.height)
        #expect(slice.shouldRasterize)
        #expect(slice.rasterizationScale == 2)
        #expect(copied.contentsScale == 2)
        #expect(try contents(of: copied) === image)
        #expect(try contents(of: sourceImage) === image)
        #expect(copied.frame == sourceImage.frame.offsetBy(dx: 0, dy: -(982 - height - 36)))
        let originalFilters = try #require(source.filters as? [NSObject])
        let filters = try #require(slice.filters as? [NSObject])
        try #require(filters.count == 3 && originalFilters.count == 3)
        for (index, key) in [(0, "inputRadius"), (0, "inputHardEdges"), (1, "inputAmount"), (2, "inputColorMatrix")] {
            let original = try #require(originalFilters[index].value(forKey: key) as? NSObject)
            let copied = try #require(filters[index].value(forKey: key) as? NSObject)
            #expect(copied.isEqual(original))
        }
    }

    @Test func aShortSourceDoesNotCreateAnOversizedRaster() throws {
        let (source, sourceImage, image) = try makeBackdrop(size: CGSize(width: 120, height: 48))
        let cover = CALayer()
        cover.bounds = CGRect(x: 0, y: 0, width: 120, height: 24)

        try updateCover(cover, from: source)

        let slice = try #require(cover.sublayers?.first)
        let copied = try #require(slice.sublayers?.first)
        #expect(slice.frame == CGRect(x: 0, y: -24, width: 120, height: 48))
        #expect(copied.frame == sourceImage.frame)
        #expect(try contents(of: copied) === image)
    }

    @Test func aColorBackgroundReplacesThePreviousImage() throws {
        let (source, sourceImage, _) = try makeBackdrop(size: CGSize(width: 1512, height: 982))
        let cover = CALayer()
        cover.bounds = CGRect(x: 0, y: 0, width: 1512, height: 38)
        try updateCover(cover, from: source)
        #expect(cover.sublayers?.first?.sublayers?.first?.contents != nil)

        let color = CGColor(red: 0.15, green: 0.3, blue: 0.5, alpha: 1)
        sourceImage.contents = nil
        source.backgroundColor = color
        try updateCover(cover, from: source)

        let slice = try #require(cover.sublayers?.first)
        let copied = try #require(slice.sublayers?.first)
        let copiedColor = try #require(slice.backgroundColor)
        #expect(cover.sublayers?.count == 1)
        #expect(cover.opacity == 1)
        #expect(slice.opacity == 1)
        #expect(copied.opacity == 1)
        #expect(copiedColor.alpha == 1)
        #expect(copied.contents == nil)
        #expect(CFEqual(copiedColor, color))
        #expect(slice.rasterizationScale == 2)
    }

    private func makeBackdrop(size: CGSize) throws -> (CALayer, CALayer, CGImage) {
        let type = try #require(NSClassFromString("NativeBackdrop") as? CALayer.Type)
        let source = type.init()
        source.bounds = CGRect(origin: .zero, size: size)
        source.rasterizationScale = 2
        // The main tint is translucent; the top cover must still hide system icons.
        source.opacity = 0.08
        source.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        source.setValue(NSValue(size: NSSize(width: 1600, height: 900)), forKey: "imageSize")
        source.setValue(NSImageScaling.scaleProportionallyUpOrDown.rawValue, forKey: "imageScaling")
        source.setValue(true, forKey: "allowClipping")
        let imageLayer = try #require(source.value(forKey: "imageLayer") as? CALayer)
        let provider = try #require(CGDataProvider(data: Data(repeating: 255, count: 64 * 36 * 4) as CFData))
        let image = try #require(CGImage(width: 64, height: 36, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        imageLayer.contents = image
        imageLayer.contentsScale = 2
        source.setNeedsLayout()
        source.layoutIfNeeded()
        return (source, imageLayer, image)
    }

    private func updateCover(_ cover: CALayer, from source: CALayer) throws {
        let selector = NSSelectorFromString("updateMenuBarCoverLayer:")
        let method = try #require(class_getInstanceMethod(type(of: source), selector))
        typealias Update = @convention(c) (AnyObject, Selector, CALayer) -> Void
        let implementation = unsafeBitCast(method_getImplementation(method), to: Update.self)
        implementation(source, selector, cover)
    }

    private func contents(of layer: CALayer) throws -> CGImage {
        let contents = try #require(layer.contents)
        return contents as! CGImage
    }
}
