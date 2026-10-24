/// geo's `LineOrPoint`: a sweep segment with ordered end points, or a single point, with the
/// partial order of segments along the sweep line that the active set is sorted by.

enum LineOrPoint: CustomStringConvertible {
    case point(SweepPoint)
    case line(left: SweepPoint, right: SweepPoint)

    var description: String {
        switch self {
        case .point(let p): return "Pt(\(p.x), \(p.y))"
        case .line(let l, let r): return "LPt((\(l.x), \(l.y)), (\(r.x), \(r.y)))"
        }
    }

    /// `From<(SweepPoint, SweepPoint)>`: orders the ends, a point if they are equal. Panics
    /// (throws) on NaN through `SweepPoint::cmp`.
    init(_ start: SweepPoint, _ end: SweepPoint) throws(GeoPanic) {
        switch try start.cmp(end) {
        case .less: self = .line(left: start, right: end)
        case .equal: self = .point(start)
        case .greater: self = .line(left: end, right: start)
        }
    }

    /// `From<Line>`.
    init(_ line: GeoLine) throws(GeoPanic) {
        try self.init(SweepPoint(line.start), SweepPoint(line.end))
    }

    /// `LineOrPoint::new`: the ends are taken as given, a point if they are equal.
    static func new(_ left: SweepPoint, _ right: SweepPoint) -> LineOrPoint {
        left == right ? .point(left) : .line(left: left, right: right)
    }

    var isLine: Bool {
        if case .line = self { return true }
        return false
    }

    /// `LineOrPoint::line`: a point becomes a degenerate line.
    var geoLine: GeoLine {
        switch self {
        case .point(let p): return GeoLine(p.coord, p.coord)
        case .line(let l, let r): return GeoLine(l.coord, r.coord)
        }
    }

    var left: SweepPoint {
        switch self {
        case .point(let p): return p
        case .line(let l, _): return l
        }
    }

    var right: SweepPoint {
        switch self {
        case .point(let p): return p
        case .line(_, let r): return r
        }
    }

    var endPoints: (SweepPoint, SweepPoint) {
        switch self {
        case .point(let p): return (p, p)
        case .line(let l, let r): return (l, r)
        }
    }

    /// Whether both are lines or both points, with equal end points (the tests' `coords_equal`).
    func coordsEqual(_ other: LineOrPoint) -> Bool {
        isLine == other.isLine && endPoints == other.endPoints
    }

    /// `PartialOrd`: requires that both left ends are strictly before both right ends. A point is
    /// an infinitesimal vertical segment centred on it.
    func partialCmp(_ other: LineOrPoint) -> RustOrdering? {
        switch (self, other) {
        case let (.point(p), .point(o)):
            // Unequal points cannot be ordered.
            return p == o ? .equal : nil
        case (.point, .line):
            return other.partialCmp(self)?.reversed
        case let (.line(left, right), .point(p)):
            if p.gt(right) || left.gt(p) {
                return nil
            }
            return RobustKernel.orient2d(left.coord, right.coord, p.coord).asOrdering.then(.greater)
        case let (.line(leftA, rightA), .line(leftB, rightB)):
            if leftA.gt(leftB) {
                return other.partialCmp(self)?.reversed
            }
            if leftA.ge(rightB) || leftB.ge(rightA) {
                return nil
            }
            let first = RobustKernel.orient2d(leftA.coord, rightA.coord, leftB.coord).asOrdering
            if first != .equal {
                return first
            }
            return RobustKernel.orient2d(leftA.coord, rightA.coord, rightB.coord).asOrdering
        }
    }

    /// `PartialEq`, defined by the ordering.
    func eq(_ other: LineOrPoint) -> Bool {
        partialCmp(other) == .equal
    }
}
