import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// A kept photo marked: everything but the landmark painted black and the
/// landmark framed in red, a panorama cut to it first.
enum StreetMarking {
    /// Paints everything outside `rect` black, `alpha` deep.
    static func mask(_ ctx: CGContext, outside rect: CGRect, in full: CGRect, alpha: Double) {
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(rect)
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
        ctx.fill(full)
        ctx.restoreGState()
    }

    /// A panorama cut around the landmark's box: the part, and the box
    /// within it.
    /// The cut around a panorama's box, as fractions: west, east, top, bottom.
    static func cutBounds(_ box: CGRect) -> (Double, Double, Double, Double) {
        (max(0, box.minX - 0.03), min(1, box.maxX + 0.03), max(0, box.minY - 0.04), min(1, box.maxY + 0.03))
    }

    static func cut(_ image: CGImage, _ box: CGRect) -> (CGImage, CGRect)? {
        let w = Double(image.width), h = Double(image.height)
        let (cx0, cx1, cy0, cy1) = cutBounds(box)
        let rect = CGRect(x: cx0 * w, y: cy0 * h, width: (cx1 - cx0) * w, height: (cy1 - cy0) * h).integral
        guard rect.width > 50, rect.height > 50, let part = image.cropping(to: rect) else { return nil }
        return (part, CGRect(x: (box.minX - cx0) / (cx1 - cx0), y: (box.minY - cy0) / (cy1 - cy0),
                             width: box.width / (cx1 - cx0), height: box.height / (cy1 - cy0)))
    }

    static func mark(_ file: URL, _ view: StreetView, maxSide: Int = 1280) throws {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw NSError(domain: "StreetMarking", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read the picture"])
        }
        var shown = image
        var box = view.box
        if view.photo.pano, let (part, inner) = cut(image, box) {
            shown = part
            box = inner
        }
        let scale = min(1, Double(maxSide) / Double(max(shown.width, shown.height)))
        let w = Int(Double(shown.width) * scale), h = Int(Double(shown.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.draw(shown, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics' y goes up: the box's fractions are from the top.
        let rect = CGRect(x: box.minX * Double(w), y: (1 - box.maxY) * Double(h), width: box.width * Double(w), height: box.height * Double(h))
            .insetBy(dx: -3, dy: -3)
        mask(ctx, outside: rect, in: CGRect(x: 0, y: 0, width: w, height: h), alpha: 1)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
        ctx.setLineWidth(max(3, Double(w) * 0.004))
        ctx.stroke(rect)
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
