import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// A photo and the model from the photo's place, side by side, the same
/// height: what the agent compares.
enum SideBySide {
    static func draw(_ left: URL, _ right: URL, to file: URL, labels: (String, String) = ("photo", "model, from the same place")) throws {
        func read(_ url: URL) -> CGImage? {
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        guard let a = read(left), let b = read(right) else { return }
        let h = 640, gap = 8, label = 24
        let wa = a.width * h / a.height, wb = b.width * h / b.height
        let w = wa + gap + wb
        guard let ctx = CGContext(data: nil, width: w, height: h + label, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h + label))
        ctx.draw(a, in: CGRect(x: 0, y: label, width: wa, height: h))
        ctx.draw(b, in: CGRect(x: wa + gap, y: label, width: wb, height: h))
        for (text, x) in [(labels.0, 4), (labels.1, wa + gap + 4)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 14, nil), .foregroundColor: CGColor(gray: 0.95, alpha: 1)]))
            ctx.textPosition = CGPoint(x: Double(x), y: 6)
            CTLineDraw(line, ctx)
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
