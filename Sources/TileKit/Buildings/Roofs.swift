import Foundation
import Geometry
import simd

// Roofs by `roof:shape`: gabled, hipped and round over a rectangle, a
// pyramid, a hip with a flat top for any other pitched outline, domes and
// onions turned on a lathe.

private let hipSlope = 0.55      // rise over run of a hip roof

func roofOn(_ b: Builder, _ poly: Geometry, _ z: Double, _ h: Double, _ shape: String, _ wall: String,
            _ roof: String, _ flatColour: String) {
    let rect = poly.minimumRotatedRectangle
    let rectangular = poly.interiors.isEmpty && rect.area > 0 && poly.area / rect.area > 0.85
    if h < 0.2 || shape == "flat" {
        b.fill(poly, z, flatColour, "roofs")
    } else if ["gabled", "hipped", "round", "gambrel", "mansard"].contains(shape) && rectangular {
        pitched(b, rect, z, h, shape, wall, roof)
    } else if shape == "pyramidal" && poly.area / max(poly.convexHull.area, 1e-6) > 0.9 {
        pyramid(b, poly, z, h, roof)
    } else if !hip(b, poly, z, roof) {
        b.fill(poly, z, roof, "roofs")
    }
}

func pitched(_ b: Builder, _ rect: Geometry, _ z: Double, _ h: Double, _ shape: String, _ wall: String,
             _ roof: String) {
    var c = rect.oriented(1).exterior.prefix(4).map { v3($0, z) }
    if (c[1] - c[0]).length < (c[2] - c[1]).length { c = Array(c[1...]) + [c[0]] }
    let up = V3(0, 0, h)
    var r0 = (c[3] + c[0]) / 2 + up, r1 = (c[1] + c[2]) / 2 + up
    if shape == "round" {
        let n = 6
        let width = c[3] - c[0]
        let arc0 = (0...n).map { k -> V3 in
            let a = Double.pi * Double(k) / Double(n)
            return c[0] + width * (0.5 - 0.5 * cos(a)) + V3(0, 0, h * sin(a))
        }
        let arc1 = arc0.map { $0 + (c[1] - c[0]) }
        for k in 0..<n { b.paint([arc0[k], arc1[k], arc1[k + 1], arc0[k + 1]], roof, "roofs") }
        b.paint([arc1[0], arc1[n]] + Array(arc1[1..<n].reversed()), wall, "roofs")
        b.paint([arc0[n], arc0[0]] + Array(arc0[1..<n]), wall, "roofs")
        return
    }
    var end = wall
    if shape == "hipped" || shape == "mansard" {
        let axis = (r1 - r0).normalized
        let inset = min((c[3] - c[0]).length / 2, (r1 - r0).length / 2 - 0.05)
        r0 = r0 + axis * inset
        r1 = r1 - axis * inset
        end = roof
    }
    b.paint([c[0], c[1], r1, r0], roof, "roofs")
    b.paint([c[2], c[3], r0, r1], roof, "roofs")
    b.paint([c[1], c[2], r1], end, "roofs")
    b.paint([c[3], c[0], r0], end, "roofs")
}

func pyramid(_ b: Builder, _ poly: Geometry, _ z: Double, _ h: Double, _ colour: String) {
    let centre = poly.contains(poly.centroid) ? poly.centroid.xy : poly.representativePoint.xy
    let apex = v3(centre, z + h)
    for (a, c) in edges(.polygon(poly.exterior)) {
        b.paint([v3(a, z), v3(c, z), apex], colour, "roofs")
    }
}

/// A ring with its inside on the left, every edge moved left by d, corners
/// mitred. nil if an edge turns round (the inset collapsed).
func insetRing(_ coords: [P2], _ d: Double) -> [P2]? {
    let pts = Array(coords.dropLast())
    let n = pts.count
    var out: [P2] = []
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n]
        let e0 = (p1 - p0).normalized, e1 = (p2 - p1).normalized
        let n0 = P2(-e0.y, e0.x), n1 = P2(-e1.y, e1.x)
        var bis = n0 + n1
        if bis.length < 1e-6 { return nil }
        bis = bis.normalized
        let cos = bis.dot(n1)
        if cos < 0.3 { return nil }
        out.append(p1 + bis * (d / cos))
    }
    for i in 0..<n {
        let before = pts[(i + 1) % n] - pts[i]
        let after = out[(i + 1) % n] - out[i]
        if before.dot(after) <= 0 { return nil }
    }
    return out
}

/// A hip roof with a flat top over any outline: every ring inset by d, the
/// band between sloped up by d * hipSlope. Tries smaller insets before it
/// gives up.
func hip(_ b: Builder, _ outline: Geometry, _ z: Double, _ colour: String) -> Bool {
    let poly = outline.oriented(1)
    var d = min(0.8 * poly.area / poly.length, 6.0)
    let source = [poly.exterior] + poly.interiors
    for _ in 0..<4 {
        let rings = source.map { insetRing($0, d) }
        if rings.allSatisfy({ $0 != nil }) {
            let top = Geometry.polygon(rings[0]!, holes: rings.dropFirst().map { $0! })
            if top.isValid && top.area > 1 && poly.contains(top) {
                let h = d * hipSlope
                for (ring, inner) in zip(source, rings) {
                    let coords = Array(ring.dropLast())
                    for i in 0..<coords.count {
                        let j = (i + 1) % coords.count
                        b.paint([v3(coords[i], z), v3(coords[j], z), v3(inner![j], z + h), v3(inner![i], z + h)],
                                colour, "roofs")
                    }
                }
                b.fill(top, z + h, colour, "roofs")
                return true
            }
        }
        d *= 0.6
    }
    return false
}

private let dome: [(Double, Double)] = [(1.0, 0.0), (0.92, 0.38), (0.71, 0.71), (0.38, 0.92), (0.0, 1.0)]
private let onion: [(Double, Double)] = [(0.85, 0.0), (1.0, 0.15), (0.95, 0.32), (0.68, 0.52), (0.38, 0.7),
                                         (0.13, 0.86), (0.04, 0.95), (0.0, 1.0)]

func lathe(_ b: Builder, _ poly: Geometry, _ z: Double, _ h: Double, _ shape: String, _ colour: String) {
    let centre = poly.centroid.xy
    let r = (poly.area / .pi).squareRoot()
    let segments = 12
    let rings = (shape == "dome" ? dome : onion).map { f, t in
        (0..<segments).map { j -> V3 in
            let a = 2 * Double.pi * Double(j) / Double(segments)
            return V3(centre.x + r * f * cos(a), centre.y + r * f * sin(a), z + h * t)
        }
    }
    for k in 0..<(rings.count - 1) {
        let lower = rings[k], upper = rings[k + 1]
        for j in 0..<segments {
            let j2 = (j + 1) % segments
            if (upper[j] - upper[j2]).length < 1e-4 {
                b.paint([lower[j], lower[j2], upper[j]], colour, "roofs")
            } else {
                b.paint([lower[j], lower[j2], upper[j2], upper[j]], colour, "roofs")
            }
        }
    }
}
