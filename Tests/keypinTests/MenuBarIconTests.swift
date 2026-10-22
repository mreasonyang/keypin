import AppKit
import XCTest
@testable import keypin

final class MenuBarIconTests: XCTestCase {
    /// Real bitmap fixtures keep these tests independent of installed input methods,
    /// the user's selected source, and the menu bar's current appearance.
    private func image(width: Int = 32, height: Int = 32,
                       pixel: (Int, Int) -> NSColor) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: width * 4, bitsPerPixel: 32)!
        for y in 0..<height {
            for x in 0..<width {
                // Write known RGBA bytes so fixture creation does not depend on
                // AppKit's NSBitmapImageRep.setColor color-space conversion.
                let color = pixel(x, y).usingColorSpace(.deviceRGB)!
                let channels = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
                for (index, channel) in channels.enumerated() {
                    bitmap.bitmapData![(y * width + x) * 4 + index] = UInt8((max(0, min(1, channel)) * 255).rounded())
                }
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    private func color(_ image: NSImage, x: CGFloat, y: CGFloat = 0.5) throws -> NSColor {
        var rect = NSRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(bitmap.colorAt(x: min(bitmap.pixelsWide - 1, Int(CGFloat(bitmap.pixelsWide) * x)),
                                            y: min(bitmap.pixelsHigh - 1, Int(CGFloat(bitmap.pixelsHigh) * y)))?
            .usingColorSpace(.deviceRGB))
    }

    func testBlackInkOnTransparencyBecomesAnAppearanceAdaptiveTemplate() throws {
        let original = image { x, y in
            (8..<24).contains(x) && (8..<24).contains(y) ? .black : .clear
        }
        let result = MenuBarIcon.inputSourceImage(original)
        XCTAssertTrue(result.isTemplate)
        XCTAssertGreaterThan(try color(result, x: 0.5).alphaComponent, 0.95)
        XCTAssertLessThan(try color(result, x: 0.05, y: 0.05).alphaComponent, 0.05)
    }

    func testWhiteInkOnTransparencyAlsoBecomesATemplate() {
        let original = image { x, y in
            (8..<24).contains(x) && (8..<24).contains(y) ? .white : .clear
        }
        XCTAssertTrue(MenuBarIcon.inputSourceImage(original).isTemplate)
    }

    func testOpaqueBlackAndWhiteArtworkRetainsItsInternalContrast() throws {
        let original = image { x, _ in x < 16 ? .black : .white }
        let result = MenuBarIcon.inputSourceImage(original)
        XCTAssertFalse(result.isTemplate, "Making a black-and-white source icon a template erases its interior artwork")
        XCTAssertLessThan(try color(result, x: 0.25).redComponent, 0.05)
        XCTAssertGreaterThan(try color(result, x: 0.75).redComponent, 0.95)
        XCTAssertGreaterThan(try color(result, x: 0.25).alphaComponent, 0.95)
        XCTAssertGreaterThan(try color(result, x: 0.75).alphaComponent, 0.95)
    }

    func testColorArtworkRetainsBothColors() throws {
        let original = image { x, y in
            guard (4..<28).contains(x), (4..<28).contains(y) else { return .clear }
            return x < 16 ? .red : .blue
        }
        let result = MenuBarIcon.inputSourceImage(original)
        XCTAssertFalse(result.isTemplate)
        let left = try color(result, x: 0.25)
        let right = try color(result, x: 0.75)
        XCTAssertGreaterThan(left.redComponent, 0.95)
        XCTAssertLessThan(left.blueComponent, 0.05)
        XCTAssertGreaterThan(right.blueComponent, 0.95)
        XCTAssertLessThan(right.redComponent, 0.05)
    }

    func testOpaqueSingleColorRectangleIsNotTreatedAsAnInkMask() {
        let original = image { _, _ in .black }
        XCTAssertFalse(MenuBarIcon.inputSourceImage(original).isTemplate)
    }

    func testMissingAndZeroSizedImagesUseTheKeyboardFallback() throws {
        for original in [nil, NSImage(size: .zero), NSImage(size: NSSize(width: 0, height: 16))] {
            let result = MenuBarIcon.inputSourceImage(original)
            XCTAssertTrue(result.isTemplate)
            XCTAssertEqual(result.size, MenuBarIcon.image.size)
            var rect = NSRect(origin: .zero, size: result.size)
            XCTAssertNotNil(result.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        }
    }

    func testNormalizationCopiesTheImageAndFitsWithoutDistortingItsAspectRatio() {
        for dimensions in [(44, 16), (12, 32)] {
            let original = image(width: dimensions.0, height: dimensions.1) { x, y in
                x > 1 && y > 1 ? .black : .clear
            }
            let originalSize = original.size
            let result = MenuBarIcon.inputSourceImage(original)
            XCTAssertFalse(result === original)
            XCTAssertEqual(original.size, originalSize)
            XCTAssertFalse(original.isTemplate, "Template conversion must not mutate a catalog-owned image")
            XCTAssertLessThanOrEqual(result.size.width, 22)
            XCTAssertLessThanOrEqual(result.size.height, 18)
            XCTAssertGreaterThan(result.size.width, 0)
            XCTAssertGreaterThan(result.size.height, 0)
            XCTAssertEqual(result.size.width / result.size.height,
                           originalSize.width / originalSize.height, accuracy: 0.001)
        }
    }
}
