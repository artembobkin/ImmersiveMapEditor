/// The overlay of two geometries, or the union of one, by noding their
/// edges into a labelled graph and reading the result off it: JTS's
/// `OverlayNG`, at floating precision (validated noding, which throws a
/// `TopologyException` when it fails) or a fixed one (snap rounding, which
/// does not fail). `OverlayNGRobust` tries the ways that may fail in turn.
///
/// Results follow JTS 1.20 where GEOS 3.13 does, which is everywhere in
/// this class: empty results by the result dimension, mixed results in the
/// order areas, lines, points, lines not merged at nodes.
public final class OverlayNG {
    public static let intersection = 1
    public static let union = 2
    public static let difference = 3
    public static let symDifference = 4

    static let strictModeDefault = false

    /// Whether a point of these input locations is in the result.
    static func isResultOfOp(_ overlayOpCode: Int, _ loc0In: Int, _ loc1In: Int) -> Bool {
        let loc0 = loc0In == Location.boundary ? Location.interior : loc0In
        let loc1 = loc1In == Location.boundary ? Location.interior : loc1In
        switch overlayOpCode {
        case intersection: return loc0 == Location.interior && loc1 == Location.interior
        case union: return loc0 == Location.interior || loc1 == Location.interior
        case difference: return loc0 == Location.interior && loc1 != Location.interior
        case symDifference:
            return (loc0 == Location.interior && loc1 != Location.interior)
                || (loc0 != Location.interior && loc1 == Location.interior)
        default: return false
        }
    }

    public static func overlay(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int, _ pm: PrecisionModel?) throws -> Geometry {
        try OverlayNG(geom0, geom1, pm, opCode).getResult()
    }

    public static func overlay(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int, _ pm: PrecisionModel?,
                               noder: Noder) throws -> Geometry {
        let ov = OverlayNG(geom0, geom1, pm, opCode)
        ov.noder = noder
        return try ov.getResult()
    }

    public static func overlay(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int, noder: Noder) throws -> Geometry {
        let ov = OverlayNG(geom0, geom1, nil, opCode)
        ov.noder = noder
        return try ov.getResult()
    }

    public static func overlay(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int) throws -> Geometry {
        try OverlayNG(geom0, geom1, geom0.factory.precisionModel, opCode).getResult()
    }

    /// The union of one geometry with itself, which cleans it.
    static func union(_ geom: Geometry, _ pm: PrecisionModel?) throws -> Geometry {
        try OverlayNG(geom, nil, pm, union).getResult()
    }

    static func union(_ geom: Geometry, _ pm: PrecisionModel?, _ noder: Noder) throws -> Geometry {
        let ov = OverlayNG(geom, nil, pm, union)
        ov.noder = noder
        ov.isStrictMode = true
        return try ov.getResult()
    }

    private let opCode: Int
    private let inputGeom: InputGeometry
    private let factory: GeometryFactory
    private let pm: PrecisionModel?
    @exclusivity(unchecked) var noder: Noder?
    /// Strict mode keeps a result homogeneous: no collapsed lines, no lower
    /// dimension parts of an intersection.
    @exclusivity(unchecked) public var isStrictMode = OverlayNG.strictModeDefault
    /// Whether edges are clipped to the result's envelope first.
    @exclusivity(unchecked) public var isOptimized = true
    @exclusivity(unchecked) var isAreaResultOnly = false

    public init(_ geom0: Geometry, _ geom1: Geometry?, _ pm: PrecisionModel?, _ opCode: Int) {
        self.pm = pm
        self.opCode = opCode
        factory = geom0.factory
        inputGeom = InputGeometry(geom0, geom1)
    }

    public func getResult() throws -> Geometry {
        if OverlayUtil.isEmptyResult(opCode, inputGeom.getGeometry(0), inputGeom.getGeometry(1), pm) {
            return createEmptyResult()
        }
        // The elevation model of JTS only interpolates Z: these geometries have none.
        if inputGeom.isAllPoints {
            return OverlayPoints.overlay(opCode, inputGeom.getGeometry(0)!, inputGeom.getGeometry(1)!, pm)
        }
        if !inputGeom.isSingle && inputGeom.hasPoints {
            return try OverlayMixedPoints.overlay(opCode, inputGeom.getGeometry(0)!, inputGeom.getGeometry(1)!, pm)
        }
        return try computeEdgeOverlay()
    }

