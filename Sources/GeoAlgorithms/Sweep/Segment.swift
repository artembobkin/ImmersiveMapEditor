/// geo's sweep `Segment` and `IMSegment` (an `Rc<RefCell<Segment>>`), merged into one class: a
/// piece of an input segment, split at intersections as the sweep finds them, with the chain of
/// pieces that overlap it.

/// geo's `Cross`: an input of the sweep, a class so the sweep can share it as Rust shares `&C`.
protocol SweepCross: AnyObject {
    /// The input segment (or point), with its ends ordered.
    var line: LineOrPoint { get }
}

/// How `adjust_for_intersection` split a segment (geo's `SplitSegments`).
enum SplitSegments: CustomStringConvertible {
    case unchanged(overlap: Bool)
    case splitOnce(overlap: Bool?, right: LineOrPoint)
    case splitTwice(right: LineOrPoint)

    var description: String {
        switch self {
        case .unchanged(let o): return "Unchanged { overlap: \(o) }"
        case .splitOnce(let o, let r): return "SplitOnce { overlap: \(String(describing: o)), right: \(r) }"
        case .splitTwice(let r): return "SplitTwice { right: \(r) }"
        }
    }
}

/// A segment of the sweep. Identity (`===`) is Rust's `Rc::ptr_eq`, and `serial`, the order of
/// creation, stands in for the `Rc` address that breaks ties in the ordering.
final class IMSegment<C: SweepCross>: CustomStringConvertible {
    var geom: LineOrPoint
    let cross: C
    let firstSegment: Bool
    var leftEventDone = false
    var overlapping: IMSegment<C>?
    var isOverlappingFlag = false
    let serial: Int

    /// `Segment::new`: a `nil` geometry means the whole input, the first segment of it.
    init(cross: C, geom: LineOrPoint?, serial: Int) {
        self.firstSegment = geom == nil
        self.geom = geom ?? cross.line
        self.cross = cross
        self.serial = serial
    }

    var description: String {
        "Segment{ \(geom) \(firstSegment ? "[1st]" : "") [\(overlapping != nil ? "HAS" : "NON")/\(isOverlappingFlag ? "OVL" : "NON")] }"
    }

    /// `IMSegment::is_overlapping`: whether another segment overlaps this one (note: it reads
    /// `overlapping`, not the `is_overlapping` flag).
    var isOverlapping: Bool { overlapping != nil }

    /// `IMSegment::partial_cmp`: the geometry order, ties broken by identity.
    func partialCmp(_ other: IMSegment<C>) -> RustOrdering? {
        guard let o = geom.partialCmp(other.geom) else { return nil }
        return o.then(RustOrdering.compare(serial, other.serial))
    }

    /// `Segment::adjust_for_intersection`: splits the segment at `intersection`, mutating it
    /// into the first part and returning the rest.
    func adjustSegment(_ intersection: LineOrPoint) throws(GeoPanic) -> SplitSegments {
        let (p, q) = geom.endPoints
        if !intersection.isLine {
            let r = intersection.left
            if p == r || q == r {
                // An intersection at an end point does not split the segment.
                return .unchanged(overlap: false)
            }
            geom = try LineOrPoint(p, r)
            return .splitOnce(overlap: nil, right: try LineOrPoint(r, q))
        }
        let (r1, r2) = intersection.endPoints
        if p == r1 {
            if r2 == q {
                // The whole segment overlaps.
                return .unchanged(overlap: true)
            }
            geom = try LineOrPoint(p, r2)
            return .splitOnce(overlap: false, right: try LineOrPoint(r2, q))
        } else if r2 == q {
            geom = try LineOrPoint(p, r1)
            return .splitOnce(overlap: true, right: try LineOrPoint(r1, q))
        } else {
            geom = try LineOrPoint(p, r1)
            return .splitTwice(right: try LineOrPoint(r2, q))
        }
    }

    func leftEvent() -> SweepEvent<C> {
        SweepEvent(point: geom.left, ty: geom.isLine ? .lineLeft : .pointLeft, payload: self)
    }

    func rightEvent() -> SweepEvent<C> {
        SweepEvent(point: geom.right, ty: geom.isLine ? .lineRight : .pointRight, payload: self)
    }

    /// `chain_overlap`: appends `child` at the end of the overlap chain.
    func chainOverlap(_ child: IMSegment<C>) {
        var this = self
        while let ovl = this.overlapping {
            this = ovl
        }
        child.isOverlappingFlag = true
        this.overlapping = child
    }

    /// `IMSegment::adjust_for_intersection`: splits this segment and gives every segment of its
    /// overlap chain the new geometry.
    func adjustForIntersection(_ adjIntersection: LineOrPoint) throws(GeoPanic) -> SplitSegments {
        let adjustOutput = try adjustSegment(adjIntersection)
        let newGeom = geom
        var this = self
        while let ovl = this.overlapping {
            this = ovl
            this.geom = newGeom
        }
        return adjustOutput
    }

    /// `IMSegment::is_correct`: a right event is stale once its segment overlaps another or was
    /// shortened.
    static func isCorrect(_ event: SweepEvent<C>) -> Bool {
        if event.ty == .lineRight {
            let segment = event.payload
            return !segment.isOverlappingFlag && segment.geom.right == event.point
        }
        return true
    }
}
