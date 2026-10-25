/// The convex hull of a geometry's points: JTS's `ConvexHull`, a Graham scan
/// after dropping the points inside an inner octagon of extreme points.
///
/// The unique points keep the order they first occur in. JTS gathers them in
/// a `HashSet`, so its order of the two points of a two-point hull is Java's
/// hashing; GEOS keeps the input's order, and so does this port.
public struct ConvexHull {
    static let tuningReduceSize = 50

    let factory: GeometryFactory
    let inputPts: [Coordinate]

    public init(_ geometry: Geometry) {
        self.init(geometry.getCoordinates(), geometry.factory)
    }

    public init(_ pts: [Coordinate], _ factory: GeometryFactory) {
        inputPts = pts
        self.factory = factory
    }

    public func getConvexHull() -> Geometry {
        if let few = createFewPointsResult() { return few }
        let reducedPts = inputPts.count > ConvexHull.tuningReduceSize ? reduce(inputPts) : ConvexHull.extractUnique(inputPts)!
        let sortedPts = ConvexHull.preSort(reducedPts)
        let hull = ConvexHull.grahamScan(sortedPts)
        return lineOrPolygon(hull)
    }

    func createFewPointsResult() -> Geometry? {
        guard let unique = ConvexHull.extractUnique(inputPts, 2) else { return nil }
        if unique.isEmpty { return factory.createGeometryCollection() }
        if unique.count == 1 { return factory.createPoint(unique[0]) }
        return factory.createLineString(unique)
    }

    /// The distinct points in the order they first occur, nil when there
    /// are more than `maxPts` (unless it is negative). Distinct as GEOS's
    /// `std::set` of coordinates finds them (`CxxTree`): the same as a hash
    /// set for finite points, while a point with a NaN ordinate is
    /// equivalent to some point already there and left out.
    static func extractUnique(_ pts: [Coordinate], _ maxPts: Int = -1) -> [Coordinate]? {
        var seen = CxxTree<Coordinate, Void> { $0 < $1 }
        var out: [Coordinate] = []
        for p in pts where seen.insert(p, ()).1 {
            out.append(p)
            if maxPts >= 0 && out.count > maxPts { return nil }
        }
        return out
    }

    /// GEOS's reduction: the points of the inner octagon and those outside
    /// it, in GEOS's `std::set` (libc++'s tree): each once and in coordinate
    /// order (JTS: a hash set). The order does not change the hull of
    /// distinct finite points; a point with a NaN ordinate is equivalent to
    /// one already there and left out, as in GEOS.
    func reduce(_ inputPts: [Coordinate]) -> [Coordinate] {
        guard let innerPolyPts = ConvexHull.computeInnerOctolateralRing(inputPts) else { return inputPts }
        var reducedSet = CxxTree<Coordinate, Void> { $0 < $1 }
        for p in innerPolyPts { reducedSet.insert(p, ()) }
        for p in inputPts where !PointLocation.isInRing(p, innerPolyPts) { reducedSet.insert(p, ()) }
        let reduced = reducedSet.inOrder().map { reducedSet.nodes[$0].key }
        if reduced.count < 3 { return ConvexHull.padArray3(reduced) }
        return reduced
    }

    static func padArray3(_ pts: [Coordinate]) -> [Coordinate] {
        (0..<3).map { $0 < pts.count ? pts[$0] : pts[0] }
    }

    /// The lowest point (leftmost of the lowest) first, the rest by angle
    /// around it. As GEOS sorts: the whole array, the lowest point with
    /// it, by libc++'s `std::sort` (JTS: a stable sort of the others). For
    /// distinct finite points the order is total and the result the same;
    /// with an infinite point the comparisons made decide whether the
    /// orientation test meets it as its tested point, where GEOS throws.
    static func preSort(_ input: [Coordinate]) -> [Coordinate] {
        var pts = input
        for i in 1..<pts.count where (pts[i].y < pts[0].y) || ((pts[i].y == pts[0].y) && (pts[i].x < pts[0].x)) {
            pts.swapAt(0, i)
        }
        let origin = pts[0]
        CxxAlgorithms.sort(&pts) { polarCompare(origin, $0, $1) == -1 }
        return pts
    }

