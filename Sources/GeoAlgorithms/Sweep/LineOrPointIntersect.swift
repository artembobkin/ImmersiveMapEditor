/// The intersection of two sweep segments, as geo's `LineOrPoint::intersect_line` and
/// `intersect_line_ordered`, including the one-ulp nudges and the heuristic that keeps the order of
/// two segments when rounding of their intersection point would change it.

extension LineOrPoint {
    /// Intersects the line `other` with `self`: a point, an overlapping segment, or `nil`.
    func intersectLine(_ other: LineOrPoint) throws(GeoPanic) -> LineOrPoint? {
        let line = other.geoLine
        switch self {
        case .point(let p):
            return line.intersects(p.coord) ? self : nil
        case .line(let left, let right):
            guard let l = lineIntersection(self.geoLine, line) else { return nil }
            switch l {
            case .singlePoint(let intersection, let isProper):
                var pt = intersection
                if isProper && pt == left.coord {
                    if left.x == right.x {
                        pt.y = pt.y.nextAfter(.infinity)
                    } else {
                        pt.x = pt.x.nextAfter(.infinity)
                    }
                }
                return .point(SweepPoint(pt))
            case .collinear(let intersection):
                return try LineOrPoint(intersection)
            }
        }
    }

    /// `intersect_line_ordered`: the intersection, nudged so it is not before `self`'s left end,
    /// and replaced by a trivial point when it would invert the order of the two segments.
    func intersectLineOrdered(_ other: LineOrPoint) throws(GeoPanic) -> LineOrPoint? {
        let ord = partialCmp(other)
        let result = try intersectLine(other)
        guard case .point(let p)? = result else {
            return result
        }
        var x = p.x
        let y = p.y
        let c = left
        if x == c.x && y < c.y {
            x = x.nextAfter(.infinity)
        }
        let point = SweepPoint(x: x, y: y)

        if let ord {
            let l1 = try LineOrPoint(left, point)
            let l2 = try LineOrPoint(other.left, point)
            guard let cmp = l1.partialCmp(l2) else { throw GeoPanic.unwrapNone }
            if l1.isLine && l2.isLine && cmp.then(ord) != ord {
                // A complicated intersection that changes the ordering: approximate it with a
                // trivial intersection point that preserves the topology.
                return left.gt(other.left) ? .point(left) : .point(other.left)
            }
        }
        return .point(point)
    }
}
