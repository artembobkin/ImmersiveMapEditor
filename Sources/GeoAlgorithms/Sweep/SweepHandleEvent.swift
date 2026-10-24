/// geo's `Sweep::handle_event`: what each event does to the active set (insert a starting
/// segment after intersecting it with its neighbours, remove an ending one and intersect the two
/// that become adjacent, split neighbours at a point), and which segments it reports.

extension Sweep {
    /// Handles one event and reports its segments to `cb`. Returns `false` for a stale event.
    func handleEvent(_ event: SweepEvent<C>, _ cb: (IMSegment<C>, SweepEventType) -> Void) throws(GeoPanic) -> Bool {
        guard IMSegment.isCorrect(event) else {
            return false
        }
        let segment = event.payload

        switch event.ty {
        case .lineLeft:
            var shouldAdd = true
            var insertIdx = try activeSegments.indexNotOf(segment)
            if !isSimple {
                for isNext in [true, false] {
                    let active: IMSegment<C>
                    if isNext {
                        if insertIdx < activeSegments.count {
                            active = activeSegments[insertIdx]
                        } else {
                            continue
                        }
                    } else if insertIdx > 0 {
                        active = activeSegments[insertIdx - 1]
                    } else {
                        continue
                    }
                    let out = try processAdjacentSegments(active, segment)
                    guard let isec = out.isec else {
                        continue
                    }
                    // If the adjacent segment was split and the intersection is at the start of
                    // this segment, a right event in the heap must be handled first.
                    let intPt = isec.left
                    let handleEndEvent = intPt != active.geom.left && intPt == segment.geom.left
                    if handleEndEvent {
                        guard let endEvent = try events.pop() else { throw GeoPanic.unwrapNone }
                        _ = try handleEvent(endEvent, cb)
                        if !isNext {
                            // The previous segment is now removed.
                            insertIdx -= 1
                        }
                    }
                    if !out.shouldContinue {
                        shouldAdd = false
                        if !out.shouldCallback {
                            return true
                        }
                        break
                    }
                }
            }

            if shouldAdd {
                // The insertion index is tracked as the active list is adjusted.
                try activeSegments.insertAt(insertIdx, segment)
            }

            var cbSeg: IMSegment<C>? = segment
            while let seg = cbSeg {
                cb(seg, event.ty)
                seg.leftEventDone = true
                cbSeg = seg.overlapping
            }

        case .lineRight:
            let elIdx = try activeSegments.indexOf(segment)
            let prev = elIdx > 0 ? activeSegments[elIdx - 1] : nil
            let next = 1 + elIdx < activeSegments.count ? activeSegments[elIdx + 1] : nil
            if try activeSegments.removeAt(elIdx) !== segment {
                throw GeoPanic("assertion `left == right` failed: removed a different active segment")
            }

            var cbSeg: IMSegment<C>? = segment
            while let seg = cbSeg {
                cb(seg, event.ty)
                cbSeg = seg.overlapping
            }

            if !isSimple, let prev, let next {
                if let adjIntersection = try prev.geom.intersectLineOrdered(next.geom) {
                    // Split both. Adjacent segments at a removal cannot overlap.
                    _ = try adjustOneSegment(prev, adjIntersection)
                    _ = try adjustOneSegment(next, adjIntersection)
                }
            }

        case .pointLeft:
            if !isSimple {
                let insertIdx = try activeSegments.indexNotOf(segment)
                let prev = insertIdx > 0 ? activeSegments[insertIdx - 1] : nil
                let next = insertIdx < activeSegments.count ? activeSegments[insertIdx] : nil
                for adjSegment in [prev, next].compactMap({ $0 }) {
                    let geom = adjSegment.geom
                    if let adjIntersection = try segment.geom.intersectLineOrdered(geom) {
                        // Split the adjacent segment. A point cannot overlap it.
                        _ = try adjustOneSegment(adjSegment, adjIntersection)
                    }
                }
            }
            // Points need not be active segments: report the point to the callback.
            cb(segment, event.ty)

        case .pointRight:
            // Nothing to do.
            break
        }
        return true
    }
}
