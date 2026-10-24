/// geo's sweep events: the start or end of a segment (or point) at a sweep point, ordered for the
/// max-heap so that the lexicographically smallest point, and at one point the smallest event
/// type, comes out first.

/// The event types in geo's order. Right ends come before left ends at the same point, so the
/// active segments stay totally ordered, and a point's events enclose the line events.
enum SweepEventType: Int, Comparable {
    case pointLeft
    case lineRight
    case lineLeft
    case pointRight

    static func < (lhs: SweepEventType, rhs: SweepEventType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SweepEvent<C: SweepCross> {
    let point: SweepPoint
    let ty: SweepEventType
    let payload: IMSegment<C>

    /// `Event::cmp`: by point, then type, reversed for the max-heap. Ignores the payload.
    static func cmp(_ a: SweepEvent<C>, _ b: SweepEvent<C>) throws(GeoPanic) -> RustOrdering {
        try a.point.cmp(b.point).then(RustOrdering.compare(a.ty, b.ty)).reversed
    }
}
