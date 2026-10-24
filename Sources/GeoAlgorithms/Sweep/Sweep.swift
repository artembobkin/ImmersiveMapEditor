/// geo's `Sweep` (`sweep/proc.rs`), part one: the event queue, the active set, the creation and
/// splitting of segments, and the processing of two adjacent segments. The event handlers are in
/// `SweepHandleEvent.swift`.

final class Sweep<C: SweepCross> {
    let isSimple: Bool
    var events: RustBinaryHeap<SweepEvent<C>, GeoPanic>
    var activeSegments = ActiveSet<C>()
    /// The creation counter that orders segments in place of their `Rc` addresses.
    private var nextSerial = 0

    init<S: Sequence>(_ crossables: S, isSimple: Bool) throws(GeoPanic) where S.Element == C {
        self.isSimple = isSimple
        self.events = RustBinaryHeap(cmp: SweepEvent<C>.cmp)
        for cr in crossables {
            _ = try createSegment(cr, geom: nil, parent: nil)
        }
    }

    private func makeSegment(_ cross: C, _ geom: LineOrPoint?) -> IMSegment<C> {
        let segment = IMSegment(cross: cross, geom: geom, serial: nextSerial)
        nextSerial += 1
        return segment
    }

    /// `IMSegment::create_segment`: a new segment with its two events pushed, and, if it is a
    /// piece of `parent`, copies of the parent's overlap chain over the same geometry.
    @discardableResult
    func createSegment(_ crossable: C, geom: LineOrPoint?, parent: IMSegment<C>?) throws(GeoPanic) -> IMSegment<C> {
        let segment = makeSegment(crossable, geom)
        for e in [segment.leftEvent(), segment.rightEvent()] {
            try events.push(e)
        }
        if let parent {
            let segmentGeom = segment.geom
            var child = parent.overlapping
            var tgt = segment
            while let childSeg = child {
                let newSegment = makeSegment(childSeg.cross, segmentGeom)
                tgt.overlapping = newSegment
                newSegment.isOverlappingFlag = true
                tgt = newSegment
                child = childSeg.overlapping
            }
        }
        return segment
    }

    /// `IMSegment::adjust_one_segment`: splits `segment` at `adjIntersection`, queues the new
    /// pieces, and returns the piece that overlaps the intersection, if any.
    func adjustOneSegment(_ segment: IMSegment<C>, _ adjIntersection: LineOrPoint) throws(GeoPanic) -> IMSegment<C>? {
        let adjCross = segment.cross
        switch try segment.adjustForIntersection(adjIntersection) {
        case .unchanged(let overlap):
            return overlap ? segment : nil
        case .splitOnce(let overlap, let right):
            try events.push(segment.rightEvent())
            let newKey = try createSegment(adjCross, geom: right, parent: segment)
            switch overlap {
            case false?: return segment
            case true?: return newKey
            case nil: return nil
            }
        case .splitTwice(let right):
            try events.push(segment.rightEvent())
            try createSegment(adjCross, geom: right, parent: segment)
            let middle = try createSegment(adjCross, geom: adjIntersection, parent: segment)
            return middle
        }
    }

    /// The result of `process_adjacent_segments`.
    struct AdjProcOutput {
        var isec: LineOrPoint?
        var shouldContinue: Bool
        var shouldCallback: Bool
    }

    /// `process_adjacent_segments`: intersects the active segment `active` with `other` and
    /// splits both. This loops because two segments may only become overlapping once broken at
    /// their intersection point.
    func processAdjacentSegments(_ active: IMSegment<C>, _ other: IMSegment<C>) throws(GeoPanic) -> AdjProcOutput {
        var out = AdjProcOutput(isec: nil, shouldContinue: true, shouldCallback: false)
        while let isec = try other.geom.intersectLineOrdered(active.geom) {
            out.isec = isec
            // Split the active segment, then the event segment.
            let adjOverlap = try adjustOneSegment(active, isec)
            let segOverlap = try adjustOneSegment(other, isec)
            if (adjOverlap != nil) != (segOverlap != nil) {
                throw GeoPanic("assertion `left == right` failed: one of the intersecting segments had an overlap, but not the other!")
            }
            if let adjOvl = adjOverlap, let tgt = segOverlap {
                adjOvl.chainOverlap(tgt)
                if tgt === other {
                    // The whole event segment now overlaps an active segment.
                    out.shouldCallback = adjOvl.leftEventDone
                    out.shouldContinue = false
                }
                // Overlaps are computed exactly, so there is no need to loop again.
                return out
            }
            if active.geom.partialCmp(other.geom) == .equal {
                continue
            } else {
                break
            }
        }
        return out
    }

    /// `next_event`: pops and handles the next event, returning its point.
    func nextEvent(_ cb: (IMSegment<C>, SweepEventType) -> Void) throws(GeoPanic) -> SweepPoint? {
        guard let event = try events.pop() else { return nil }
        let pt = event.point
        _ = try handleEvent(event, cb)
        return pt
    }

    /// `with_prev_active`: the active segment just below the crossing's segment.
    func prevActive(_ segment: IMSegment<C>) throws(GeoPanic) -> IMSegment<C>? {
        try activeSegments.previous(segment)
    }

    func peekPoint() -> SweepPoint? {
        events.peek()?.point
    }
}
