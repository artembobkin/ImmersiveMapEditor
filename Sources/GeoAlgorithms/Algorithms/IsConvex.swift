/// geo's `IsConvex` for line strings: whether a closed ring turns the same way at every vertex,
/// optionally allowing collinear vertices or requiring one orientation.

extension GeoLineString {
    /// The common orientation of a convex closed ring, or `nil` if it is open or not convex.
    public func convexOrientation(allowCollinear: Bool, specificOrientation: GeoOrientation?) -> GeoOrientation? {
        if !isClosed || coords.isEmpty {
            return nil
        }
        return isConvexShaped(Array(coords[1...]), allowCollinear, specificOrientation)
    }

    public var isConvex: Bool {
        convexOrientation(allowCollinear: true, specificOrientation: nil) != nil
    }

    public var isCCWConvex: Bool {
        convexOrientation(allowCollinear: true, specificOrientation: .counterClockwise) != nil
    }

    public var isCWConvex: Bool {
        convexOrientation(allowCollinear: true, specificOrientation: .clockwise) != nil
    }

    public var isStrictlyConvex: Bool {
        convexOrientation(allowCollinear: false, specificOrientation: nil) != nil
    }

    public var isStrictlyCCWConvex: Bool {
        convexOrientation(allowCollinear: false, specificOrientation: .counterClockwise) == .counterClockwise
    }

    public var isStrictlyCWConvex: Bool {
        convexOrientation(allowCollinear: false, specificOrientation: .clockwise) == .clockwise
    }

    public var isCollinear: Bool {
        coords.isEmpty || isConvexShaped(Array(coords[1...]), true, .collinear) != nil
    }
}

/// geo's `is_convex_shaped`, over the coordinates of a ring without its first one.
private func isConvexShaped(
    _ coords: [GeoCoord], _ allowCollinear: Bool, _ specificOrientation: GeoOrientation?
) -> GeoOrientation? {
    let n = coords.count

    func orientationAt(_ i: Int) -> GeoOrientation {
        let coord = coords[i]
        let next = coords[(i + 1) % n]
        let nnext = coords[(i + 2) % n]
        return RobustKernel.orient2d(coord, next, nnext)
    }

    // The first orientation that is not collinear, or the first collinear one if those are not
    // allowed.
    var found: (Int, GeoOrientation)?
    for i in 0..<n {
        let orientation = orientationAt(i)
        if orientation == .collinear && allowCollinear {
            continue
        }
        found = (i, orientation)
        break
    }

    guard let (i, firstNonCollinear) = found else {
        // Empty, or everything collinear and allowed.
        return .collinear
    }
    if firstNonCollinear == .collinear {
        // Only when collinear points are not allowed.
        return nil
    }

    // If a specific orientation is expected, accept only that.
    if let required = specificOrientation, required != firstNonCollinear {
        return nil
    }

    // Every remaining vertex must turn the same way.
    for j in (i + 1)..<Swift.max(n, i + 1) {
        let orientation = orientationAt(j)
        let ok = orientation == .collinear ? allowCollinear : orientation == firstNonCollinear
        if !ok {
            return nil
        }
    }
    return firstNonCollinear
}
