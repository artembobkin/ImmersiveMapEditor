/// geo's `Winding` for line strings: the winding order of a closed ring, decided by the robust
/// orientation at its lexicographically least vertex, and the helpers to reorder a ring.

public enum GeoWindingOrder: Sendable, Equatable {
    case clockwise
    case counterClockwise

    public var inverse: GeoWindingOrder {
        self == .clockwise ? .counterClockwise : .clockwise
    }
}

/// geo's `lex_cmp`: by `x`, then `y`. Both comparisons are unwrapped, so a NaN in either
/// ordinate panics even when the other decides.
func lexCmp(_ p: GeoCoord, _ q: GeoCoord) -> RustOrdering {
    guard let xo = rustPartialCmp(p.x, q.x) else {
        preconditionFailure("called `Option::unwrap()` on a `None` value")
    }
    guard let yo = rustPartialCmp(p.y, q.y) else {
        preconditionFailure("called `Option::unwrap()` on a `None` value")
    }
    return xo.then(yo)
}

/// geo's `least_index`: the first of the lexicographically least coordinates.
func leastIndex(_ pts: [GeoCoord]) -> Int {
    var best = 0
    for i in 1..<pts.count where lexCmp(pts[best], pts[i]) == .greater {
        best = i
    }
    return best
}

/// geo's `least_and_greatest_index`: the first least and the first greatest coordinate.
func leastAndGreatestIndex(_ pts: [GeoCoord]) -> (Int, Int) {
    precondition(!pts.isEmpty, "assertion `left != right` failed")
    var minIdx = 0
    var maxIdx = 0
    for idx in 1..<pts.count {
        if lexCmp(pts[idx], pts[minIdx]) == .less {
            minIdx = idx
        }
        if lexCmp(pts[idx], pts[maxIdx]) == .greater {
            maxIdx = idx
        }
    }
    return (minIdx, maxIdx)
}

extension GeoLineString {
    /// The winding order, or `nil` for a ring that is open, too short or degenerate.
    public var windingOrder: GeoWindingOrder? {
        let count = coords.count
        if count < 4 || !isClosed {
            return nil
        }
        func increment(_ x: inout Int) {
            x += 1
            if x >= count {
                x = 0
            }
        }
        func decrement(_ x: inout Int) {
            if x == 0 {
                x = count - 1
            } else {
                x -= 1
            }
        }

        let i = leastIndex(coords)

        var next = i
        increment(&next)
        while coords[next] == coords[i] {
            if next == i {
                // Not enough distinct coordinates for an orientation.
                return nil
            }
            increment(&next)
        }

        var prev = i
        decrement(&prev)
        while coords[prev] == coords[i] {
            // The loop above found two distinct coordinates, so this one ends.
            decrement(&prev)
        }

        switch RobustKernel.orient2d(coords[prev], coords[i], coords[next]) {
        case .counterClockwise: return .counterClockwise
        case .clockwise: return .clockwise
        case .collinear: return nil
        }
    }

    public var isCW: Bool { windingOrder == .clockwise }
    public var isCCW: Bool { windingOrder == .counterClockwise }

    /// `points_cw`: the points in clockwise order.
    public var pointsCW: [GeoPoint] {
        windingOrder == .counterClockwise ? points.reversed() : points
    }

    /// `points_ccw`: the points in counterclockwise order.
    public var pointsCCW: [GeoPoint] {
        windingOrder == .clockwise ? points.reversed() : points
    }

    public mutating func makeCWWinding() {
        if windingOrder == .counterClockwise {
            coords.reverse()
        }
    }

    public mutating func makeCCWWinding() {
        if windingOrder == .clockwise {
            coords.reverse()
        }
    }

    public mutating func makeWindingOrder(_ order: GeoWindingOrder) {
        switch order {
        case .clockwise: makeCWWinding()
        case .counterClockwise: makeCCWWinding()
        }
    }

    public func cloneToWindingOrder(_ order: GeoWindingOrder) -> GeoLineString {
        var copy = self
        copy.makeWindingOrder(order)
        return copy
    }
}
