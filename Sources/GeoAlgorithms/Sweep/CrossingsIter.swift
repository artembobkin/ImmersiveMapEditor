/// geo's `CrossingsIter`: a Bentley-Ottmann sweep that yields, point by point, every end point
/// and intersection of a set of segments, with the pieces of segments that start or end there
/// (`Crossing`), and `compare_crossings`, the order those pieces are sorted in.

/// A piece of an input that starts (`atLeft`) or ends at the point last yielded.
struct Crossing<C: SweepCross> {
    /// The input this piece belongs to.
    let cross: C
    /// The geometry of the piece.
    let line: LineOrPoint
    /// Whether this is the first piece of the input.
    let firstSegment: Bool
    /// Whether another piece overlaps this one.
    let hasOverlap: Bool
    /// Whether the piece starts at the point (else it ends there).
    let atLeft: Bool
    let segment: IMSegment<C>

    /// `Crossing::from_segment`.
    init(segment: IMSegment<C>, eventType: SweepEventType) {
        self.cross = segment.cross
        self.line = segment.geom
        self.firstSegment = segment.firstSegment
        self.hasOverlap = segment.isOverlapping
        self.atLeft = eventType == .lineLeft
        self.segment = segment
    }
}

/// `compare_crossings`: ending pieces before starting ones, then by the segment order, reversed
/// for the ending pieces.
func compareCrossings<C>(_ a: Crossing<C>, _ b: Crossing<C>) throws(GeoPanic) -> RustOrdering {
    let first = RustOrdering.compare(a.atLeft ? 1 : 0, b.atLeft ? 1 : 0)
    if first != .equal {
        return first
    }
    guard let ord = a.segment.partialCmp(b.segment) else { throw GeoPanic.unwrapNone }
    return a.atLeft ? ord : ord.reversed
}

struct CrossingsIter<C: SweepCross> {
    let sweep: Sweep<C>
    /// The pieces at the point last yielded (`intersections()`).
    var intersections: [Crossing<C>] = []

    /// `CrossingsIter::from_iter`: the full sweep, which finds intersections.
    init<S: Sequence>(_ crossables: S) throws(GeoPanic) where S.Element == C {
        self.sweep = try Sweep(crossables, isSimple: false)
    }

    /// `CrossingsIter::new_simple`: a faster sweep for inputs that meet only at end points.
    init<S: Sequence>(simple crossables: S) throws(GeoPanic) where S.Element == C {
        self.sweep = try Sweep(crossables, isSimple: true)
    }

    /// `Iterator::next`: handles every event at the next sweep point and returns that point, or
    /// `nil` when no events are left.
    mutating func next() throws(GeoPanic) -> GeoCoord? {
        intersections.removeAll(keepingCapacity: true)
        var segments: [Crossing<C>] = []
        var lastPoint = sweep.peekPoint()
        while lastPoint == sweep.peekPoint() && sweep.peekPoint() != nil {
            lastPoint = try sweep.nextEvent { seg, ty in
                segments.append(Crossing(segment: seg, eventType: ty))
            }
        }
        intersections = segments
        if intersections.isEmpty {
            return nil
        }
        return lastPoint?.coord
    }

    /// Sorts the pieces with `compare_crossings`, as `sort_unstable_by` does.
    mutating func sortIntersections() throws(GeoPanic) {
        try rustSortUnstable(&intersections, compareCrossings)
    }

    /// `prev_active`: the geometry and input of the active segment just below a starting piece.
    func prevActive(_ c: Crossing<C>) throws(GeoPanic) -> (LineOrPoint, C)? {
        guard let s = try sweep.prevActive(c.segment) else { return nil }
        return (s.geom, s.cross)
    }
}
