import AppKit

/// Source artwork in the menu bar; the app's keyboard remains the no-artwork fallback.
enum MenuBarIcon {
    static func inputSourceImage(_ source: NSImage?) -> NSImage {
        guard let source, source.size.width.isFinite, source.size.height.isFinite,
              source.size.width > 0, source.size.height > 0,
              let result = source.copy() as? NSImage else { return image }
        let scale = min(22 / source.size.width, 18 / source.size.height)
        result.size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        // A monochrome input-method PDF often arrives without a template flag.
        // Do not mask colored icons or black-on-white keyboard labels: their
        // opaque background is part of the artwork, and masking would erase it.
        result.isTemplate = source.isTemplate || hasSingleInkOnTransparency(source)
        return result
    }

    private static func hasSingleInkOnTransparency(_ source: NSImage) -> Bool {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 36,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 44, height: 36))
        source.draw(in: NSRect(x: 0, y: 0, width: 44, height: 36),
                    from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        var transparent = false
        var darkest: CGFloat = 1
        var lightest: CGFloat = 0
        var visible = false
        for y in 0..<36 {
            for x in 0..<44 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent < 0.05 { transparent = true }
                guard color.alphaComponent > 0.1 else { continue }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                guard let low = channels.min(), let high = channels.max(), high - low < 0.04 else { return false }
                darkest = min(darkest, low)
                lightest = max(lightest, high)
                if lightest - darkest > 0.12 { return false }
                visible = true
            }
        }
        return visible && transparent
    }

    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.white.setStroke()
            let deck = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 20, height: 10),
                                    xRadius: 2, yRadius: 2)
            deck.lineWidth = 1.3
            deck.stroke()

            NSColor.white.setFill()
            for index in 0..<3 {
                let raised = index == 1
                let key = NSRect(x: 3 + CGFloat(index) * 5.9, y: raised ? 6.7 : 6.4,
                                 width: 4.2, height: raised ? 5.1 : 4.8)
                NSBezierPath(roundedRect: key, xRadius: 0.9, yRadius: 0.9).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
