/// The points snapping has kept, in a KD-tree with the snap tolerance: a
/// point within it of one already there snaps to that one: JTS's
/// `SnappingPointIndex`.
public final class SnappingPointIndex {
    public let tolerance: Double
    private let snapPointIndex: KdTree<Void>

    public init(_ snapTolerance: Double) {
        tolerance = snapTolerance
        snapPointIndex = KdTree(tolerance: snapTolerance)
    }

    /// The point `p` snaps to, `p` itself when it is the first near there.
    public func snap(_ p: Coordinate) -> Coordinate {
        let node = snapPointIndex.insert(p)
        return snapPointIndex.nodes[node].coordinate
    }

    public func depth() -> Int { snapPointIndex.depth() }
}
