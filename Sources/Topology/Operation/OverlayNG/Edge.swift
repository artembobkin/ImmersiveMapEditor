/// A noded edge of an overlay, with what each input has it as, merged with
/// its duplicates: JTS's `Edge` of OverlayNG.
final class Edge {
    /// Whether the points collapse: fewer than two, or a first or last
    /// segment of zero length.
    static func isCollapsed(_ pts: [Coordinate]) -> Bool {
        if pts.count < 2 { return true }
        if pts[0].equals2D(pts[1]) { return true }
        if pts.count > 2 && pts[pts.count - 1].equals2D(pts[pts.count - 2]) { return true }
        return false
    }

    let pts: [Coordinate]
    @exclusivity(unchecked) private var aDim = OverlayLabel.dimUnknown
    @exclusivity(unchecked) private var aDepthDelta = 0
    @exclusivity(unchecked) private var aIsHole = false
    @exclusivity(unchecked) private var bDim = OverlayLabel.dimUnknown
    @exclusivity(unchecked) private var bDepthDelta = 0
    @exclusivity(unchecked) private var bIsHole = false

    init(_ pts: [Coordinate], _ info: EdgeSourceInfo) {
        self.pts = pts
        copyInfo(info)
    }

    var size: Int { pts.count }

    /// True when the edge runs from its lesser end: of the first and last
    /// points, else of the second and second last.
    func direction() throws -> Bool {
        if pts.count < 2 { throw IllegalStateException("Edge must have >= 2 points") }
        let p0 = pts[0], p1 = pts[1]
        let pn0 = pts[pts.count - 1], pn1 = pts[pts.count - 2]
        var cmp = 0
        let cmp0 = p0.compareTo(pn0)
        if cmp0 != 0 { cmp = cmp0 }
        if cmp == 0 {
            let cmp1 = p1.compareTo(pn1)
            if cmp1 != 0 { cmp = cmp1 }
        }
        if cmp == 0 { throw IllegalStateException("Edge direction cannot be determined because endpoints are equal") }
        return cmp == -1
    }

    /// Whether both edges start the same way.
    func relativeDirection(_ edge2: Edge) -> Bool {
        if !pts[0].equals2D(edge2.pts[0]) { return false }
        if !pts[1].equals2D(edge2.pts[1]) { return false }
        return true
    }

    func createLabel() -> OverlayLabel {
        let lbl = OverlayLabel()
        Edge.initLabel(lbl, 0, aDim, aDepthDelta, aIsHole)
        Edge.initLabel(lbl, 1, bDim, bDepthDelta, bIsHole)
        return lbl
    }

    private static func initLabel(_ lbl: OverlayLabel, _ geomIndex: Int, _ dim: Int, _ depthDelta: Int, _ isHole: Bool) {
        switch labelDim(dim, depthDelta) {
        case OverlayLabel.dimNotPart: lbl.initNotPart(geomIndex)
        case OverlayLabel.dimBoundary: lbl.initBoundary(geomIndex, locationLeft(depthDelta), locationRight(depthDelta), isHole)
        case OverlayLabel.dimCollapse: lbl.initCollapse(geomIndex, isHole)
        case OverlayLabel.dimLine: lbl.initLine(geomIndex)
        default: break
        }
    }

    /// A ring whose merged depth delta is zero has collapsed.
    private static func labelDim(_ dim: Int, _ depthDelta: Int) -> Int {
        if dim == Dimension.false { return OverlayLabel.dimNotPart }
        if dim == Dimension.l { return OverlayLabel.dimLine }
        if depthDelta == 0 { return OverlayLabel.dimCollapse }
        return OverlayLabel.dimBoundary
    }

    /// Whether the edge is of a shell of the input (its dimension is the
    /// input's, `Dimension.a`, compared with the label's boundary code as JTS
    /// does: both are 2).
    private func isShell(_ geomIndex: Int) -> Bool {
        if geomIndex == 0 { return aDim == OverlayLabel.dimBoundary && !aIsHole }
        return bDim == OverlayLabel.dimBoundary && !bIsHole
    }

    private static func locationRight(_ depthDelta: Int) -> Int {
        switch delSign(depthDelta) {
        case 1: return Location.interior
        case -1: return Location.exterior
        default: return OverlayLabel.locUnknown
        }
    }

    private static func locationLeft(_ depthDelta: Int) -> Int {
        switch delSign(depthDelta) {
        case 1: return Location.exterior
        case -1: return Location.interior
        default: return OverlayLabel.locUnknown
        }
    }

    private static func delSign(_ depthDel: Int) -> Int {
        if depthDel > 0 { return 1 }
        if depthDel < 0 { return -1 }
        return 0
    }

    private func copyInfo(_ info: EdgeSourceInfo) {
        if info.index == 0 {
            aDim = info.dim
            aIsHole = info.isHole
            aDepthDelta = info.depthDelta
        } else {
            bDim = info.dim
            bIsHole = info.isHole
            bDepthDelta = info.depthDelta
        }
    }

    /// Takes in a duplicate: a shell wins over a hole, the higher dimension
    /// wins, and the depth deltas add up, flipped when it runs the other way.
    func merge(_ edge: Edge) {
        aIsHole = Edge.isHoleMerged(0, self, edge)
        bIsHole = Edge.isHoleMerged(1, self, edge)
        if edge.aDim > aDim { aDim = edge.aDim }
        if edge.bDim > bDim { bDim = edge.bDim }
        let flipFactor = relativeDirection(edge) ? 1 : -1
        aDepthDelta += flipFactor * edge.aDepthDelta
        bDepthDelta += flipFactor * edge.bDepthDelta
    }

    private static func isHoleMerged(_ geomIndex: Int, _ edge1: Edge, _ edge2: Edge) -> Bool {
        let isShellMerged = edge1.isShell(geomIndex) || edge2.isShell(geomIndex)
        return !isShellMerged
    }
}
