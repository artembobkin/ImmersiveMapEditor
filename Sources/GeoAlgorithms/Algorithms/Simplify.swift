/// geo's `Simplify` and `SimplifyIdx`: Ramer-Douglas-Peucker simplification of line strings and
/// polygon rings, with geo's minimum point counts (2 for a line string, 4 for a ring) below which
/// a culling step is undone.

private struct RdpIndex {
    let index: Int
    let coord: GeoCoord
}

private let lineStringInitialMin = 2
private let polygonInitialMin = 4

/// `rdp`: the simplified coordinates.
func rdp(_ coords: [GeoCoord], _ epsilon: Double, initialMin: Int) -> [GeoCoord] {
    // Epsilon must be greater than zero for any simplification to happen.
    if epsilon <= 0 {
        return coords
    }
    let rdpIndices = coords.enumerated().map { RdpIndex(index: $0.offset, coord: $0.element) }
    var simplifiedLen = rdpIndices.count
    return computeRdp(rdpIndices[...], &simplifiedLen, epsilon, initialMin: initialMin).map(\.coord)
}

/// `calculate_rdp_indices`: the indices of the retained coordinates.
private func calculateRdpIndices(_ rdpIndices: [RdpIndex], _ epsilon: Double, initialMin: Int) -> [Int] {
    if epsilon <= 0 {
        return rdpIndices.map(\.index)
    }
    var simplifiedLen = rdpIndices.count
    return computeRdp(rdpIndices[...], &simplifiedLen, epsilon, initialMin: initialMin).map(\.index)
}

/// `compute_rdp`: the recursion over the farthest point from the first-last line.
private func computeRdp(
    _ rdpIndices: ArraySlice<RdpIndex>,
    _ simplifiedLen: inout Int,
    _ epsilon: Double,
    initialMin: Int
) -> [RdpIndex] {
    if rdpIndices.isEmpty {
        return []
    }
    let base = rdpIndices.startIndex
    let count = rdpIndices.count
    let first = rdpIndices[base]
    let last = rdpIndices[base + count - 1]
    if count == 2 {
        return [first, last]
    }

    let firstLastLine = GeoLine(first.coord, last.coord)

    // The farthest point from the line, ties going to the later point.
    var farthestIndex = 0
    var farthestDistance = 0.0
    for index in stride(from: 1, to: count - 1, by: 1) {
        let distance = firstLastLine.euclideanDistance(rdpIndices[base + index].coord)
        if distance >= farthestDistance {
            farthestIndex = index
            farthestDistance = distance
        }
    }

    if farthestDistance > epsilon {
        // Simplify the two halves split at the farthest point.
        var intermediate = computeRdp(
            rdpIndices[base...(base + farthestIndex)], &simplifiedLen, epsilon, initialMin: initialMin)
        // The farthest point is not included twice.
        intermediate.removeLast()
        intermediate.append(contentsOf: computeRdp(
            rdpIndices[(base + farthestIndex)...], &simplifiedLen, epsilon, initialMin: initialMin))
        return intermediate
    }

    // Keep only the first and last points, unless that leaves fewer than the minimum.
    // Rust computes these in wrapping `usize` arithmetic (a release build): for a single point
    // `count - 2` wraps, and the new length comes out one more than before.
    let numberCulled = count &- 2
    let newLength = simplifiedLen &- numberCulled
    if newLength < initialMin {
        return Array(rdpIndices)
    }
    simplifiedLen = newLength
    return [first, last]
}

extension GeoLineString {
    public func simplify(_ epsilon: Double) -> GeoLineString {
        GeoLineString(rdp(coords, epsilon, initialMin: lineStringInitialMin))
    }

    public func simplifyIdx(_ epsilon: Double) -> [Int] {
        calculateRdpIndices(
            coords.enumerated().map { RdpIndex(index: $0.offset, coord: $0.element) },
            epsilon, initialMin: lineStringInitialMin)
    }
}

extension GeoMultiLineString {
    public func simplify(_ epsilon: Double) -> GeoMultiLineString {
        GeoMultiLineString(lineStrings.map { $0.simplify(epsilon) })
    }
}

extension GeoPolygon {
    public func simplify(_ epsilon: Double) -> GeoPolygon {
        GeoPolygon(
            GeoLineString(rdp(exterior.coords, epsilon, initialMin: polygonInitialMin)),
            interiors.map { GeoLineString(rdp($0.coords, epsilon, initialMin: polygonInitialMin)) })
    }
}

extension GeoMultiPolygon {
    public func simplify(_ epsilon: Double) -> GeoMultiPolygon {
        GeoMultiPolygon(polygons.map { $0.simplify(epsilon) })
    }
}
