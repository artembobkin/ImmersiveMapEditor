/// Builds the lines of an overlay's result from the graph's linear edges
/// in the result, one line per edge (they are not merged at nodes): JTS's
/// `LineBuilder` of OverlayNG.
final class LineBuilder {
    private let factory: GeometryFactory
    private let graph: OverlayGraph
    private let opCode: Int
    private let inputAreaIndex: Int
    private let hasResultArea: Bool
    @exclusivity(unchecked) private var isAllowMixedResult = !OverlayNG.strictModeDefault
    @exclusivity(unchecked) private var isAllowCollapseLines = !OverlayNG.strictModeDefault
    @exclusivity(unchecked) private var lines: [LineString] = []

    init(_ inputGeom: InputGeometry, _ graph: OverlayGraph, _ hasResultArea: Bool, _ opCode: Int, _ factory: GeometryFactory) {
        self.graph = graph
        self.opCode = opCode
        self.factory = factory
        self.hasResultArea = hasResultArea
        inputAreaIndex = inputGeom.getAreaIndex()
    }

    func setStrictMode(_ isStrictResultMode: Bool) {
        isAllowCollapseLines = !isStrictResultMode
        isAllowMixedResult = !isStrictResultMode
    }

    func getLines() -> [LineString] {
        markResultLines()
        addResultLines()
        return lines
    }

    private func markResultLines() {
        for edge in graph.edges where !edge.isInResultEither && isResultLine(edge.label) {
            edge.markInResultLine()
        }
    }

    /// Whether a linear edge of this label is in the result.
    private func isResultLine(_ lbl: OverlayLabel) -> Bool {
        // A boundary of one area alone is never a line of the result.
        if lbl.isBoundarySingleton() { return false }
        if !isAllowCollapseLines && lbl.isBoundaryCollapse() { return false }
        if lbl.isInteriorCollapse() { return false }
        if opCode != OverlayNG.intersection {
            if lbl.isCollapseAndNotPartInterior() { return false }
            if hasResultArea && lbl.isLineInArea(inputAreaIndex) { return false }
        }
        if isAllowMixedResult && opCode == OverlayNG.intersection && lbl.isBoundaryTouch() { return true }
        let aLoc = LineBuilder.effectiveLocation(lbl, 0)
        let bLoc = LineBuilder.effectiveLocation(lbl, 1)
        return OverlayNG.isResultOfOp(opCode, aLoc, bLoc)
    }

    /// A collapse or a line counts as interior to its own input.
    private static func effectiveLocation(_ lbl: OverlayLabel, _ geomIndex: Int) -> Int {
        if lbl.isCollapse(geomIndex) { return Location.interior }
        if lbl.isLine(geomIndex) { return Location.interior }
        return lbl.getLineLocation(geomIndex)
    }

    private func addResultLines() {
        for edge in graph.edges where edge.isInResultLine && !edge.isVisited {
            lines.append(toLine(edge))
            edge.markVisitedBoth()
        }
    }

    /// The edge as a line in the direction of its input. The forward
    /// half-edge always comes first in the graph, so this is its direction,
    /// as GEOS gives it.
    private func toLine(_ edge: OverlayEdge) -> LineString {
        var pts = CoordinateList()
        pts.add(edge.orig, false)
        edge.addCoordinates(&pts)
        return factory.createLineString(pts.toCoordinateArray(edge.isForward))
    }
}
