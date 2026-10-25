/// Builds the buffer of a geometry: its raw offset curves are noded, the
/// noded edges merged into a planar graph labelled with depths, and the
/// edges between depth 0 and 1 make the result's polygons: JTS's
/// `BufferBuilder`.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: the noding
/// of a zero-distance buffer is not validated, repeated points are removed
/// from each noded edge (and an edge left with one point dropped), and the
/// parts of the graph are sorted by libc++'s `std::sort` (not stable, so
/// parts with the same rightmost x are in its order, `CxxAlgorithms`).
final class BufferBuilder {
    private let bufParams: BufferParameters
    @exclusivity(unchecked) var workingPrecisionModel: PrecisionModel?
    @exclusivity(unchecked) var workingNoder: Noder?
    @exclusivity(unchecked) var isInvertOrientation = false
    @exclusivity(unchecked) private var geomFact: GeometryFactory!
    private let edgeList = GeomGraph.EdgeList()

    init(_ bufParams: BufferParameters) { self.bufParams = bufParams }

    /// The change of depth across an edge with this label, right to left.
    private static func depthDelta(_ label: GeomGraph.Label) -> Int {
        let lLoc = label.getLocation(0, Position.left)
        let rLoc = label.getLocation(0, Position.right)
        if lLoc == Location.interior && rLoc == Location.exterior { return 1 }
        if lLoc == Location.exterior && rLoc == Location.interior { return -1 }
        return 0
    }

    func buffer(_ g: Geometry, _ distance: Double) throws -> Geometry {
        let precisionModel = workingPrecisionModel ?? g.factory.precisionModel
        geomFact = g.factory
        let curveSetBuilder = BufferCurveSetBuilder(g, distance, precisionModel, bufParams)
        curveSetBuilder.isInvertOrientation = isInvertOrientation
        let bufferSegStrList = try curveSetBuilder.getCurves()
        if bufferSegStrList.isEmpty { return geomFact.createPolygon() }
        try computeNodedEdges(bufferSegStrList, precisionModel)
        let graph = GeomGraph.PlanarGraph()
        defer { graph.dispose() }
        try graph.addEdges(edgeList.edges)
        let subgraphList = try createSubgraphs(graph)
        let polyBuilder = Overlay.PolygonBuilder(geomFact)
        try buildSubgraphs(subgraphList, polyBuilder)
        let resultPolyList = polyBuilder.getPolygons()
        if resultPolyList.isEmpty { return geomFact.createPolygon() }
        return geomFact.buildGeometry(resultPolyList)
    }

    private func getNoder(_ precisionModel: PrecisionModel) -> Noder {
        if let workingNoder { return workingNoder }
        var li = RobustLineIntersector()
        li.precisionModel = precisionModel
        return MCIndexNoder(IntersectionAdder(li))
    }

    private func computeNodedEdges(_ bufferSegStrList: [SegmentString], _ precisionModel: PrecisionModel) throws {
        let noder = getNoder(precisionModel)
        try noder.computeNodes(bufferSegStrList)
        for segStr in noder.getNodedSubstrings() {
            let oldLabel = segStr.getData() as! GeomGraph.Label
            let cs = CoordinateArrays.removeRepeatedPoints(segStr.getCoordinates())
            if cs.count < 2 { continue }
            insertUniqueEdge(GeomGraph.Edge(cs, GeomGraph.Label(oldLabel)))
        }
    }

    /// Adds an edge, or merges it into an equal one already there: their
    /// labels merged, their depth deltas summed.
    private func insertUniqueEdge(_ e: GeomGraph.Edge) {
        if let existingEdge = edgeList.findEqualEdge(e) {
            let existingLabel = existingEdge.label
            var labelToMerge = e.label
            if !existingEdge.isPointwiseEqual(e) {
                labelToMerge = GeomGraph.Label(e.label)
                labelToMerge.flip()
            }
            existingLabel.merge(labelToMerge)
            existingEdge.depthDelta += BufferBuilder.depthDelta(labelToMerge)
        } else {
            edgeList.add(e)
            e.depthDelta = BufferBuilder.depthDelta(e.label)
        }
    }

    /// The connected parts of the graph, rightmost first.
    private func createSubgraphs(_ graph: GeomGraph.PlanarGraph) throws -> [BufferSubgraph] {
        var subgraphList: [BufferSubgraph] = []
        for node in graph.getNodes() where !node.isVisited {
            let subgraph = BufferSubgraph()
            try subgraph.create(node)
            subgraphList.append(subgraph)
        }
        CxxAlgorithms.sort(&subgraphList) { $0.compareTo($1) > 0 }
        return subgraphList
    }

    /// The depths of each part, from right to left, each from the parts to
    /// its right, and the polygons of their result edges.
    private func buildSubgraphs(_ subgraphList: [BufferSubgraph], _ polyBuilder: Overlay.PolygonBuilder) throws {
        var processedGraphs: [BufferSubgraph] = []
        for subgraph in subgraphList {
            let p = subgraph.rightMostCoord!
            let outsideDepth = SubgraphDepthLocater(subgraphs: processedGraphs).getDepth(p)
            try subgraph.computeDepth(outsideDepth)
            subgraph.findResultEdges()
            processedGraphs.append(subgraph)
            try polyBuilder.add(subgraph.dirEdgeList, subgraph.nodes)
        }
    }
}
