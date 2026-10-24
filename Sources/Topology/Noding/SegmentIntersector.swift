/// Processes a pair of segments the noder finds may intersect: JTS's
/// `SegmentIntersector`.
public protocol SegmentIntersector: AnyObject {
    func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int)
    func isDone() -> Bool
}
