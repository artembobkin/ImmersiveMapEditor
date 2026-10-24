/// geo's `ClosestPoint` and its `Closest` result: the point of a geometry nearest to a given
/// point, telling an exact hit (`intersection`) from a nearest point (`singlePoint`).

public enum GeoClosest: Equatable, Sendable {
    /// The point lies on the geometry.
    case intersection(GeoPoint)
    /// The geometry's nearest point to the query.
    case singlePoint(GeoPoint)
    /// No single nearest point (an empty geometry or a zero length line).
    case indeterminate

    /// `Closest::best_of_two`: the better of `self` and `other` for the query `p`.
    public func bestOfTwo(_ other: GeoClosest, _ p: GeoPoint) -> GeoClosest {
        let left: GeoPoint
        switch self {
        case .indeterminate: return other
        case .intersection: return self
        case .singlePoint(let l): left = l
        }
        let right: GeoPoint
        switch other {
        case .indeterminate: return self
        case .intersection: return other
        case .singlePoint(let r): right = r
        }
        if left.euclideanDistance(p) <= right.euclideanDistance(p) {
            return self
        } else {
            return other
        }
    }
}

/// `closest_of`: the best of the elements' closest points, stopping at the first hit.
private func closestOf<S: Sequence>(_ elements: S, _ p: GeoPoint, _ closest: (S.Element, GeoPoint) -> GeoClosest) -> GeoClosest {
    var best = GeoClosest.indeterminate
    for element in elements {
        let got = closest(element, p)
        best = got.bestOfTwo(best, p)
        if case .intersection = best {
            // Nothing can be closer than an intersection.
            return best
        }
    }
    return best
}

extension GeoPoint {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        self == p ? .intersection(self) : .singlePoint(self)
    }
}

extension GeoCoord {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        GeoPoint(self).closestPoint(p)
    }
}

extension GeoLine {
    /// The foot of the perpendicular from `p`, clamped to the line.
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        let lineLength = euclideanLength
        if lineLength == 0 {
            // For a zero length line the whole line is the closest point.
            return .indeterminate
        }
        // The line is `start + t * (end - start)`.
        let directionVector = GeoPoint(end - start)
        let toP = GeoPoint(p.coord - start)

        let t = toP.dot(directionVector) / directionVector.dot(directionVector)

        // The closest point is outside the line.
        if t < 0 {
            return .singlePoint(GeoPoint(start))
        } else if t > 1 {
            return .singlePoint(GeoPoint(end))
        }

        let x = directionVector.x
        let y = directionVector.y
        let c = GeoPoint(start + GeoCoord(x: t * x, y: t * y))

        return intersects(p) ? .intersection(c) : .singlePoint(c)
    }
}

extension GeoLineString {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        closestOf(lines, p) { $0.closestPoint($1) }
    }
}

extension GeoPolygon {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        if intersects(p) {
            return .intersection(p)
        }
        return closestOf(interiors + [exterior], p) { $0.closestPoint($1) }
    }
}

extension GeoMultiPolygon {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        closestOf(polygons, p) { $0.closestPoint($1) }
    }
}

extension GeoMultiLineString {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        closestOf(lineStrings, p) { $0.closestPoint($1) }
    }
}

extension GeoMultiPoint {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        closestOf(points, p) { $0.closestPoint($1) }
    }
}

extension GeoRect {
    public func closestPoint(_ p: GeoPoint) -> GeoClosest {
        if intersects(p) {
            return .intersection(p)
        }
        return closestOf(toLines(), p) { $0.closestPoint($1) }
    }
}
