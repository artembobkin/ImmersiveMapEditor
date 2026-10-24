/// geo's `line_intersection`, modelled on JTS's `RobustLineIntersector`: the intersection of two
/// segments as a single point (proper or at an end) or a collinear overlap, with the conditioned
/// homogeneous-coordinate computation and the nearest-endpoint fallback.

public enum GeoLineIntersection: Equatable, Sendable {
    /// The lines meet in one point. `isProper` is true when the point lies in the interior of
    /// both lines (even if rounding snapped it onto an end).
    case singlePoint(intersection: GeoCoord, isProper: Bool)
    /// The lines overlap along a segment.
    case collinear(intersection: GeoLine)

    public var isProper: Bool {
        switch self {
        case .collinear: return false
        case .singlePoint(_, let isProper): return isProper
        }
    }
}

/// The intersection of `p` and `q`, or `nil` when they do not meet.
public func lineIntersection(_ p: GeoLine, _ q: GeoLine) -> GeoLineIntersection? {
    if !p.boundingRect.intersects(q.boundingRect) {
        return nil
    }

    let pq1 = RobustKernel.orient2d(p.start, p.end, q.start)
    let pq2 = RobustKernel.orient2d(p.start, p.end, q.end)
    if (pq1 == .clockwise && pq2 == .clockwise)
        || (pq1 == .counterClockwise && pq2 == .counterClockwise) {
        return nil
    }

    let qp1 = RobustKernel.orient2d(q.start, q.end, p.start)
    let qp2 = RobustKernel.orient2d(q.start, q.end, p.end)
    if (qp1 == .clockwise && qp2 == .clockwise)
        || (qp1 == .counterClockwise && qp2 == .counterClockwise) {
        return nil
    }

    if pq1 == .collinear && pq2 == .collinear && qp1 == .collinear && qp2 == .collinear {
        return collinearIntersection(p, q)
    }

    // There is a single intersection point. If it is an end point, copy that point exactly
    // rather than computing it.
    if pq1 == .collinear || pq2 == .collinear || qp1 == .collinear || qp2 == .collinear {
        let intersection: GeoCoord
        if p.start == q.start || p.start == q.end {
            intersection = p.start
        } else if p.end == q.start || p.end == q.end {
            intersection = p.end
        } else if pq1 == .collinear {
            intersection = q.start
        } else if pq2 == .collinear {
            intersection = q.end
        } else if qp1 == .collinear {
            intersection = p.start
        } else {
            precondition(qp2 == .collinear, "assertion `left == right` failed")
            intersection = p.end
        }
        return .singlePoint(intersection: intersection, isProper: false)
    } else {
        return .singlePoint(intersection: properIntersection(p, q), isProper: true)
    }
}

private func collinearIntersection(_ p: GeoLine, _ q: GeoLine) -> GeoLineIntersection? {
    let pBounds = p.boundingRect
    let qBounds = q.boundingRect
    let a = pBounds.intersects(q.start)
    let b = pBounds.intersects(q.end)
    let c = qBounds.intersects(p.start)
    let d = qBounds.intersects(p.end)
    // The arms in geo's order.
    if a && b {
        return .collinear(intersection: q)
    }
    if c && d {
        return .collinear(intersection: p)
    }
    if a && !b && c && !d && q.start == p.start {
        return .singlePoint(intersection: q.start, isProper: false)
    }
    if a && c {
        return .collinear(intersection: GeoLine(q.start, p.start))
    }
    if a && !b && !c && d && q.start == p.end {
        return .singlePoint(intersection: q.start, isProper: false)
    }
    if a && d {
        return .collinear(intersection: GeoLine(q.start, p.end))
    }
    if !a && b && c && !d && q.end == p.start {
        return .singlePoint(intersection: q.end, isProper: false)
    }
    if b && c {
        return .collinear(intersection: GeoLine(q.end, p.start))
    }
    if !a && b && !c && d && q.end == p.end {
        return .singlePoint(intersection: q.end, isProper: false)
    }
    if b && d {
        return .collinear(intersection: GeoLine(q.end, p.end))
    }
    return nil
}

/// The end point of either segment that is closest to the other segment, a surrogate for the
/// intersection in ill-conditioned cases.
private func nearestEndpoint(_ p: GeoLine, _ q: GeoLine) -> GeoCoord {
    var nearestPt = p.start
    var minDist = pointLineEuclideanDistance(p.start, q)

    var dist = pointLineEuclideanDistance(p.end, q)
    if dist < minDist {
        minDist = dist
        nearestPt = p.end
    }
    dist = pointLineEuclideanDistance(q.start, p)
    if dist < minDist {
        minDist = dist
        nearestPt = q.start
    }
    dist = pointLineEuclideanDistance(q.end, p)
    if dist < minDist {
        nearestPt = q.end
    }
    return nearestPt
}

private func rawLineIntersection(_ p: GeoLine, _ q: GeoLine) -> GeoCoord? {
    let pMinX = rustMin(p.start.x, p.end.x)
    let pMinY = rustMin(p.start.y, p.end.y)
    let pMaxX = rustMax(p.start.x, p.end.x)
    let pMaxY = rustMax(p.start.y, p.end.y)

    let qMinX = rustMin(q.start.x, q.end.x)
    let qMinY = rustMin(q.start.y, q.end.y)
    let qMaxX = rustMax(q.start.x, q.end.x)
    let qMaxY = rustMax(q.start.y, q.end.y)

    let intMinX = rustMax(pMinX, qMinX)
    let intMaxX = rustMin(pMaxX, qMaxX)
    let intMinY = rustMax(pMinY, qMinY)
    let intMaxY = rustMin(pMaxY, qMaxY)

    let two = 1.0 + 1.0
    let midX = (intMinX + intMaxX) / two
    let midY = (intMinY + intMaxY) / two

    // Condition the ordinates by subtracting the midpoint.
    let p1x = p.start.x - midX
    let p1y = p.start.y - midY
    let p2x = p.end.x - midX
    let p2y = p.end.y - midY
    let q1x = q.start.x - midX
    let q1y = q.start.y - midY
    let q2x = q.end.x - midX
    let q2y = q.end.y - midY

    // The unrolled homogeneous coordinates equation.
    let px = p1y - p2y
    let py = p2x - p1x
    let pw = p1x * p2y - p2x * p1y

    let qx = q1y - q2y
    let qy = q2x - q1x
    let qw = q1x * q2y - q2x * q1y

    let xw = py * qw - qy * pw
    let yw = qx * pw - px * qw
    let w = px * qy - qx * py

    let xInt = xw / w
    let yInt = yw / w

    // Parallel lines.
    if (xInt.isNaN || xInt.isInfinite) || (yInt.isNaN || yInt.isInfinite) {
        return nil
    }
    return GeoCoord(x: xInt + midX, y: yInt + midY)
}

private func properIntersection(_ p: GeoLine, _ q: GeoLine) -> GeoCoord {
    var intPt = rawLineIntersection(p, q) ?? nearestEndpoint(p, q)
    // JTS's `Envelope::contains(coord)` here is in fact an intersection test, boundary included.
    if !(p.boundingRect.intersects(intPt) && q.boundingRect.intersects(intPt)) {
        intPt = nearestEndpoint(p, q)
    }
    return intPt
}
