/// The polygons of a region inside one raster cell, and the point-in-polygon test on them.
///
/// Ported from `multipolygon.rs` of the Rust crate country-boundaries 1.2.0 (Apache-2.0).
/// The winding number test is modified from code by softSurfer (2000) and Dan Sunday (2012),
/// http://geomalgorithms.com/a03-_inclusion.html, which may be freely used and modified for
/// any purpose provided that this copyright notice is included with it. SoftSurfer makes no
/// warranty for this code and cannot be held liable for any real or imagined damage resulting
/// from its use. Users of this code must verify correctness for their application.

/// A point in the local coordinates of a cell: 0 to 0xffff across it on each axis.
struct Point: Equatable, Sendable {
    var x: UInt16
    var y: UInt16
}

/// Outer and inner rings of a region in a cell. A point is covered when more outer rings than
/// inner rings contain it.
struct Multipolygon: Equatable, Sendable {
    var outer: [[Point]]
    var inner: [[Point]]

    /// Returns whether the point is inside the region.
    func covers(_ point: Point) -> Bool {
        var insides = 0
        for area in outer where isPointInPolygon(point, area) {
            insides += 1
        }
        for area in inner where isPointInPolygon(point, area) {
            insides -= 1
        }
        return insides > 0
    }
}

/// Returns whether the point is inside the ring, by its winding number. Only the lower and the
/// left edges of a ring count as inside.
func isPointInPolygon(_ p: Point, _ v: [Point]) -> Bool {
    var wn = 0
    guard var a = v.last else {
        return false
    }
    for b in v {
        if a.y <= p.y {
            if b.y > p.y && isLeft(a, b, p) > 0 {
                wn += 1
            }
        } else if b.y <= p.y && isLeft(a, b, p) < 0 {
            wn -= 1
        }
        a = b
    }
    return wn != 0
}

/// Returns twice the signed area of the triangle p0, p1, p: positive when p lies left of the
/// line from p0 to p1. It is computed in 64 bits, which cannot overflow.
func isLeft(_ p0: Point, _ p1: Point, _ p: Point) -> Int64 {
    (Int64(p1.x) - Int64(p0.x)) * (Int64(p.y) - Int64(p0.y))
        - (Int64(p.x) - Int64(p0.x)) * (Int64(p1.y) - Int64(p0.y))
}
