/// Polygonizes a set of lines: the polygons their fully noded linework
/// encloses, JTS's `Polygonizer`, as GEOS 3.13 runs it (`GEOSPolygonize`):
/// the rings are always checked for validity, the shells are not sorted by
/// envelope (JTS 1.20 sorts them) and come in the order of the graph's
/// directed edges, the invalid rings are sorted with libc++'s `std::sort`,
/// and the disjoint shells of the polygonal mode are found by GEOS's
/// recursive update.
public final class Polygonizer {
    @exclusivity(unchecked) var graph: Polygonize.PolygonizeGraph?
    @exclusivity(unchecked) public private(set) var dangles: [LineString] = []
    @exclusivity(unchecked) public private(set) var cutEdges: [LineString] = []
    @exclusivity(unchecked) public private(set) var invalidRingLines: [LineString] = []
    @exclusivity(unchecked) var holeList: [Polygonize.EdgeRing] = []
    @exclusivity(unchecked) var shellList: [Polygonize.EdgeRing] = []
    @exclusivity(unchecked) var polyList: [Polygon]?
    let extractOnlyPolygonal: Bool

    public init(_ extractOnlyPolygonal: Bool = false) {
        self.extractOnlyPolygonal = extractOnlyPolygonal
    }

    /// Adds the linear components of a geometry: its lines and rings.
    public func add(_ g: Geometry) {
        g.applyComponents { c in
            if let line = c as? LineString { add(line: line) }
        }
    }

    public func add(_ geomList: [Geometry]) {
        for g in geomList { add(g) }
    }

    private func add(line: LineString) {
        if graph == nil { graph = Polygonize.PolygonizeGraph(line.factory) }
        graph!.addEdge(line)
    }

    public func getPolygons() throws -> [Polygon] {
        try polygonize()
        return polyList!
    }

    private func polygonize() throws {
        if polyList != nil { return }
        guard let graph else {
            polyList = []
            return
        }
        dangles = graph.deleteDangles()
        cutEdges = try graph.deleteCutEdges()
        let edgeRingList = try graph.getEdgeRings()
        var validEdgeRingList: [Polygonize.EdgeRing] = []
        var invalidRings: [Polygonize.EdgeRing] = []
        for er in edgeRingList {
            try er.computeValid()
            if er.isValid { validEdgeRingList.append(er) } else { invalidRings.append(er) }
        }
        invalidRingLines = extractInvalidLines(&invalidRings)
        findShellsAndHoles(validEdgeRingList)
        HoleAssigner.assignHolesToShells(holeList, shellList)
        var includeAll = true
        if extractOnlyPolygonal {
            findDisjointShells()
            includeAll = false
        }
        polyList = shellList.filter { includeAll || $0.isIncluded }.map { $0.getPolygon() }
    }

    private func extractInvalidLines(_ invalidRings: inout [Polygonize.EdgeRing]) -> [LineString] {
        CxxAlgorithms.sort(&invalidRings) { $0.getRing().getEnvelope().getArea() < $1.getRing().getEnvelope().getArea() }
        var invalidLines: [LineString] = []
        for er in invalidRings {
            if Polygonizer.isIncludedInvalid(er) { invalidLines.append(er.getLineString()) }
            er.isProcessed = true
        }
        return invalidLines
    }

    /// Whether an invalid ring has an edge whose other side is neither a
    /// valid ring nor an invalid one already processed.
    private static func isIncludedInvalid(_ invalidRing: Polygonize.EdgeRing) -> Bool {
        for de in invalidRing.deList {
            let erAdj = de.pSym.edgeRing!
            let isEdgeIncluded = erAdj.isValid || erAdj.isProcessed
            if !isEdgeIncluded { return true }
        }
        return false
    }

    private func findShellsAndHoles(_ edgeRingList: [Polygonize.EdgeRing]) {
        holeList = []
        shellList = []
        for er in edgeRingList {
            er.computeHole()
            if er.isHole { holeList.append(er) } else { shellList.append(er) }
        }
    }

    private func findDisjointShells() {
        Polygonizer.findOuterShells(shellList)
        for er in shellList where !er.isIncludedSet { er.updateIncludedRecursive() }
    }

    private static func findOuterShells(_ shells: [Polygonize.EdgeRing]) {
        for er in shells {
            if let outerHoleER = er.getOuterHole(), !outerHoleER.isProcessed {
                er.setIncluded(true)
                outerHoleER.isProcessed = true
            }
        }
    }
}

/// Assigns the holes of the polygonizer to the innermost shell containing
/// each, the shells in an STR tree: JTS's `HoleAssigner`.
enum HoleAssigner {
    static func assignHolesToShells(_ holes: [Polygonize.EdgeRing], _ shells: [Polygonize.EdgeRing]) {
        let shellIndex = STRtree<Polygonize.EdgeRing>()
        for shell in shells { shellIndex.insert(shell.getRing().getEnvelopeInternal(), shell) }
        for holeER in holes {
            let candidateShells = shellIndex.query(holeER.getRing().getEnvelopeInternal())
            if let shell = holeER.findEdgeRingContaining(candidateShells) { shell.addHole(holeER) }
        }
    }
}

extension Geometry {
    /// The polygons formed by the linework of the geometries, as a
    /// collection (`GEOSPolygonize`).
    public static func polygonize(_ geoms: [Geometry], factory: GeometryFactory = .default) throws -> GeometryCollection {
        let p = Polygonizer()
        for g in geoms { p.add(g) }
        return factory.createGeometryCollection(try NonFinite.scope { try p.getPolygons() })
    }
}
