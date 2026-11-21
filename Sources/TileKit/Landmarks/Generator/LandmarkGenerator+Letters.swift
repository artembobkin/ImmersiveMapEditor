import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// Lettering: the outlines of a text's letters from CoreText, for a
/// text shape.
extension LandmarkGenerator {
    // MARK: Letters

    /// The letters of a text in the Mac's bold sans face: for each, its
    /// outer rings counter-clockwise with their holes clockwise, in metres
    /// with the capitals `height` tall, the letter's foot on y 0 and its
    /// left at x 0, and its advance to the next; a space is an advance
    /// alone. Curves are flattened to a few segments and the rings
    /// simplified, so a letter is a few dozen corners.
    static func glyphs(_ text: String, height: Double) -> [(letters: [(outer: [P2], holes: [[P2]])], advance: Double)] {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 1, nil)
        let scale = height / Double(CTFontGetCapHeight(font))
        let chars = Array(text.utf16)
        var ids = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(font, chars, &ids, chars.count)
        var advances = [CGSize](repeating: .zero, count: chars.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, ids, &advances, chars.count)
        var out: [(letters: [(outer: [P2], holes: [[P2]])], advance: Double)] = []
        for (k, id) in ids.enumerated() {
            let advance = Double(advances[k].width) * scale
            guard id != 0, let path = CTFontCreatePathForGlyph(font, id, nil) else { out.append(([], advance)); continue }
            var rings: [[P2]] = []
            var ring: [P2] = []
            var last = P2.zero
            func add(_ q: CGPoint) { let p = P2(Double(q.x) * scale, Double(q.y) * scale); ring.append(p); last = p }
            path.applyWithBlock { element in
                let e = element.pointee
                switch e.type {
                case .moveToPoint:
                    if ring.count >= 3 { rings.append(ring) }
                    ring = []
                    add(e.points[0])
                case .addLineToPoint:
                    add(e.points[0])
                case .addQuadCurveToPoint:
                    let c = P2(Double(e.points[0].x) * scale, Double(e.points[0].y) * scale), q = P2(Double(e.points[1].x) * scale, Double(e.points[1].y) * scale)
                    let a = last
                    for i in 1...3 {
                        let t = Double(i) / 3, u = 1 - t
                        var p = a * (u * u)
                        p += c * (2 * u * t)
                        p += q * (t * t)
                        ring.append(p)
                    }
                    last = q
                case .addCurveToPoint:
                    let c1 = P2(Double(e.points[0].x) * scale, Double(e.points[0].y) * scale), c2 = P2(Double(e.points[1].x) * scale, Double(e.points[1].y) * scale)
                    let q = P2(Double(e.points[2].x) * scale, Double(e.points[2].y) * scale)
                    let a = last
                    for i in 1...4 {
                        let t = Double(i) / 4, u = 1 - t
                        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                        var p = a * w0
                        p += c1 * w1
                        p += c2 * w2
                        p += q * w3
                        ring.append(p)
                    }
                    last = q
                case .closeSubpath:
                    if ring.count >= 3 { rings.append(ring) }
                    ring = []
                @unknown default:
                    break
                }
            }
            if ring.count >= 3 { rings.append(ring) }
            // Simplified, and told apart: a ring inside an odd number of
            // others is a hole of the smallest ring around it.
            let simple: [[P2]] = rings.compactMap { r in
                let g = Geometry.polygon(r + [r[0]]).simplify(height * 0.035)
                guard let poly = g.polygons.max(by: { $0.area < $1.area }), poly.area > height * height * 0.002 else { return nil }
                return Array(poly.exterior.dropLast())
            }
            let polys = simple.map { Geometry.polygon($0 + [$0[0]]) }
            var holeOf = [Int?](repeating: nil, count: simple.count)
            for i in simple.indices {
                let inside = simple.indices.filter { $0 != i && polys[$0].contains(.point(simple[i][0])) }
                guard inside.count % 2 == 1, let parent = inside.min(by: { polys[$0].area < polys[$1].area }) else { continue }
                holeOf[i] = parent
            }
            var letters: [(outer: [P2], holes: [[P2]])] = []
            for i in simple.indices where holeOf[i] == nil {
                let outer = ccw(simple[i])
                let holes = simple.indices.filter { holeOf[$0] == i }.map { Array(ccw(simple[$0]).reversed()) }
                letters.append((outer, holes))
            }
            out.append((letters, advance))
        }
        return out
    }
}
