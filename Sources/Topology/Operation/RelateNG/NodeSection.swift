/// The part of one geometry's edge at a node: the node, the vertices before
/// and after it (nil at a line's end), which geometry, the element's
/// dimension, its id and ring, its parent polygonal and whether the node is
/// a vertex of it: JTS's `NodeSection`.
struct NodeSection {
    let isA: Bool
    let dim: Int
    let id: Int
    let ringId: Int
    let poly: Geometry?
    let isNodeAtVertex: Bool
    let nodePt: Coordinate
    let v0: Coordinate?
    let v1: Coordinate?

    init(_ isA: Bool, _ dimension: Int, _ id: Int, _ ringId: Int, _ poly: Geometry?, _ isNodeAtVertex: Bool,
         _ v0: Coordinate?, _ nodePt: Coordinate, _ v1: Coordinate?) {
        self.isA = isA
        dim = dimension
        self.id = id
        self.ringId = ringId
        self.poly = poly
        self.isNodeAtVertex = isNodeAtVertex
        self.nodePt = nodePt
        self.v0 = v0
        self.v1 = v1
    }

    static func isAreaArea(_ a: NodeSection, _ b: NodeSection) -> Bool { a.dim == Dimension.a && b.dim == Dimension.a }
    static func isProper(_ a: NodeSection, _ b: NodeSection) -> Bool { a.isProper && b.isProper }

    func getVertex(_ i: Int) -> Coordinate? { i == 0 ? v0 : v1 }
    var isShell: Bool { ringId == 0 }
    var isArea: Bool { dim == Dimension.a }
    func isSameGeometry(_ ns: NodeSection) -> Bool { isA == ns.isA }
    func isSamePolygon(_ ns: NodeSection) -> Bool { isA == ns.isA && id == ns.id }
    var isProper: Bool { !isNodeAtVertex }

    /// By geometry (A first), dimension, id, ring, then the vertices.
    func compareTo(_ o: NodeSection) -> Int {
        if isA != o.isA { return isA ? -1 : 1 }
        if dim != o.dim { return dim < o.dim ? -1 : 1 }
        if id != o.id { return id < o.id ? -1 : 1 }
        if ringId != o.ringId { return ringId < o.ringId ? -1 : 1 }
        let compV0 = NodeSection.compareWithNull(v0, o.v0)
        if compV0 != 0 { return compV0 }
        return NodeSection.compareWithNull(v1, o.v1)
    }

    private static func compareWithNull(_ v0: Coordinate?, _ v1: Coordinate?) -> Int {
        guard let v0 else { return v1 == nil ? 0 : -1 }
        guard let v1 else { return 1 }
        return v0.compareTo(v1)
    }

    /// The order of sections by the angle of their first vertex.
    static func compareEdgeAngle(_ ns1: NodeSection, _ ns2: NodeSection) -> Int {
        PolygonNodeTopology.compareAngle(ns1.nodePt, ns1.getVertex(0)!, ns2.getVertex(0)!)
    }
}
