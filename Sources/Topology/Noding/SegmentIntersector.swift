/// Processes a pair of segments the noder finds may intersect: JTS's
/// `SegmentIntersector`. A base class here (JTS: an interface), so the
/// noders' calls are dispatched through its vtable without the metadata
/// lookup and reference counting of a protocol existential.
public class SegmentIntersector {
    public init() {}

    public func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) {
        preconditionFailure("abstract")
    }

    public func isDone() -> Bool { false }
}
