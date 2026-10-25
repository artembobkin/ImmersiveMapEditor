/// Snap-rounding noding: every intersection and vertex rounded to the grid
/// of a fixed precision model, and every segment that crosses a hot pixel
/// snapped to its centre, so the result is fully noded on the grid: JTS's
/// `SnapRoundingNoder`.
public final class SnapRoundingNoder: Noder {
    static let nearnessFactor = 100.0

    let pm: PrecisionModel
    let pixelIndex: HotPixelIndex
    @exclusivity(unchecked) var snappedResult: [NodedSegmentString] = []

    public init(_ pm: PrecisionModel) {
        self.pm = pm
        pixelIndex = HotPixelIndex(pm)
    }

    public func getNodedSubstrings() -> [SegmentString] { NodedSegmentString.getNodedSubstrings(snappedResult) }

    public func computeNodes(_ inputSegmentStrings: [SegmentString]) throws {
        let strings = inputSegmentStrings.map { $0 as! NodedSegmentString }
        try addIntersectionPixels(strings)
        try addVertexPixels(strings)
        snappedResult = computeSnaps(strings)
    }

    func addIntersectionPixels(_ segStrings: [NodedSegmentString]) throws {
        let snapGridSize = 1.0 / pm.scale
        let nearnessTol = snapGridSize / SnapRoundingNoder.nearnessFactor
        let intAdder = SnapRoundingIntersectionAdder(nearnessTol)
        let noder = MCIndexNoder(intAdder, overlapTolerance: nearnessTol)
        noder.computeNodes(segStrings)
        try pixelIndex.addNodes(intAdder.intersections)
    }

    func addVertexPixels(_ segStrings: [NodedSegmentString]) throws {
        for ss in segStrings { try pixelIndex.add(ss.getCoordinates()) }
    }

    func round(_ pt: Coordinate) -> Coordinate { pm.makePrecise(pt) }

    /// The points rounded, no point repeated in a row.
    func round(_ pts: [Coordinate]) -> [Coordinate] {
        var out: [Coordinate] = []
        for p in pts {
            let r = round(p)
            if out.last != r { out.append(r) }
        }
        return out
    }

    func computeSnaps(_ segStrings: [NodedSegmentString]) -> [NodedSegmentString] {
        var snapped: [NodedSegmentString] = []
        for ss in segStrings {
            if let s = computeSegmentSnaps(ss) { snapped.append(s) }
        }
        for ss in snapped { addVertexNodeSnaps(ss) }
        return snapped
    }

    func computeSegmentSnaps(_ ss: NodedSegmentString) -> NodedSegmentString? {
        let pts = ss.getNodedCoordinates()
        let ptsRound = round(pts)
        if ptsRound.count <= 1 { return nil }
        let snapSS = NodedSegmentString(ptsRound, ss.getData())
        var snapSSindex = 0
        for i in 0..<(pts.count - 1) {
            let currSnap = snapSS.getCoordinate(snapSSindex)
            let p1 = pts[i + 1]
            if round(p1).equals2D(currSnap) { continue }
            snapSegment(pts[i], p1, snapSS, snapSSindex)
            snapSSindex += 1
        }
        return snapSS
    }

    func snapSegment(_ p0: Coordinate, _ p1: Coordinate, _ ss: NodedSegmentString, _ segIndex: Int) {
        pixelIndex.query(p0, p1) { hp in
            if !hp.isNode && (hp.intersects(p0) || hp.intersects(p1)) { return }
            if hp.intersects(p0, p1) {
                ss.addIntersection(hp.coordinate, segIndex)
                hp.setToNode()
            }
        }
    }

    func addVertexNodeSnaps(_ ss: NodedSegmentString) {
        let pts = ss.getCoordinates()
        guard pts.count > 2 else { return }
        for i in 1..<(pts.count - 1) { snapVertexNode(pts[i], ss, i) }
    }

    func snapVertexNode(_ p0: Coordinate, _ ss: NodedSegmentString, _ segIndex: Int) {
        pixelIndex.query(p0, p0) { hp in
            if hp.isNode && hp.coordinate.equals2D(p0) { ss.addIntersection(p0, segIndex) }
        }
    }
}