    static func polarCompare(_ o: Coordinate, _ p: Coordinate, _ q: Coordinate) -> Int {
        let orient = Orientation.index(o, p, q)
        if orient == Orientation.counterclockwise { return 1 }
        if orient == Orientation.clockwise { return -1 }
        if p.y > q.y { return 1 }
        if p.y < q.y { return -1 }
        if p.x > q.x { return 1 }
        if p.x < q.x { return -1 }
        return 0
    }

    static func grahamScan(_ c: [Coordinate]) -> [Coordinate] {
        var ps: [Coordinate] = [c[0], c[1], c[2]]
        for i in 3..<c.count {
            let cp = c[i]
            var p = ps.removeLast()
            while !ps.isEmpty && Orientation.index(ps.last!, p, cp) > 0 { p = ps.removeLast() }
            ps.append(p)
            ps.append(cp)
        }
        ps.append(c[0])
        return ps
    }

    static func isBetween(_ c1: Coordinate, _ c2: Coordinate, _ c3: Coordinate) -> Bool {
        if Orientation.index(c1, c2, c3) != 0 { return false }
        if c1.x != c3.x {
            if c1.x <= c2.x && c2.x <= c3.x { return true }
            if c3.x <= c2.x && c2.x <= c1.x { return true }
        }
        if c1.y != c3.y {
            if c1.y <= c2.y && c2.y <= c3.y { return true }
            if c3.y <= c2.y && c2.y <= c1.y { return true }
        }
        return false
    }

    static func computeInnerOctolateralRing(_ inputPts: [Coordinate]) -> [Coordinate]? {
        let octPts = computeInnerOctolateralPts(inputPts)
        // CoordinateList.add(pts, false): no repeated points in a row.
        var list: [Coordinate] = []
        for p in octPts where list.last != p { list.append(p) }
        if list.count < 3 { return nil }
        if list.first != list.last { list.append(list[0]) }
        return list
    }

    static func computeInnerOctolateralPts(_ inputPts: [Coordinate]) -> [Coordinate] {
        var pts = [Coordinate](repeating: inputPts[0], count: 8)
        for i in 1..<inputPts.count {
            let p = inputPts[i]
            if p.x < pts[0].x { pts[0] = p }
            if p.x - p.y < pts[1].x - pts[1].y { pts[1] = p }
            if p.y > pts[2].y { pts[2] = p }
            if p.x + p.y > pts[3].x + pts[3].y { pts[3] = p }
            if p.x > pts[4].x { pts[4] = p }
            if p.x - p.y > pts[5].x - pts[5].y { pts[5] = p }
            if p.y < pts[6].y { pts[6] = p }
            if p.x + p.y < pts[7].x + pts[7].y { pts[7] = p }
        }
        return pts
    }

    func lineOrPolygon(_ input: [Coordinate]) -> Geometry {
        let coordinates = ConvexHull.cleanRing(input)
        if coordinates.count == 3 { return factory.createLineString([coordinates[0], coordinates[1]]) }
        // Only non-finite points leave the hull unclosed: GEOS's ring then
        // throws, which this non-throwing function reports as the orientation
        // test does (`NonFinite`); its result is discarded.
        guard let ring = try? factory.createLinearRingChecked(coordinates) else {
            NonFinite.raise()
            return factory.createPolygon()
        }
        return factory.createPolygon(ring)
    }

    static func cleanRing(_ original: [Coordinate]) -> [Coordinate] {
        var cleaned: [Coordinate] = []
        var previousDistinct: Coordinate?
        for i in 0...(original.count - 2) {
            let current = original[i], next = original[i + 1]
            if current == next { continue }
            if let prev = previousDistinct, isBetween(prev, current, next) { continue }
            cleaned.append(current)
            previousDistinct = current
        }
        cleaned.append(original[original.count - 1])
        return cleaned
    }
}
