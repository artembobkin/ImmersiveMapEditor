/// geo's Visvalingam-Whyatt simplification: `SimplifyVw` (plain), and `SimplifyVwPreserve`, which
/// also removes the previous point whenever removing a point would make the ring cross itself or
/// another ring. The candidate triangles come out of Rust's binary heap in its exact order.

/// geo's `VScore`: a candidate triangle. The order is reversed on the area, so the max-heap
/// pops the smallest area first. `partial_cmp(...).unwrap()` panics on a NaN area.
struct VScore {
    let left: Int
    let current: Int
    let right: Int
    let area: Double
    /// Used only by the preserving variant.
    var intersector: Bool

    static func cmp(_ a: VScore, _ b: VScore) -> RustOrdering {
        guard let o = rustPartialCmp(b.area, a.area) else {
            preconditionFailure("called `Option::unwrap()` on a `None` value")
        }
        return o
    }
}

typealias VScoreHeap = RustBinaryHeap<VScore, Never>

/// The linked list of retained points, as `(previous, next)` index pairs. An index at or past
/// the end means no neighbour, and `(0, 0)` marks a removed point.
func initialAdjacent(_ count: Int) -> [(Int32, Int32)] {
    var adjacent: [(Int32, Int32)] = []
    adjacent.reserveCapacity(count)
    for i in 0..<count {
        if i == 0 {
            adjacent.append((-1, 1))
        } else {
            adjacent.append((Int32(truncatingIfNeeded: i - 1), Int32(truncatingIfNeeded: i + 1)))
        }
    }
    return adjacent
}

/// The initial triangles of every three consecutive coordinates.
func initialTriangles(_ orig: GeoLineString) -> VScoreHeap {
    let scores = orig.triangles.enumerated().map { i, triangle in
        VScore(left: i, current: i + 1, right: i + 2, area: triangle.unsignedArea, intersector: false)
    }
    return VScoreHeap(scores, cmp: VScore.cmp)
}

/// `visvalingam_indices`: the indices of the coordinates kept by plain VW simplification.
func visvalingamIndices(_ orig: GeoLineString, _ epsilon: Double) -> [Int] {
    // At least three points are needed.
    if orig.coords.count < 3 {
        return Array(orig.coords.indices)
    }
    let max = orig.coords.count
    var adjacent = initialAdjacent(max)
    var pq = initialTriangles(orig)

    // Triangles invalidated by a removal stay in the heap and are skipped here.
    while let smallest = pq.pop() {
        if smallest.area > epsilon {
            // The min-heap guarantees every later triangle is larger too.
            break
        }
        let (left, right) = adjacent[smallest.current]
        // A point of this triangle was removed after the triangle was made.
        if left != Int32(truncatingIfNeeded: smallest.left) || right != Int32(truncatingIfNeeded: smallest.right) {
            continue
        }
        let (ll, _) = adjacent[Int(left)]
        let (_, rr) = adjacent[Int(right)]
        adjacent[Int(left)] = (ll, right)
        adjacent[Int(right)] = (left, rr)
        adjacent[smallest.current] = (0, 0)

        recomputeTriangles(smallest, orig, &pq, ll, left, right, rr, max, epsilon)
    }
    return zip(orig.coords.indices, adjacent).compactMap { $1 != (0, 0) ? $0 : nil }
}

/// `recompute_triangles`: pushes the triangles of the two neighbours of a removed point.
func recomputeTriangles(
    _ smallest: VScore, _ orig: GeoLineString, _ pq: inout VScoreHeap,
    _ ll: Int32, _ left: Int32, _ right: Int32, _ rr: Int32, _ max: Int, _ epsilon: Double
) {
    let choices = [(ll, left, right), (left, right, rr)]
    for (ai, currentPoint, bi) in choices {
        // `ai as usize` turns -1 into a huge index, past the end.
        if asUsizeIndex(ai) >= max || asUsizeIndex(bi) >= max {
            // On one edge.
            continue
        }
        var area = GeoTriangle(
            orig.coords[Int(ai)], orig.coords[Int(currentPoint)], orig.coords[Int(bi)]
        ).unsignedArea

        // Only for VW-Preserve: when removing `smallest.current` made the ring cross itself, the
        // point before it is demoted so it is removed next.
        if smallest.intersector && asUsizeIndex(currentPoint) < smallest.current {
            area = -epsilon
        }

        pq.push(VScore(
            left: Int(ai), current: Int(currentPoint), right: Int(bi), area: area, intersector: false))
    }
}

/// Rust's `i32 as usize`: a negative value wraps to a huge index.
func asUsizeIndex(_ value: Int32) -> Int {
    value < 0 ? Int.max : Int(value)
}

/// `visvalingam`: the coordinates kept by plain VW simplification.
func visvalingam(_ orig: GeoLineString, _ epsilon: Double) -> [GeoCoord] {
    // Epsilon must be greater than zero for any simplification to happen.
    if epsilon <= 0 {
        return orig.coords
    }
    let subset = visvalingamIndices(orig, epsilon)
    // `zip` stops at the shorter of the two, the subset.
    return zip(orig.coords, subset).map { orig.coords[$1] }
}

extension GeoLineString {
    public func simplifyVw(_ epsilon: Double) -> GeoLineString {
        GeoLineString(visvalingam(self, epsilon))
    }

    public func simplifyVwIdx(_ epsilon: Double) -> [Int] {
        visvalingamIndices(self, epsilon)
    }
}

extension GeoMultiLineString {
    public func simplifyVw(_ epsilon: Double) -> GeoMultiLineString {
        GeoMultiLineString(lineStrings.map { $0.simplifyVw(epsilon) })
    }
}

extension GeoPolygon {
    public func simplifyVw(_ epsilon: Double) -> GeoPolygon {
        GeoPolygon(exterior.simplifyVw(epsilon), interiors.map { $0.simplifyVw(epsilon) })
    }
}

extension GeoMultiPolygon {
    public func simplifyVw(_ epsilon: Double) -> GeoMultiPolygon {
        GeoMultiPolygon(polygons.map { $0.simplifyVw(epsilon) })
    }
}
