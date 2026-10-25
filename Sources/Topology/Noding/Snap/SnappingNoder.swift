/// Nodes with snapping: every vertex snapped to the points kept within the
/// tolerance (seeded with a quasi-random sample of each string, so the KD-tree
/// stays balanced), then the intersections found with a tolerance and
/// snapped likewise: JTS's `SnappingNoder`. Robust overlay tries it when
/// floating noding fails.
public final class SnappingNoder: Noder {
    private let snapIndex: SnappingPointIndex
    private let snapTolerance: Double
    @exclusivity(unchecked) private var nodedResult: [SegmentString] = []

    public init(_ snapTolerance: Double) {
        self.snapTolerance = snapTolerance
        snapIndex = SnappingPointIndex(snapTolerance)
    }

    public func getNodedSubstrings() -> [SegmentString] { nodedResult }

    public func computeNodes(_ inputSegStrings: [SegmentString]) {
        let snapped = snapVertices(inputSegStrings)
        nodedResult = snapIntersections(snapped)
    }

    private func snapVertices(_ segStrings: [SegmentString]) -> [NodedSegmentString] {
        seedSnapIndex(segStrings)
        return segStrings.map { NodedSegmentString(snap($0.getCoordinates()), $0.getData()) }
    }

    private func seedSnapIndex(_ segStrings: [SegmentString]) {
        let seedSizeFactor = 100
        for ss in segStrings {
            let pts = ss.getCoordinates()
            let numPtsToLoad = pts.count / seedSizeFactor
            var rand = 0.0
            for _ in 0..<numPtsToLoad {
                rand = MathUtil.quasirandom(rand)
                let index = Int(Double(pts.count) * rand)
                _ = snapIndex.snap(pts[index])
            }
        }
    }

    private func snap(_ coords: [Coordinate]) -> [Coordinate] {
        var snapCoords = CoordinateList()
        for c in coords { snapCoords.add(snapIndex.snap(c), false) }
        return snapCoords.points
    }

    private func snapIntersections(_ inputSS: [NodedSegmentString]) -> [SegmentString] {
        let intAdder = SnappingIntersectionAdder(snapTolerance, snapIndex)
        // A tolerance on the overlaps finds every intersection a snap could make.
        let noder = MCIndexNoder(intAdder, overlapTolerance: 2 * snapTolerance)
        noder.computeNodes(inputSS)
        return noder.getNodedSubstrings()
    }
}
