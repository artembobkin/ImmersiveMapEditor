/// Counts the crossings of a ray from a point to the right with the segments
/// of a ring, to locate the point: JTS's `RayCrossingCounter`.
public struct RayCrossingCounter {
    let p: Coordinate
    public private(set) var count = 0
    public private(set) var isOnSegment = false

    public init(_ p: Coordinate) { self.p = p }

    public static func locatePointInRing(_ p: Coordinate, _ ring: [Coordinate]) -> Int {
        var counter = RayCrossingCounter(p)
        if ring.count > 1 {
            for i in 1..<ring.count {
                // GEOS 3.13 counts each segment forward (JTS: from its end). The
                // location is the same; a NaN or infinite point meets the
                // orientation test, or a vertex, in GEOS's order.
                counter.countSegment(ring[i - 1], ring[i])
                if counter.isOnSegment { return counter.location }
            }
        }
        return counter.location
    }

    public mutating func countSegment(_ p1: Coordinate, _ p2: Coordinate) {
        if p1.x < p.x && p2.x < p.x { return }
        if p.x == p2.x && p.y == p2.y {
            isOnSegment = true
            return
        }
        if p1.y == p.y && p2.y == p.y {
            var minx = p1.x, maxx = p2.x
            if minx > maxx {
                minx = p2.x
                maxx = p1.x
            }
            if p.x >= minx && p.x <= maxx { isOnSegment = true }
            return
        }
        if ((p1.y > p.y) && (p2.y <= p.y)) || ((p2.y > p.y) && (p1.y <= p.y)) {
            var orient = Orientation.index(p1, p2, p)
            if orient == Orientation.collinear {
                isOnSegment = true
                return
            }
            if p2.y < p1.y { orient = -orient }
            if orient == Orientation.left { count += 1 }
        }
    }

    public var location: Int {
        if isOnSegment { return Location.boundary }
        if count % 2 == 1 { return Location.interior }
        return Location.exterior
    }

    public var isPointInPolygon: Bool { location != Location.exterior }
}