    private func computeEdgeOverlay() throws -> Geometry {
        let edges = try nodeEdges()
        let graph = try buildGraph(edges)
        try labelGraph(graph)
        let result = try extractResult(opCode, graph)
        // A noding that moved vertices can turn the graph's area inside out.
        if OverlayUtil.isFloating(pm) {
            let isAreaConsistent = OverlayUtil.isResultAreaConsistent(inputGeom.getGeometry(0), inputGeom.getGeometry(1),
                                                                      opCode, result)
            if !isAreaConsistent { throw TopologyException("Result area inconsistent with overlay operation") }
        }
        return result
    }

    private func nodeEdges() throws -> [Edge] {
        let nodingBuilder = EdgeNodingBuilder(pm, noder)
        if isOptimized, let clipEnv = OverlayUtil.clippingEnvelope(opCode, inputGeom, pm) {
            nodingBuilder.setClipEnvelope(clipEnv)
        }
        let mergedEdges = try nodingBuilder.build(inputGeom.getGeometry(0), inputGeom.getGeometry(1))
        // An input whose edges all collapsed is located as having no area.
        inputGeom.setCollapsed(0, !nodingBuilder.hasEdgesFor(0))
        inputGeom.setCollapsed(1, !nodingBuilder.hasEdgesFor(1))
        return mergedEdges
    }

    private func buildGraph(_ edges: [Edge]) throws -> OverlayGraph {
        let graph = OverlayGraph(capacity: edges.count)
        for e in edges { try graph.addEdge(e.pts, e.createLabel()) }
        return graph
    }

    private func labelGraph(_ graph: OverlayGraph) throws {
        let labeller = OverlayLabeller(graph, inputGeom)
        try labeller.computeLabelling()
        labeller.markResultAreaEdges(opCode)
        labeller.unmarkDuplicateEdgesFromResultArea()
    }

    private func extractResult(_ opCode: Int, _ graph: OverlayGraph) throws -> Geometry {
        let isAllowMixedIntResult = !isStrictMode
        let resultAreaEdges = graph.getResultAreaEdges()
        let polyBuilder = try PolygonBuilder(resultAreaEdges, factory)
        let resultPolyList = polyBuilder.getPolygons()
        let hasResultAreaComponents = !resultPolyList.isEmpty
        var resultLineList: [LineString]?
        var resultPointList: [Point]?
        if !isAreaResultOnly {
            let allowResultLines = !hasResultAreaComponents || isAllowMixedIntResult
                || opCode == OverlayNG.symDifference || opCode == OverlayNG.union
            if allowResultLines {
                let lineBuilder = LineBuilder(inputGeom, graph, hasResultAreaComponents, opCode, factory)
                lineBuilder.setStrictMode(isStrictMode)
                resultLineList = lineBuilder.getLines()
            }
            // Only an intersection gives points from inputs with edges.
            let hasResultComponents = hasResultAreaComponents || !(resultLineList?.isEmpty ?? true)
            let allowResultPoints = !hasResultComponents || isAllowMixedIntResult
            if opCode == OverlayNG.intersection && allowResultPoints {
                let pointBuilder = IntersectionPointBuilder(graph, factory)
                pointBuilder.setStrictMode(isStrictMode)
                resultPointList = pointBuilder.getPoints()
            }
        }
        if resultPolyList.isEmpty && (resultLineList?.isEmpty ?? true) && (resultPointList?.isEmpty ?? true) {
            return createEmptyResult()
        }
        return OverlayUtil.createResultGeometry(resultPolyList, resultLineList, resultPointList, factory)
    }

    private func createEmptyResult() -> Geometry {
        OverlayUtil.createEmptyResult(OverlayUtil.resultDimension(opCode, inputGeom.getDimension(0), inputGeom.getDimension(1)),
                                      factory)
    }
}
