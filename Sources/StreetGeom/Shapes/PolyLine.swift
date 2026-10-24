/// geom's `PolyLine`: at least two points, no adjacent or repeated points,
/// with its length cached. Construction, gluing and the simple accessors.
/// Slicing is in `PolyLineSlicing.swift`, shifting and thickening in
/// `PolyLineShift.swift`.

/// The miter limit geom uses when shifting.
let miterThreshold = 500.0

public enum ArrowCap: Sendable {
    case triangle
}

/// Rust derives `PartialEq`: the points compared with geom's approximate
/// equality and the cached lengths exactly.
public struct PolyLine: Equatable, Sendable, CustomStringConvertible {
    public private(set) var points: [Pt2D]
    public private(set) var length: Distance

    @usableFromInline init(points: [Pt2D], length: Distance) {
        self.points = points
        self.length = length
    }

    @usableFromInline static func foldLength(_ pts: [Pt2D]) -> Distance {
        var soFar = Distance.zero
        if pts.count >= 2 {
            for i in 1..<pts.count { soFar = soFar + pts[i - 1].distTo(pts[i]) }
        }
        return soFar
    }

    public static func new(_ pts: [Pt2D]) throws -> PolyLine {
        if pts.count < 2 { throw bail("Need at least two points for a PolyLine") }
        let length = foldLength(pts)
        for i in 1..<pts.count where pts[i - 1] == pts[i] {
            throw bail("PL with total length \(length) and \(pts.count) pts has ~dupe adjacent pts")
        }
        if !toSet(pts).dupes.isEmpty {
            throw bail("PL with total length \(length) and \(pts.count) pts has dupe non-adjacent pts")
        }
        return PolyLine(points: pts, length: length)
    }

    public static func mustNew(_ pts: [Pt2D]) -> PolyLine {
        do { return try new(pts) } catch { fatalError("\(error)") }
    }

    /// Doesn't check for duplicates.
    public static func uncheckedNew(_ pts: [Pt2D]) -> PolyLine {
        precondition(pts.count >= 2)
        return PolyLine(points: pts, length: foldLength(pts))
    }

    /// First dedupes adjacent points.
    public static func dedupingNew(_ pts: [Pt2D]) throws -> PolyLine {
        var pts = pts
        pts.dedup()
        return try new(pts)
    }

    public func reversed() -> PolyLine { .mustNew(points.reversed()) }

    public func maybeReverse(_ reverse: Bool) -> PolyLine { reverse ? reversed() : self }

    /// The quadrant of the overall angle, between 1 and 4.
    public func quadrant() -> Int64 {
        let lineAngle = overallAngle().normalizedRadians()
        let q = Int64(lineAngle / (Double.pi / 2.0))
        let r = q % 4
        return (r < 0 ? r + 4 : r) + 1
    }

    /// Glues `other` after `self`: the last point of `self` must be the first
    /// of `other`. Clips out loops and drops a point that lies on the line
    /// being extended.
    public func extend(_ other: PolyLine) throws -> PolyLine {
        if points.last! != other.points[0] {
            throw bail("can't extend PL; last and first points don't match")
        }
        var selfPts = points
        var otherPts = other.points
        while true {
            let pl1 = toSet(selfPts).deduped
            let pl2 = toSet(Array(otherPts[1...])).deduped
            if pl1.isDisjoint(with: pl2) { break }
            for (otherRevIdx, pt) in otherPts.reversed().enumerated() where pl1.contains(pt.toHashable()) {
                while selfPts.last! != pt { selfPts.removeLast() }
                otherPts = Array(otherPts[(otherPts.count - 1 - otherRevIdx)...])
                break
            }
            precondition(selfPts.last! == otherPts[0])
        }
        if otherPts.count >= 2 {
            let sameLine = selfPts[selfPts.count - 2].angleTo(selfPts[selfPts.count - 1])
                .approxEq(otherPts[0].angleTo(otherPts[1]), 0.1)
            if sameLine { selfPts.removeLast() }
        }
        selfPts.append(contentsOf: otherPts.dropFirst())
        return try .new(selfPts)
    }

    public func mustExtend(_ other: PolyLine) -> PolyLine {
        do { return try extend(other) } catch { fatalError("\(error)") }
    }

    /// Adds one point, deduping it if close to the last.
    public func optionallyPush(_ pt: Pt2D) -> PolyLine {
        var pts = points
        pts.append(pt)
        return (try? PolyLine.dedupingNew(pts)) ?? self
    }

    /// Like `extend`, inserting the first point of `other` if the ends don't meet.
    public func forceExtend(_ other: PolyLine) throws -> PolyLine {
        var copy = self
        if copy.points.last! != other.points[0] {
            copy.points.append(other.points[0])
        }
        return try copy.extend(other)
    }

    public static func append(_ first: [Pt2D], _ second: [Pt2D]) throws -> [Pt2D] {
        if second.isEmpty { return first }
        if first.isEmpty { return second }
        return try PolyLine.new(first).extend(try PolyLine.new(second)).points
    }

    public func lines() -> [Line] {
        var result: [Line] = []
        result.reserveCapacity(points.count - 1)
        for i in 1..<points.count { result.append(.mustNew(points[i - 1], points[i])) }
        return result
    }

    public func firstPt() -> Pt2D { points[0] }
    public func lastPt() -> Pt2D { points[points.count - 1] }
    public func firstLine() -> Line { .mustNew(points[0], points[1]) }
    public func lastLine() -> Line { .mustNew(points[points.count - 2], points[points.count - 1]) }

    public func getBounds() -> Bounds { .from(points) }

    public func overallAngle() -> Angle { firstPt().angleTo(lastPt()) }

    /// A placeholder value.
    public static func dummy() -> PolyLine { .mustNew([Pt2D(0.0, 0.0), Pt2D(0.1, 0.1)]) }

    public var description: String {
        var out = "PolyLine::new(vec![     // length \(length)\n"
        for (idx, pt) in points.enumerated() {
            out += "  Pt2D::new(\(rustDisplay(pt.x)), \(rustDisplay(pt.y))),"
            if idx > 0 {
                let line = Line.mustNew(points[idx - 1], pt)
                out += "    // \(rustDisplay(pt.x - points[idx - 1].x)), \(rustDisplay(pt.y - points[idx - 1].y)) (+ \(line.length()) @ \(line.angle()))"
            }
            out += "\n"
        }
        return out + "])"
    }
}

/// The points as a set, and the points seen more than once.
func toSet(_ pts: [Pt2D]) -> (deduped: Set<HashablePt2D>, dupes: Set<HashablePt2D>) {
    var deduped = Set<HashablePt2D>()
    var dupes = Set<HashablePt2D>()
    for pt in pts {
        let h = pt.toHashable()
        if deduped.contains(h) { dupes.insert(h) } else { deduped.insert(h) }
    }
    return (deduped, dupes)
}
