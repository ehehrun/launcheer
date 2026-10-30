import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Launcheer

struct SettingsTests {
    @Test(arguments: [false, true])
    func selectedImagesAreStoredWithoutChangingTheSource(forIcon: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try imageFixture()
        let source = directory.appendingPathComponent("selected.png")
        try original.write(to: source)
        let destination = directory.appendingPathComponent("support", isDirectory: true)

        let (saved, preview) = try forIcon
            ? SettingsImageFiles.saveIcon(from: source, directory: destination)
            : SettingsImageFiles.saveBackground(from: source, directory: destination)

        #expect(saved.lastPathComponent == (forIcon ? "custom-icon.png" : "custom-background"))
        #expect(saved.deletingLastPathComponent() == destination)
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: saved) == (forIcon ? preview : original))
        let previewSource = try #require(CGImageSourceCreateWithData(preview as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
        #expect(decoded.width == (forIcon ? 512 : 320))
        #expect(decoded.height == (forIcon ? 384 : 240))
        #expect(decoded.bitsPerComponent == 8)
    }

    @Test(arguments: [false, true])
    func anUnreadableOrCorruptSelectionKeepsThePreviousImage(forIcon: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("launcheer-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("selected.png")
        try imageFixture().write(to: source)
        let destination = directory.appendingPathComponent("support", isDirectory: true)
        let (saved, _) = try forIcon
            ? SettingsImageFiles.saveIcon(from: source, directory: destination)
            : SettingsImageFiles.saveBackground(from: source, directory: destination)
        let previous = try Data(contentsOf: saved)

        for exists in [true, false] {
            if exists { try Data("not an image".utf8).write(to: source) }
            else { try FileManager.default.removeItem(at: source) }
            #expect(throws: (any Error).self) {
                if forIcon { _ = try SettingsImageFiles.saveIcon(from: source, directory: destination) }
                else { _ = try SettingsImageFiles.saveBackground(from: source, directory: destination) }
            }
            #expect(try Data(contentsOf: saved) == previous)
        }
    }

    private func imageFixture() throws -> Data {
        let color = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 1024, height: 768, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 768))
        let image = try #require(context.makeImage())
        let data = try #require(CFDataCreateMutable(kCFAllocatorDefault, 0))
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
