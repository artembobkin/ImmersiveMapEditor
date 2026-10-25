/// An edge's identity for merging duplicates: its first two points in its
/// lesser direction, ordered by their ordinates: JTS's `EdgeKey`. GEOS keeps
/// the keys in an ordered map (JTS in a hash map, whose `-0.0` and `0.0`
/// hash apart), so the keys here compare by value, `-0.0` equal to `0.0`.
struct EdgeKey: Comparable {
    let p0x: Double, p0y: Double, p1x: Double, p1y: Double

    init(_ edge: Edge) throws {
        if try edge.direction() {
            (p0x, p0y, p1x, p1y) = (edge.pts[0].x, edge.pts[0].y, edge.pts[1].x, edge.pts[1].y)
        } else {
            let len = edge.size
            (p0x, p0y, p1x, p1y) = (edge.pts[len - 1].x, edge.pts[len - 1].y, edge.pts[len - 2].x, edge.pts[len - 2].y)
        }
    }

    func compareTo(_ ek: EdgeKey) -> Int {
        if p0x < ek.p0x { return -1 }
        if p0x > ek.p0x { return 1 }
        if p0y < ek.p0y { return -1 }
        if p0y > ek.p0y { return 1 }
        if p1x < ek.p1x { return -1 }
        if p1x > ek.p1x { return 1 }
        if p1y < ek.p1y { return -1 }
        if p1y > ek.p1y { return 1 }
        return 0
    }

    static func < (a: EdgeKey, b: EdgeKey) -> Bool { a.compareTo(b) < 0 }
    static func == (a: EdgeKey, b: EdgeKey) -> Bool { a.compareTo(b) == 0 }
}

extension EdgeKey: Hashable {
    func hash(into h: inout Hasher) {
        // Equal keys hash alike, -0.0 as 0.0.
        for v in [p0x, p0y, p1x, p1y] { h.combine(v == 0 ? 0 : v) }
    }
}
