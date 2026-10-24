/// geo's `SimplifyVwPreserve`: Visvalingam-Whyatt simplification that keeps rings from crossing
/// themselves or each other. geo keeps the current segments of all rings in an rstar R-tree, used
/// only as a multiset (insert, remove an equal segment, and "does any segment in this
/// box cross the new one"), whose answers do not depend on the tree's layout, so a flat array of
/// segments with the same envelope test gives the same results.

/// The segments of all rings, standing in for `RTree<CachedEnvelope<Line>>`.
struct SegmentMultiset {
    private(set) var lines: [GeoLine]

    init(_ lines: [GeoLine]) {
        self.lines = lines
    }

    /// `RTree::remove`: removes one segment equal to `line`, returning whether there was one.
    mutating func remove(_ line: GeoLine) -> Bool {
        guard let i = lines.firstIndex(of: line) else { return false }
        lines.remove(at: i)
        return true
    }

    mutating func insert(_ line: GeoLine) {
        lines.append(line)
    }

    /// Whether any segment whose envelope intersects `envelope` (rstar's `AABB::intersects`,
    /// boundaries included) satisfies `predicate`.
    func anyIntersecting(_ envelope: GeoRect, _ predicate: (GeoLine) -> Bool) -> Bool {
        lines.contains { line in
            // `AABB::from_corners` with rstar's `min_inline` and `max_inline`.
            let lower = GeoCoord(x: minInline(line.start.x, line.end.x), y: minInline(line.start.y, line.end.y))
            let upper = GeoCoord(x: maxInline(line.start.x, line.end.x), y: maxInline(line.start.y, line.end.y))
            let intersects = lower.x <= envelope.max.x && lower.y <= envelope.max.y
                && upper.x >= envelope.min.x && upper.y >= envelope.min.y
            return intersects && predicate(line)
        }
    }
}

/// rstar's `min_inline`.
private func minInline(_ a: Double, _ b: Double) -> Double { a < b ? a : b }

/// rstar's `max_inline`.
private func maxInline(_ a: Double, _ b: Double) -> Double { a > b ? a : b }

/// `vwp_wrapper`: simplifies the exterior and then each interior, sharing one segment set so
/// crossings between rings are seen.
func vwpWrapper(
    _ exterior: GeoLineString, _ interiors: [GeoLineString]?, _ epsilon: Double,
    initialMin: Int, minPoints: Int
) -> [[GeoCoord]] {
    var rings: [[GeoCoord]] = []
    var tree = SegmentMultiset(exterior.lines + (interiors ?? []).flatMap(\.lines))
    rings.append(visvalingamPreserve(exterior, epsilon, &tree, initialMin: initialMin, minPoints: minPoints))
    if let interiors {
        for ring in interiors {
            rings.append(visvalingamPreserve(ring, epsilon, &tree, initialMin: initialMin, minPoints: minPoints))
        }
    }
    return rings
}

/// `visvalingam_preserve`. `initialMin`: stop when this few points are left. `minPoints`: stop
/// when a removal would cross and only this few points are left, since removing the previous
/// point too could leave an invalid geometry.
private func visvalingamPreserve(
    _ orig: GeoLineString, _ epsilon: Double, _ tree: inout SegmentMultiset,
    initialMin: Int, minPoints: Int
) -> [GeoCoord] {
    if orig.coords.count < 3 || epsilon <= 0 {
        return orig.coords
    }
    let max = orig.coords.count
    var counter = orig.coords.count
    var adjacent = initialAdjacent(max)
    var pq = initialTriangles(orig)

    while var smallest = pq.pop() {
        if smallest.area > epsilon {
            break
        }
        if counter <= initialMin {
            // No more points can be removed.
            break
        }
        let (left, right) = adjacent[smallest.current]
        // A point of this triangle was removed after the triangle was made.
        if left != Int32(truncatingIfNeeded: smallest.left) || right != Int32(truncatingIfNeeded: smallest.right) {
            continue
        }
        // If removing this point makes a crossing, the previous point is removed too, unless
        // the geometry is within one point of its minimum.
        smallest.intersector = treeIntersect(tree, smallest, orig.coords)
        if smallest.intersector && counter <= minPoints {
            break
        }
        let (ll, _) = adjacent[Int(left)]
        let (_, rr) = adjacent[Int(right)]
        adjacent[Int(left)] = (ll, right)
        adjacent[Int(right)] = (left, rr)
        adjacent[smallest.current] = (0, 0)
        counter -= 1

        // Replace the two stale segments by the one that joins their ends.
        let leftPoint = orig.coords[Int(left)]
        let middlePoint = orig.coords[smallest.current]
        let rightPoint = orig.coords[Int(right)]
        precondition(tree.remove(GeoLine(leftPoint, middlePoint)), "assertion failed: tree.remove(&line_1).is_some()")
        precondition(tree.remove(GeoLine(middlePoint, rightPoint)), "assertion failed: tree.remove(&line_2).is_some()")
        tree.insert(GeoLine(leftPoint, rightPoint))

        recomputeTriangles(smallest, orig, &pq, ll, left, right, rr, max, epsilon)
    }
    return zip(orig.coords, adjacent).compactMap { $1 != (0, 0) ? $0 : nil }
}

/// `tree_intersect`: whether the segment that would replace the triangle's two sides crosses any
/// segment that shares no end point with it.
private func treeIntersect(_ tree: SegmentMultiset, _ triangle: VScore, _ orig: [GeoCoord]) -> Bool {
    let newSegmentStart = orig[triangle.left]
    let newSegmentEnd = orig[triangle.right]
    let newSegment = GeoLine(newSegmentStart, newSegmentEnd)
    let boundingRect = GeoTriangle(orig[triangle.left], orig[triangle.current], orig[triangle.right]).boundingRect
    return tree.anyIntersecting(boundingRect) { candidate in
        candidate.start != newSegmentStart
            && candidate.start != newSegmentEnd
            && candidate.end != newSegmentStart
            && candidate.end != newSegmentEnd
            && newSegment.intersects(candidate)
    }
}

extension GeoLineString {
    public func simplifyVwPreserve(_ epsilon: Double) -> GeoLineString {
        var simplified = vwpWrapper(self, nil, epsilon, initialMin: 2, minPoints: 4)
        return GeoLineString(simplified.removeLast())
    }
}

extension GeoMultiLineString {
    public func simplifyVwPreserve(_ epsilon: Double) -> GeoMultiLineString {
        GeoMultiLineString(lineStrings.map { $0.simplifyVwPreserve(epsilon) })
    }
}

extension GeoPolygon {
    public func simplifyVwPreserve(_ epsilon: Double) -> GeoPolygon {
        // `min_points` was formerly 6, too conservative for small polygons.
        var simplified = vwpWrapper(exterior, interiors, epsilon, initialMin: 4, minPoints: 5)
        let exterior = GeoLineString(simplified.removeFirst())
        return GeoPolygon(exterior, simplified.map(GeoLineString.init))
    }
}

extension GeoMultiPolygon {
    public func simplifyVwPreserve(_ epsilon: Double) -> GeoMultiPolygon {
        GeoMultiPolygon(polygons.map { $0.simplifyVwPreserve(epsilon) })
    }
}
