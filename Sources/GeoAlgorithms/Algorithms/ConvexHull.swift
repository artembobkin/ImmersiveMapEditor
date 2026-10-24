/// geo's `ConvexHull` by quick hull (`convex_hull/qhull.rs`), with its in-place partitioning of
/// the points, so the hull starts and runs in the same order as geo's: counterclockwise, closed,
/// collinear points left out.

/// geo's `partition_slice`: moves the elements satisfying `predicate` to the front, returning
/// how many there are.
private func partitionSlice(_ data: inout [GeoCoord], _ range: Range<Int>, _ predicate: (GeoCoord) -> Bool) -> Int {
    let len = range.count
    if len == 0 {
        return 0
    }
    let base = range.lowerBound
    var l = 0
    var r = len - 1
    while true {
        while l < len && predicate(data[base + l]) {
            l += 1
        }
        while r > 0 && !predicate(data[base + r]) {
            r -= 1
        }
        if l >= r {
            return l
        }
        data.swapAt(base + l, base + r)
    }
}

/// Whether `pC` lies left of `pA -> pB`, exactly.
private func isCCW(_ pA: GeoCoord, _ pB: GeoCoord, _ pC: GeoCoord) -> Bool {
    RobustKernel.orient2d(pA, pB, pC) == .counterClockwise
}

/// geo's `trivial_hull`: the hull of at most three points, counterclockwise, with repeated
/// points removed unless `includeOnHull`.
func trivialHull(_ points: [GeoCoord], includeOnHull: Bool) -> GeoLineString {
    precondition(points.count < 4, "assertion failed: points.len() < 4")
    var ls = points
    if !includeOnHull {
        rustSortUnstable(&ls) { lexCmp($0, $1) }
        if ls.count == 3 && RobustKernel.orient2d(ls[0], ls[1], ls[2]) == .collinear {
            ls.remove(at: 1)
        }
    }
    // A line string with a single point is invalid.
    if ls.count == 1 {
        ls.append(ls[0])
    }
    var result = GeoLineString(ls)
    result.close()
    // Keep the counterclockwise invariant.
    result.makeCCWWinding()
    return result
}

/// geo's `quick_hull`. The slice is reordered in place, as in geo.
public func quickHull(_ points: inout [GeoCoord]) -> GeoLineString {
    // A hull needs at least four points.
    if points.count < 4 {
        return trivialHull(points, includeOnHull: false)
    }
    var hull: [GeoCoord] = []

    // `swap_remove_to_first` swaps an element to the head and then drops the head from the
    // slice, so the working slice is `points[start...]`.
    var start = 0
    let (minIdx, maxIdxFound) = leastAndGreatestIndex(points)
    var maxIdx = maxIdxFound
    points.swapAt(start, start + minIdx)
    let min = points[start]
    start += 1
    // The maximum was at index 0 and got swapped.
    if maxIdx == 0 {
        maxIdx = minIdx
    }
    // `saturating_sub`: if the maximum equals the minimum, any point may serve.
    maxIdx = Swift.max(maxIdx - 1, 0)
    points.swapAt(start, start + maxIdx)
    let max = points[start]
    start += 1

    do {
        let n = partitionSlice(&points, start..<points.count) { isCCW(max, min, $0) }
        hullSet(max, min, &points, start..<(start + n), &hull)
    }
    hull.append(max)
    let n = partitionSlice(&points, start..<points.count) { isCCW(min, max, $0) }
    hullSet(min, max, &points, start..<(start + n), &hull)
    hull.append(min)
    // Close the polygon.
    var result = GeoLineString(hull)
    result.close()
    return result
}

/// `hull_set`: the hull points beyond `pA -> pB` among `points[range]`, appended to `hull`.
private func hullSet(_ pA: GeoCoord, _ pB: GeoCoord, _ points: inout [GeoCoord], _ range: Range<Int>, _ hull: inout [GeoCoord]) {
    if range.isEmpty {
        return
    }
    if range.count == 1 {
        hull.append(points[range.lowerBound])
        return
    }

    // A vector orthogonal to `pB - pA`, whose dot product finds the farthest point.
    let pOrth = GeoCoord(x: pA.y - pB.y, y: pB.x - pA.x)

    // `max_by` keeps the last of equal maxima and unwraps `partial_cmp`.
    var furthestIdx = 0
    var furthestValue = 0.0
    for (i, idx) in range.enumerated() {
        let pt = points[idx]
        let pDiff = GeoCoord(x: pt.x - pA.x, y: pt.y - pA.y)
        let value = pOrth.x * pDiff.x + pOrth.y * pDiff.y
        if i == 0 {
            furthestIdx = 0
            furthestValue = value
            continue
        }
        guard let o = rustPartialCmp(furthestValue, value) else {
            preconditionFailure("called `Option::unwrap()` on a `None` value")
        }
        if o != .greater {
            furthestIdx = i
            furthestValue = value
        }
    }

    // Move the furthest point from the set into the hull.
    var start = range.lowerBound
    points.swapAt(start, start + furthestIdx)
    let furthestPoint = points[start]
    start += 1
    let end = range.upperBound
    // The points beyond `furthest -> pB`.
    do {
        let n = partitionSlice(&points, start..<end) { isCCW(furthestPoint, pB, $0) }
        hullSet(furthestPoint, pB, &points, start..<(start + n), &hull)
    }
    hull.append(furthestPoint)
    // The points beyond `pA -> furthest`.
    let n = partitionSlice(&points, start..<end) { isCCW(pA, furthestPoint, $0) }
    hullSet(pA, furthestPoint, &points, start..<(start + n), &hull)
}

extension GeoMultiPolygon {
    /// The convex hull of the exterior coordinates of all polygons.
    public func convexHull() -> GeoPolygon {
        var exterior = exteriorCoords
        return GeoPolygon(quickHull(&exterior), [])
    }
}

extension GeoPolygon {
    public func convexHull() -> GeoPolygon {
        var exterior = self.exterior.coords
        return GeoPolygon(quickHull(&exterior), [])
    }
}

extension GeoLineString {
    public func convexHull() -> GeoPolygon {
        var exterior = coords
        return GeoPolygon(quickHull(&exterior), [])
    }
}

extension GeoMultiPoint {
    public func convexHull() -> GeoPolygon {
        var exterior = points.map(\.coord)
        return GeoPolygon(quickHull(&exterior), [])
    }
}

extension GeoMultiLineString {
    public func convexHull() -> GeoPolygon {
        var exterior = lineStrings.flatMap(\.coords)
        return GeoPolygon(quickHull(&exterior), [])
    }
}
