import Foundation
import TileKit

/// TileKit's markings' constants and the strokes they are drawn with, for
/// the marking objects (Objects/), which draw as TileKit's Markings builds:
/// quads fast enough to follow a drag, where TileKit makes polygons.
enum MarkingShapes {
    static let line = Markings.line
    static let dash = Markings.dash.0, gap = Markings.dash.1
    static let double = Markings.double
    static let zebraKerb = Markings.zebraKerb
    static let zigzagInset = Markings.zigzagInset
    static let zigzagLine = Markings.zigzagLine
    static let letterSize = Vec2(Markings.busLetterSize.0, Markings.busLetterSize.1)
    static let shelter = Vec2(shelterSize.0, shelterSize.1)
    /// The letter A in a unit box, its outer ring turned counter-clockwise
    /// for the stencil, and the hole of its crossbar.
    static let letterA: [[Vec2]] = [Array(Markings.letterA[0].reversed()), Markings.letterA[1]]

    /// A painted strip along a polyline, as quads, one per segment.
    static func stroke(_ pts: [Vec2], width: Double) -> [[Vec2]] {
        guard pts.count >= 2 else { return [] }
        let side = offsetLine(pts, width / 2), other = offsetLine(pts, -width / 2)
        return (0..<(pts.count - 1)).map { i in [other[i], other[i + 1], side[i + 1], side[i]] }
    }
}
