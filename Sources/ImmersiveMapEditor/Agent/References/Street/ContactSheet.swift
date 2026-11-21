import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// A grid of pictures with a label each, and a red frame where one is
/// given: what the user looks at. The agent gets each picture by itself
/// (`one`), larger, since its eyes need the pixels.
enum ContactSheet {
    /// One picture with its frame (the outside dimmed), a panorama cut to
    /// it first, at most `maxSide` across, to a JPEG.
    static func one(_ cell: Cell, maxSide: Int, to file: URL) throws {
        guard let url = cell.image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        var shown = image
        var box = cell.box
        if cell.cut, let b = box, let (part, inner) = StreetMarking.cut(image, b) {
            shown = part
            box = inner
        }
        let scale = min(1, Double(maxSide) / Double(max(shown.width, shown.height)))
        let w = Int(Double(shown.width) * scale), h = Int(Double(shown.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(shown, in: full)
        if let box {
            let frame = CGRect(x: box.minX * Double(w), y: (1 - box.maxY) * Double(h), width: box.width * Double(w), height: box.height * Double(h))
            StreetMarking.mask(ctx, outside: frame, in: full, alpha: 0.55)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
            ctx.setLineWidth(max(3, Double(w) * 0.004))
            ctx.stroke(frame.insetBy(dx: -2, dy: -2))
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    struct Cell {
        let image: URL?
        /// The frame, as fractions of the picture (from the top left).
        let box: CGRect?
        /// Whether to cut the picture to the frame first (a panorama).
        let cut: Bool
        let label: String
    }

    static func draw(_ cells: [Cell], to file: URL) throws {
        let columns = cells.count <= 4 ? 2 : cells.count <= 9 ? 3 : 4, rows = (cells.count + columns - 1) / columns
        let cw = 320, ch = 260, pad = 6
        let w = columns * cw, h = rows * ch
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (k, cell) in cells.enumerated() {
            let col = k % columns, row = k / columns
            // CoreGraphics' y goes up: the first row at the top.
            let area = CGRect(x: col * cw + pad, y: h - (row + 1) * ch + pad + 22, width: cw - 2 * pad, height: ch - 2 * pad - 22)
            if let url = cell.image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                var shown = image
                var box = cell.box
                if cell.cut, let b = box, let (part, inner) = StreetMarking.cut(image, b) {
                    shown = part
                    box = inner
                }
                let scale = min(area.width / Double(shown.width), area.height / Double(shown.height))
                let dw = Double(shown.width) * scale, dh = Double(shown.height) * scale
                let at = CGRect(x: area.midX - dw / 2, y: area.midY - dh / 2, width: dw, height: dh)
                ctx.draw(shown, in: at)
                if let box {
                    let frame = CGRect(x: at.minX + box.minX * dw, y: at.minY + (1 - box.maxY) * dh, width: box.width * dw, height: box.height * dh)
                    // Dimmed, not painted over: the agent judges the pose by what is around.
                    StreetMarking.mask(ctx, outside: frame, in: at, alpha: 0.65)
                    ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
                    ctx.setLineWidth(3)
                    ctx.stroke(frame.insetBy(dx: -1.5, dy: -1.5))
                }
            }
            let text = NSAttributedString(string: cell.label, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 13, nil), .foregroundColor: CGColor(gray: 0.95, alpha: 1)])
            let line = CTLineCreateWithAttributedString(text)
            ctx.textPosition = CGPoint(x: Double(col * cw + pad), y: Double(h - (row + 1) * ch + pad))
            CTLineDraw(line, ctx)
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
