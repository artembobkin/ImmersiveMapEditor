/// A triangle of a triangulation, with its neighbours across its edges:
/// JTS's `Tri`. Edge `i` runs from vertex `i` to vertex `i + 1`; the
/// neighbour across it is `getAdjacent(i)`. Triangles are classes (their
/// adjacency is by identity), kept alive by the list that holds them.
final class Tri {
    @exclusivity(unchecked) var p0: Coordinate
    @exclusivity(unchecked) var p1: Coordinate
    @exclusivity(unchecked) var p2: Coordinate
    @exclusivity(unchecked) unowned(unsafe) var tri0: Tri?
    @exclusivity(unchecked) unowned(unsafe) var tri1: Tri?
    @exclusivity(unchecked) unowned(unsafe) var tri2: Tri?

    init(_ p0: Coordinate, _ p1: Coordinate, _ p2: Coordinate) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
    }

    static func next(_ index: Int) -> Int {
        switch index {
        case 0: return 1
        case 1: return 2
        case 2: return 0
        default: return -1
        }
    }

    static func prev(_ index: Int) -> Int {
        switch index {
        case 0: return 2
        case 1: return 0
        case 2: return 1
        default: return -1
        }
    }

    static func oppVertex(_ edgeIndex: Int) -> Int { prev(edgeIndex) }

    func setAdjacent(_ tri0: Tri?, _ tri1: Tri?, _ tri2: Tri?) {
        self.tri0 = tri0
        self.tri1 = tri1
        self.tri2 = tri2
    }

    func setAdjacent(_ pt: Coordinate, _ tri: Tri?) throws { try setTri(getIndex(pt), tri) }

    func setTri(_ edgeIndex: Int, _ tri: Tri?) throws {
        switch edgeIndex {
        case 0: tri0 = tri
        case 1: tri1 = tri
        case 2: tri2 = tri
        default: throw IllegalArgumentException("Tri::setTri - invalid index")
        }
    }

    func getCoordinate(_ i: Int) -> Coordinate {
        switch i {
        case 0: return p0
        case 1: return p1
        default: return p2
        }
    }

    func getIndex(_ p: Coordinate) -> Int {
        if p0.equals2D(p) { return 0 }
        if p1.equals2D(p) { return 1 }
        if p2.equals2D(p) { return 2 }
        return -1
    }

    func getIndex(_ tri: Tri) -> Int {
        if tri0 === tri { return 0 }
        if tri1 === tri { return 1 }
        if tri2 === tri { return 2 }
        return -1
    }

    func getAdjacent(_ i: Int) -> Tri? {
        switch i {
        case 0: return tri0
        case 1: return tri1
        default: return tri2
        }
    }

    /// Flips the edge `index` with the neighbour across it: the two
    /// triangles take the other diagonal of their quadrilateral.
    func flip(_ index: Int) {
        let tri = getAdjacent(index)!
        let index1 = tri.getIndex(self)
        let adj0 = getCoordinate(index)
        let adj1 = getCoordinate(Tri.next(index))
        let opp0 = getCoordinate(Tri.oppVertex(index))
        let opp1 = tri.getCoordinate(Tri.oppVertex(index1))
        p0 = opp1; p1 = opp0; p2 = adj0
        tri.p0 = opp0; tri.p1 = opp1; tri.p2 = adj1
        let a0 = getAdjacent(Tri.prev(index))
        let a1 = getAdjacent(Tri.next(index))
        let a2 = tri.getAdjacent(Tri.next(index1))
        let a3 = tri.getAdjacent(Tri.prev(index1))
        setAdjacent(tri, a0, a2)
        a2?.replace(tri, self)
        tri.setAdjacent(self, a3, a1)
        a1?.replace(self, tri)
    }

    private func replace(_ triOld: Tri, _ triNew: Tri) {
        if tri0 != nil && tri0 === triOld {
            tri0 = triNew
        } else if tri1 != nil && tri1 === triOld {
            tri1 = triNew
        } else if tri2 != nil && tri2 === triOld {
            tri2 = triNew
        }
    }

    func toPolygon(_ factory: GeometryFactory) -> Polygon {
        factory.createPolygon(factory.createLinearRing([p0, p1, p2, p0]))
    }
}

/// An edge between two vertices, either way: JTS's `TriEdge`, the key of
/// the triangulation builder.
struct TriEdge: Hashable {
    let p0: Coordinate
    let p1: Coordinate

    init(_ a: Coordinate, _ b: Coordinate) {
        if a.compareTo(b) < 0 {
            p0 = b
            p1 = a
        } else {
            p0 = a
            p1 = b
        }
    }
}

/// Links each triangle of a list to the triangles sharing its edges: JTS's
/// `TriangulationBuilder`. Only lookups are made, so the map's order does
/// not matter; an edge already in it keeps its first triangle (GEOS's
/// `emplace`).
enum TriangulationBuilder {
    static func build(_ triList: [Tri]) throws {
        var triMap: [TriEdge: Tri] = [:]
        func addAdjacent(_ tri: Tri, _ adj: Tri?, _ p0: Coordinate, _ p1: Coordinate) throws {
            guard let adj else {
                let key = TriEdge(p0, p1)
                if triMap[key] == nil { triMap[key] = tri }
                return
            }
            try adj.setAdjacent(p1, tri)
        }
        for tri in triList {
            let p0 = tri.p0, p1 = tri.p1, p2 = tri.p2
            let n0 = triMap[TriEdge(p0, p1)]
            let n1 = triMap[TriEdge(p1, p2)]
            let n2 = triMap[TriEdge(p2, p0)]
            tri.setAdjacent(n0, n1, n2)
            try addAdjacent(tri, n0, p0, p1)
            try addAdjacent(tri, n1, p1, p2)
            try addAdjacent(tri, n2, p2, p0)
        }
    }
}
