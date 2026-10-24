import Metal
import simd

// What the Roads view draws with: one vertex format for everything, meshes
// built from it, polygons filled through the stencil, the colours.

struct Vertex {
    var colour: SIMD4<Float>
    var position: SIMD2<Float>
    var extrude: SIMD2<Float>
    var pixel: Float = 0
}

struct Uniforms {
    var view: SIMD4<Float>      // the centre in metres, half the view's size in points
    var scale: SIMD4<Float>     // points per metre
}

func rgb(_ hex: UInt32, _ alpha: Float = 1) -> SIMD4<Float> {
    SIMD4(Float((hex >> 16) & 255) / 255, Float((hex >> 8) & 255) / 255, Float(hex & 255) / 255, alpha)
}

/// The colours, the tile's own palette (build/common.py) where it has one.
enum Colours {
    static let ground = rgb(0xE6E2DC)
    static let building = rgb(0xD2CCC4)
    static let buildingEdge = rgb(0xB9B2A9)
    static let asphalt = rgb(0x6E6A7D)
    static let kerb = rgb(0xA6A3B1)
    static let marking = rgb(0xECE8E1)
    static let yellow = rgb(0xE8C24A)
    static let bad = rgb(0xE5484D)
    static let cutEdge = rgb(0xE5484D)
    static let centreLine = rgb(0x3C7DD9, 0.55)
    static let crossing = rgb(0x3C7DD9)
    static let stop = rgb(0x2E9E5B)
    static let tileEdge = rgb(0x8A6FD1, 0.8)
    static let shelter = rgb(0xF2EBDD)
    static let shelterEdge = rgb(0x5B5E6C)
    static let handle = rgb(0xFFFFFF)
    static let handleEdge = rgb(0x30303A)
    static let selected = rgb(0xFF8A1F)
    static let draft = rgb(0x1F9BFF)
}

/// Builds vertex lists.
struct Mesh {
    var v: [Vertex] = []

    mutating func triangle(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ colour: SIMD4<Float>) {
        for p in [a, b, c] { v.append(Vertex(colour: colour, position: SIMD2(Float(p.x), Float(p.y)), extrude: .zero)) }
    }

    /// A convex polygon, as a fan.
    mutating func convex(_ pts: [Vec2], _ colour: SIMD4<Float>) {
        guard pts.count >= 3 else { return }
        for i in 1..<(pts.count - 1) { triangle(pts[0], pts[i], pts[i + 1], colour) }
    }

    /// A ring as a fan for the stencil: overlapping triangles count the
    /// winding, the cover pass fills where it is not zero.
    mutating func fan(_ ring: [Vec2]) {
        convex(ring, .zero)
    }

    /// A line `width` screen points wide from a to b.
    mutating func pixelLine(_ a: Vec2, _ b: Vec2, width: Float, _ colour: SIMD4<Float>) {
        let d = b - a
        guard d.length > 1e-9 else { return }
        let n = d.normalized.left
        let e = SIMD2(Float(n.x), Float(n.y)) * width / 2
        let pa = SIMD2(Float(a.x), Float(a.y)), pb = SIMD2(Float(b.x), Float(b.y))
        let quad = [(pa, -e), (pb, -e), (pb, e), (pa, -e), (pb, e), (pa, e)]
        for (p, x) in quad { v.append(Vertex(colour: colour, position: p, extrude: x, pixel: 1)) }
    }

    mutating func pixelPolyline(_ pts: [Vec2], closed: Bool = false, width: Float, _ colour: SIMD4<Float>) {
        guard pts.count >= 2 else { return }
        for i in 0..<(pts.count - 1) { pixelLine(pts[i], pts[i + 1], width: width, colour) }
        if closed { pixelLine(pts[pts.count - 1], pts[0], width: width, colour) }
    }

    /// A square `size` screen points across at p.
    mutating func pixelSquare(_ p: Vec2, size: Float, _ colour: SIMD4<Float>) {
        let h = size / 2
        let c = SIMD2(Float(p.x), Float(p.y))
        for e in [SIMD2<Float>(-h, -h), SIMD2(h, -h), SIMD2(h, h), SIMD2(-h, -h), SIMD2(h, h), SIMD2(-h, h)] {
            v.append(Vertex(colour: colour, position: c, extrude: e, pixel: 1))
        }
    }

    /// A strip `width` metres wide along a segment.
    mutating func band(_ a: Vec2, _ b: Vec2, width: Double, _ colour: SIMD4<Float>) {
        let n = (b - a).normalized.left * (width / 2)
        convex([a - n, b - n, b + n, a + n], colour)
    }
}

/// A batch filled through the stencil: its rings' fans, then one cover
/// quad over their bounds.
struct StencilBatch {
    var fans = Mesh()
    var cover = Mesh()
    mutating func add(_ rings: [[Vec2]]) {
        for r in rings { fans.fan(r) }
    }
    mutating func close(_ colour: SIMD4<Float>) {
        let pts = fans.v.map(\.position)
        guard let first = pts.first else { return }
        var lo = first, hi = first
        for p in pts { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let a = Vec2(Double(lo.x) - 1, Double(lo.y) - 1), b = Vec2(Double(hi.x) + 1, Double(hi.y) + 1)
        cover.convex([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], colour)
    }
}
