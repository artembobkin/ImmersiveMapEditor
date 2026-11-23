import CoreGraphics
import CoreText
import Foundation
import ImageIO
import TileKit

/// A palette drawn as the palette agent sees it (`PaletteMCP`'s
/// show_palette): every colour of the palette in use (`Palette`, applied
/// first) in its groups, a wall or landmark colour as a little facade of
/// its three sides to the sun, lit, side and shade, each with a window of
/// its reveal and glass, as the build paints them, and the other colours
/// as plain swatches; each labelled with its name and hex. What the agent
/// judges its colours by is what they look like side by side, not their
/// numbers.
enum PaletteSheet {
    static func draw(title: String, set: Set<String>, to file: URL) throws {
        let groups: [(String, [(String, String)], Bool)] = [
            ("Landmarks", Palette.landmark, true), ("Walls", Palette.walls, true),
            ("Roads and ground", Palette.base, false), ("Props", Palette.props, false),
        ]
        let columns = 6, cw = 160, ch = 112, head = 30, top = 40
        let rows = groups.map { ($0.1.count + columns - 1) / columns }
        let w = columns * cw, h = top + groups.count * head + rows.reduce(0, +) * ch
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw MCPChannel.Failure("cannot draw the palette")
        }
        ctx.setFillColor(CGColor(gray: 0.14, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics' y goes up: `y` counts down from the top.
        var y = top
        label(ctx, title, x: 10, y: h - 28, size: 18)
        for (g, group) in groups.enumerated() {
            label(ctx, group.0, x: 10, y: h - y - 22, size: 15)
            y += head
            for (k, colour) in group.1.enumerated() {
                let col = k % columns, row = k / columns
                let cell = CGRect(x: col * cw + 8, y: h - y - (row + 1) * ch + 30, width: cw - 16, height: ch - 38)
                if group.2 { facade(ctx, colour.0, in: cell) } else { swatch(ctx, colour.1, in: cell) }
                let mark = set.contains(colour.0) ? " •" : ""
                label(ctx, colour.0 + mark, x: Double(col * cw + 8), y: Double(h - y - (row + 1) * ch + 15), size: 12)
                label(ctx, colour.1, x: Double(col * cw + 8), y: Double(h - y - (row + 1) * ch + 2), size: 11, grey: 0.7)
            }
            y += rows[g] * ch
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else {
            throw MCPChannel.Failure("cannot write the palette's picture")
        }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else { throw MCPChannel.Failure("cannot write the palette's picture") }
    }

    /// A wall colour's three sides, each with a window of its reveal and glass.
    private static func facade(_ ctx: CGContext, _ name: String, in cell: CGRect) {
        let band = cell.width / 3
        for (i, side) in ["lit", "side", "shade"].enumerated() {
            let r = CGRect(x: cell.minX + Double(i) * band, y: cell.minY, width: band, height: cell.height)
            fill(ctx, Palette.hex("\(name).\(side)"), r)
            let window = CGRect(x: r.midX - band * 0.22, y: r.minY + cell.height * 0.3, width: band * 0.44, height: cell.height * 0.45)
            fill(ctx, Palette.hex("\(name).reveal.\(side)"), window)
            fill(ctx, Palette.hex("\(name).glass.\(side)"), window.insetBy(dx: 3, dy: 3))
        }
    }

    private static func swatch(_ ctx: CGContext, _ hex: String, in cell: CGRect) { fill(ctx, hex, cell) }

    private static func fill(_ ctx: CGContext, _ hex: String?, _ rect: CGRect) {
        let (r, g, b) = Palette.rgb(hex ?? "#FF00FF")
        ctx.setFillColor(CGColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: 1))
        ctx.fill(rect)
    }

    private static func label(_ ctx: CGContext, _ text: String, x: Double, y: Double, size: Double, grey: Double = 0.95) {
        let s = NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, size, nil), .foregroundColor: CGColor(gray: grey, alpha: 1)])
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(s), ctx)
    }

    private static func label(_ ctx: CGContext, _ text: String, x: Int, y: Int, size: Double) {
        label(ctx, text, x: Double(x), y: Double(y), size: size)
    }
}
