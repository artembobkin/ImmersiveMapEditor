import Foundation
import Geometry

/// The palette as an image: flat colours in 16 px cells from the top left.
/// No patterns: a pattern repeated over a large surface shimmers in the
/// distance. UVs come out with V up (row 0 at V = 1), as the build has
/// them until the export turns them.
public final class PaletteTexture {
    public static let cell = 16
    /// Every palette is 512 px, 1024 cells, whatever the tile needs: the
    /// engine keeps the tiles' palettes as the layers of texture arrays,
    /// which share one size, and one size everywhere is simplest and
    /// fastest there (the user, 2026-11-02).
    public static let size = 512
    public static let cells = (size / cell) * (size / cell)
    public let size = PaletteTexture.size
    public private(set) var pixels: [UInt8]           // RGB, row 0 on top
    public private(set) var flat: [String: (Double, Double)] = [:]
    /// The name of each cell, in order.
    public let names: [String]

    /// The base palette: every colour, in `Palette.all`'s order, so a
    /// name's cell is the same in every build.
    public convenience init() { self.init(names: Palette.all.map(\.0)) }

    /// A palette of just these names, in the order given.
    public init(names: [String]) {
        let cell = PaletteTexture.cell, n = PaletteTexture.size
        precondition(names.count <= PaletteTexture.cells, "too many colours for the palette: \(names.count)")
        self.names = names
        pixels = [UInt8](repeating: 0, count: n * n * 3)
        let perRow = n / cell
        for (i, name) in names.enumerated() {
            let (r, c) = (i / perRow, i % perRow)
            let (cr, cg, cb) = Palette.rgb(Palette.hexAny(name) ?? "#FF00FF")
            for y in (r * cell)..<((r + 1) * cell) {
                for x in (c * cell)..<((c + 1) * cell) {
                    let k = (y * n + x) * 3
                    pixels[k] = UInt8(cr); pixels[k + 1] = UInt8(cg); pixels[k + 2] = UInt8(cb)
                }
            }
            flat[name] = (Double(c * cell) + Double(cell) / 2, Double(r * cell) + Double(cell) / 2)
        }
    }

    public func has(_ name: String) -> Bool { flat[name] != nil }

    /// The UV of a colour's cell centre.
    public func uv(_ name: String) -> P2 {
        guard let (px, py) = flat[name] else { fatalError("no colour \(name) in the palette") }
        return P2(px / Double(size), 1 - py / Double(size))
    }

    /// The name of the cell a UV (V up) points into.
    public func name(at uv: P2) -> String? {
        let cell = PaletteTexture.cell, perRow = size / cell
        let c = Int(uv.x * Double(size)) / cell, r = Int((1 - uv.y) * Double(size)) / cell
        let i = r * perRow + c
        return i >= 0 && i < names.count ? names[i] : nil
    }
}
