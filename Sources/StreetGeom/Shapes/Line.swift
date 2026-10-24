/// geom's `Line` (a segment between two distinct points) and
/// `InfiniteLine` (the line through two points).

public enum GeomError: Error, CustomStringConvertible {
    case message(String)
    public var description: String {
        switch self {
        case .message(let m): return m
        }
    }
}

@inlinable func bail(_ message: @autoclosure () -> String) -> GeomError { .message(message()) }

/// A line segment. Rust derives `PartialEq`, comparing the points with
/// geom's approximate equality.
public struct Line: Equatable, Sendable, CustomStringConvertible {
    public let pt1: Pt2D
    public let pt2: Pt2D

    @usableFromInline init(unchecked pt1: Pt2D, _ pt2: Pt2D) {
        self.pt1 = pt1
        self.pt2 = pt2
    }

    /// The two points must not be the same.
    @inlinable
    public static func new(_ pt1: Pt2D, _ pt2: Pt2D) throws -> Line {
        if pt1.distTo(pt2) <= epsilonDist {
            throw bail("Line from \(pt1) to \(pt2) too small")
        }
        return Line(unchecked: pt1, pt2)
    }

    @inlinable
    public static func mustNew(_ pt1: Pt2D, _ pt2: Pt2D) -> Line {
        do { return try new(pt1, pt2) } catch { fatalError("\(error)") }
    }

    public func infinite() -> InfiniteLine { InfiniteLine(pt1, pt2) }

    public func points() -> [Pt2D] { [pt1, pt2] }

    public func toPolyline() -> PolyLine { PolyLine.mustNew(points()) }

    public func makePolygons(_ thickness: Distance) -> Polygon { toPolyline().makePolygons(thickness) }

    @inlinable public func length() -> Distance { pt1.distTo(pt2) }

    /// Where two segments hit, endpoints included.
    public func intersection(_ other: Line) -> Pt2D? {
        if isCounterClockwise(pt1, other.pt1, other.pt2) == isCounterClockwise(pt2, other.pt1, other.pt2)
            || isCounterClockwise(pt1, pt2, other.pt1) == isCounterClockwise(pt1, pt2, other.pt2) {
            return nil
        }
        guard let hit = infinite().intersection(other.infinite()) else { return nil }
        if containsPt(hit) { return hit }
        return nil
    }

    /// Two segments cross, more than touching at an endpoint.
    public func crosses(_ other: Line) -> Bool {
        if pt1 == other.pt1 || pt1 == other.pt2 || pt2 == other.pt1 || pt2 == other.pt2 { return false }
        return intersection(other) != nil
    }

    public func intersectionInfinite(_ other: InfiniteLine) -> Pt2D? {
        guard let hit = infinite().intersection(other) else { return nil }
        return containsPt(hit) ? hit : nil
    }

    public func shiftRight(_ width: Distance) -> Line {
        precondition(width >= .zero)
        let angle = self.angle().rotateDegs(90.0)
        return .mustNew(pt1.projectAway(width, angle), pt2.projectAway(width, angle))
    }

    public func shiftLeft(_ width: Distance) -> Line {
        precondition(width >= .zero)
        let angle = self.angle().rotateDegs(-90.0)
        return .mustNew(pt1.projectAway(width, angle), pt2.projectAway(width, angle))
    }

    public func shiftEitherDirection(_ width: Distance) -> Line {
        width >= .zero ? shiftRight(width) : shiftLeft(-width)
    }

    public func reversed() -> Line { .mustNew(pt2, pt1) }

    @inlinable public func angle() -> Angle { pt1.angleTo(pt2) }

    public func distAlong(_ dist: Distance) throws -> Pt2D {
        let len = length()
        if dist < .zero || dist > len {
            throw bail("dist_along(\(dist)) of a length \(len) line")
        }
        return try percentAlong(dist / len)
    }

    public func mustDistAlong(_ dist: Distance) -> Pt2D {
        do { return try distAlong(dist) } catch { fatalError("\(error)") }
    }

    public func unboundedDistAlong(_ dist: Distance) -> Pt2D { unboundedPercentAlong(dist / length()) }

    public func unboundedPercentAlong(_ percent: Double) -> Pt2D {
        Pt2D(pt1.x + percent * (pt2.x - pt1.x), pt1.y + percent * (pt2.y - pt1.y))
    }

    public func percentAlong(_ percent: Double) throws -> Pt2D {
        if !(0.0...1.0).contains(percent) {
            throw bail("percent_along(\(percent)) of some line outside [0, 1]")
        }
        return unboundedPercentAlong(percent)
    }

    public func slice(_ from: Distance, _ to: Distance) throws -> Line {
        if from < .zero || to < .zero || from >= to {
            throw bail("slice(\(from), \(to)) makes no sense")
        }
        return try .new(try distAlong(from), try distAlong(to))
    }

    public func middle() throws -> Pt2D { try distAlong(length() / 2.0) }

    public func containsPt(_ pt: Pt2D) -> Bool { distAlongOfPoint(pt) != nil }

    public func distAlongOfPoint(_ pt: Pt2D) -> Distance? {
        let dist1 = pt1.rawDistTo(pt)
        let dist2 = pt.rawDistTo(pt2)
        let length = pt1.rawDistTo(pt2)
        if Swift.abs(dist1 + dist2 - length) < epsilonDist.innerMeters {
            return .meters(dist1)
        }
        return nil
    }

    public func percentAlongOfPoint(_ pt: Pt2D) -> Double? {
        guard let dist = distAlongOfPoint(pt) else { return nil }
        return dist / length()
    }

    public var description: String {
        "Line::new(\n  Pt2D::new(\(rustDisplay(pt1.x)), \(rustDisplay(pt1.y))),\n  Pt2D::new(\(rustDisplay(pt2.x)), \(rustDisplay(pt2.y))),\n)"
    }
}

@inlinable
func isCounterClockwise(_ pt1: Pt2D, _ pt2: Pt2D, _ pt3: Pt2D) -> Bool {
    (pt3.y - pt1.y) * (pt2.x - pt1.x) > (pt2.y - pt1.y) * (pt3.x - pt1.x)
}

/// The infinite line through two points.
public struct InfiniteLine: Sendable {
    public let pt1: Pt2D
    public let pt2: Pt2D

    init(_ pt1: Pt2D, _ pt2: Pt2D) {
        self.pt1 = pt1
        self.pt2 = pt2
    }

    /// Fails for parallel lines.
    public func intersection(_ other: InfiniteLine) -> Pt2D? {
        func cross(_ a: (Double, Double), _ b: (Double, Double)) -> Double { a.0 * b.1 - a.1 * b.0 }
        let p = pt1
        let q = other.pt1
        let r = (pt2.x - pt1.x, pt2.y - pt1.y)
        let s = (other.pt2.x - other.pt1.x, other.pt2.y - other.pt1.y)
        let rCrossS = cross(r, s)
        let qMinusP = (q.x - p.x, q.y - p.y)
        if rCrossS == 0.0 { return nil }
        let t = cross(qMinusP, (s.0 / rCrossS, s.1 / rCrossS))
        return Pt2D(p.x + t * r.0, p.y + t * r.1)
    }

    public static func fromPtAngle(_ pt: Pt2D, _ angle: Angle) -> InfiniteLine {
        Line.mustNew(pt, pt.projectAway(.meters(1.0), angle)).infinite()
    }
}
