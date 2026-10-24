/// geo's `sweep::Intersections`: every pair of input lines that intersect or overlap, found by the
/// sweep, as a drop-in replacement for testing all pairs with `line_intersection`.

/// A line as a sweep input (geo's `Cross for Line`).
final class LineCross: SweepCross, CustomStringConvertible {
    let geoLine: GeoLine
    let line: LineOrPoint

    init(_ geoLine: GeoLine) throws(GeoPanic) {
        self.geoLine = geoLine
        self.line = try LineOrPoint(geoLine)
    }

    var description: String { "\(line)" }
}

struct Intersections<C: SweepCross> {
    private var inner: CrossingsIter<C>
    private var idx = 0
    private var jdx = 0
    private var isOverlap = false
    private var pt: GeoCoord?

    init<S: Sequence>(_ crossables: S) throws(GeoPanic) where S.Element == C {
        inner = try CrossingsIter(crossables)
    }

    private func intersection() throws(GeoPanic) -> (C, C, GeoLineIntersection)? {
        let segments = inner.intersections
        let si = segments[idx]
        let sj = segments[jdx]
        // Ignore intersections that were already reported.
        let shouldCompute: Bool
        if isOverlap {
            // An overlap is reported only when both pieces are first pieces, at their left.
            shouldCompute = si.atLeft && (si.firstSegment && sj.firstSegment)
        } else {
            shouldCompute = (!si.atLeft || si.firstSegment) && (!sj.atLeft || sj.firstSegment)
        }
        guard shouldCompute else { return nil }
        guard let int = lineIntersection(si.cross.line.geoLine, sj.cross.line.geoLine) else {
            throw GeoPanic("line_intersection returned `None` disagreeing with `CrossingsIter`")
        }
        return (si.cross, sj.cross, int)
    }

    private mutating func step() throws(GeoPanic) -> Bool {
        let segLen = inner.intersections.count
        if 1 + jdx < segLen {
            isOverlap = isOverlap && inner.intersections[jdx].hasOverlap
            jdx += 1
        } else {
            idx += 1
            if 1 + idx >= segLen {
                while true {
                    pt = try inner.next()
                    if pt == nil {
                        return false
                    }
                    if inner.intersections.count > 1 {
                        break
                    }
                }
                idx = 0
            }
            isOverlap = inner.intersections[idx].hasOverlap
            jdx = idx + 1
        }
        return true
    }

    mutating func next() throws(GeoPanic) -> (C, C, GeoLineIntersection)? {
        while true {
            if try !step() {
                return nil
            }
            if let result = try intersection() {
                return result
            }
        }
    }
}
