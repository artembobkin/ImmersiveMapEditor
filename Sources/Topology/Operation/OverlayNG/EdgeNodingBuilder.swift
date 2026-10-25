/// Extracts the edges of an overlay's inputs (rings clipped and lines
/// limited to the clipping envelope, repeated points removed), nodes them,
/// and merges the duplicates: JTS's `EdgeNodingBuilder`. At floating
/// precision the noder is the MC index noder with an intersection adder,
/// its result validated; at a fixed one, snap rounding.
final class EdgeNodingBuilder {
    private static let minLimitPts = 20
    private static let isNodingValidated = true

    private let pm: PrecisionModel?
    @exclusivity(unchecked) private var inputEdges: [NodedSegmentString] = []
    private let customNoder: Noder?
    @exclusivity(unchecked) private var clipEnv: Envelope?
    @exclusivity(unchecked) private var clipper: RingClipper?
    @exclusivity(unchecked) private var limiter: LineLimiter?
    @exclusivity(unchecked) private var hasEdges = [false, false]

    init(_ pm: PrecisionModel?, _ noder: Noder?) {
        self.pm = pm
        customNoder = noder
    }

    private func getNoder() -> Noder {
        if let customNoder { return customNoder }
        if OverlayUtil.isFloating(pm) {
            let mcNoder = MCIndexNoder(IntersectionAdder(RobustLineIntersector()))
            return EdgeNodingBuilder.isNodingValidated ? ValidatingNoder(mcNoder) : mcNoder
        }
        return SnapRoundingNoder(pm!)
    }

    func setClipEnvelope(_ clipEnv: Envelope) {
        self.clipEnv = clipEnv
        clipper = RingClipper(clipEnv)
        limiter = LineLimiter(clipEnv)
    }

    /// Whether an input kept any edge after noding (it may collapse away).
    func hasEdgesFor(_ geomIndex: Int) -> Bool { hasEdges[geomIndex] }

    func build(_ geom0: Geometry?, _ geom1: Geometry?) throws -> [Edge] {
        try add(geom0, 0)
        try add(geom1, 1)
        let nodedEdges = try node(inputEdges)
        return try EdgeMerger.merge(nodedEdges)
    }

    private func node(_ segStrings: [NodedSegmentString]) throws -> [Edge] {
        let noder = getNoder()
        try noder.computeNodes(segStrings)
        return createEdges(noder.getNodedSubstrings())
    }

    private func createEdges(_ segStrings: [SegmentString]) -> [Edge] {
        var edges: [Edge] = []
        for ss in segStrings {
            let pts = ss.getCoordinates()
            if Edge.isCollapsed(pts) { continue }
            let info = ss.getData() as! EdgeSourceInfo
            hasEdges[info.index] = true
            edges.append(Edge(pts, info))
        }
        return edges
    }

    private func add(_ g: Geometry?, _ geomIndex: Int) throws {
        guard let g, !g.isEmpty() else { return }
        if isClippedCompletely(g.getEnvelopeInternal()) { return }
        switch g {
        case let poly as Polygon: addPolygon(poly, geomIndex)
        case let line as LineString: addLine(line, geomIndex)
        case let ml as MultiLineString: try addCollection(ml, geomIndex)
        case let mp as MultiPolygon: try addCollection(mp, geomIndex)
        case is MultiPoint: break
        case let gc as GeometryCollection: try addGeometryCollection(gc, geomIndex, g.getDimension())
        default: break
        }
    }

    private func addCollection(_ gc: GeometryCollection, _ geomIndex: Int) throws {
        for g in gc.geometries { try add(g, geomIndex) }
    }

    private func addGeometryCollection(_ gc: GeometryCollection, _ geomIndex: Int, _ expectedDim: Int) throws {
        for g in gc.geometries {
            if g.getDimension() != expectedDim { throw IllegalArgumentException("Overlay input is mixed-dimension") }
            try add(g, geomIndex)
        }
    }

    private func addPolygon(_ poly: Polygon, _ geomIndex: Int) {
        addPolygonRing(poly.shell, false, geomIndex)
        for hole in poly.holes { addPolygonRing(hole, true, geomIndex) }
    }

    private func addPolygonRing(_ ring: LinearRing, _ isHole: Bool, _ index: Int) {
        if ring.isEmpty() { return }
        if isClippedCompletely(ring.getEnvelopeInternal()) { return }
        let pts = clip(ring)
        // A ring clipped down to nothing that matters.
        if pts.count < 2 { return }
        let depthDelta = EdgeNodingBuilder.computeDepthDelta(ring, isHole)
        addEdge(pts, EdgeSourceInfo(index, depthDelta, isHole))
    }

    private func isClippedCompletely(_ env: Envelope) -> Bool {
        guard let clipEnv else { return false }
        return clipEnv.disjoint(env)
    }

    private func clip(_ ring: LinearRing) -> [Coordinate] {
        let env = ring.getEnvelopeInternal()
        if clipper == nil || clipEnv!.covers(env) { return CoordinateArrays.removeRepeatedPoints(ring.points) }
        return clipper!.clip(ring.points)
    }

    /// +1 for a ring with the area on its right (a clockwise shell, a
    /// counter-clockwise hole), -1 otherwise.
    private static func computeDepthDelta(_ ring: LinearRing, _ isHole: Bool) -> Int {
        let isCCW = Orientation.isCCW(ring.points)
        let isOriented = isHole ? isCCW : !isCCW
        return isOriented ? 1 : -1
    }

    private func addLine(_ line: LineString, _ geomIndex: Int) {
        if line.isEmpty() { return }
        if isClippedCompletely(line.getEnvelopeInternal()) { return }
        if isToBeLimited(line) {
            for pts in limiter!.limit(line.points) { addLine(pts, geomIndex) }
        } else {
            addLine(CoordinateArrays.removeRepeatedPoints(line.points), geomIndex)
        }
    }

    private func addLine(_ pts: [Coordinate], _ geomIndex: Int) {
        if pts.count < 2 { return }
        addEdge(pts, EdgeSourceInfo(geomIndex))
    }

    private func addEdge(_ pts: [Coordinate], _ info: EdgeSourceInfo) {
        inputEdges.append(NodedSegmentString(pts, info))
    }

    /// A long line partly outside the clipping envelope is cut to the
    /// sections near it.
    private func isToBeLimited(_ line: LineString) -> Bool {
        if limiter == nil || line.points.count <= EdgeNodingBuilder.minLimitPts { return false }
        if clipEnv!.covers(line.getEnvelopeInternal()) { return false }
        return true
    }
}
