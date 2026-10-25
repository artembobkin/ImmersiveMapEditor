/// An edge at a node of RelateNG, with the side and line locations of each
/// geometry: JTS's `RelateEdge`.
final class RelateEdge {
    static let dimUnknown = -1
    private static let locUnknown = Location.none

    unowned let node: RelateNode
    let dirPt: Coordinate
    @exclusivity(unchecked) private var aDim = RelateEdge.dimUnknown
    @exclusivity(unchecked) private var aLocLeft = RelateEdge.locUnknown
    @exclusivity(unchecked) private var aLocRight = RelateEdge.locUnknown
    @exclusivity(unchecked) private var aLocLine = RelateEdge.locUnknown
    @exclusivity(unchecked) private var bDim = RelateEdge.dimUnknown
    @exclusivity(unchecked) private var bLocLeft = RelateEdge.locUnknown
    @exclusivity(unchecked) private var bLocRight = RelateEdge.locUnknown
    @exclusivity(unchecked) private var bLocLine = RelateEdge.locUnknown

    static func create(_ node: RelateNode, _ dirPt: Coordinate, _ isA: Bool, _ dim: Int, _ isForward: Bool) -> RelateEdge {
        let e = RelateEdge(node, dirPt)
        if dim == Dimension.a { e.setLocationsArea(isA, isForward) } else { e.setLocationsLine(isA) }
        return e
    }

    static func findKnownEdgeIndex(_ edges: [RelateEdge], _ isA: Bool) -> Int {
        edges.firstIndex { $0.isKnown(isA) } ?? -1
    }

    static func setAreaInterior(_ edges: [RelateEdge], _ isA: Bool) {
        for e in edges { e.setAreaInterior(isA) }
    }

    private init(_ node: RelateNode, _ dirPt: Coordinate) {
        self.node = node
        self.dirPt = dirPt
    }

    private func setLocationsLine(_ isA: Bool) {
        if isA {
            aDim = 1; aLocLeft = Location.exterior; aLocRight = Location.exterior; aLocLine = Location.interior
        } else {
            bDim = 1; bLocLeft = Location.exterior; bLocRight = Location.exterior; bLocLine = Location.interior
        }
    }

    private func setLocationsArea(_ isA: Bool, _ isForward: Bool) {
        let locLeft = isForward ? Location.exterior : Location.interior
        let locRight = isForward ? Location.interior : Location.exterior
        if isA {
            aDim = 2; aLocLeft = locLeft; aLocRight = locRight; aLocLine = Location.boundary
        } else {
            bDim = 2; bLocLeft = locLeft; bLocRight = locRight; bLocLine = Location.boundary
        }
    }

    /// The angular order of this edge's direction against another one.
    func compareToEdge(_ edgeDirPt: Coordinate) -> Int {
        PolygonNodeTopology.compareAngle(node.nodePt, dirPt, edgeDirPt)
    }

    /// Takes in an edge of the same direction: an area wins over a line, an
    /// interior side stays interior.
    func merge(_ isA: Bool, _ dirPt: Coordinate, _ dim: Int, _ isForward: Bool) {
        var locEdge = Location.interior
        var locLeft = Location.exterior
        var locRight = Location.exterior
        if dim == Dimension.a {
            locEdge = Location.boundary
            locLeft = isForward ? Location.exterior : Location.interior
            locRight = isForward ? Location.interior : Location.exterior
        }
        if !isKnown(isA) {
            setDimension(isA, dim)
            setOn(isA, locEdge)
            setLeft(isA, locLeft)
            setRight(isA, locRight)
            return
        }
        mergeDimEdgeLoc(isA, locEdge)
        mergeSideLocation(isA, Position.left, locLeft)
        mergeSideLocation(isA, Position.right, locRight)
    }

    private func mergeDimEdgeLoc(_ isA: Bool, _ locEdge: Int) {
        let dim = locEdge == Location.boundary ? Dimension.a : Dimension.l
        if dim == Dimension.a && dimension(isA) == Dimension.l {
            setDimension(isA, dim)
            setOn(isA, Location.boundary)
        }
    }

    private func mergeSideLocation(_ isA: Bool, _ pos: Int, _ loc: Int) {
        if location(isA, pos) != Location.interior { setLocation(isA, pos, loc) }
    }

    private func setDimension(_ isA: Bool, _ dimension: Int) {
        if isA { aDim = dimension } else { bDim = dimension }
    }

    func setLocation(_ isA: Bool, _ pos: Int, _ loc: Int) {
        switch pos {
        case Position.left: setLeft(isA, loc)
        case Position.right: setRight(isA, loc)
        case Position.on: setOn(isA, loc)
        default: break
        }
    }

    func setUnknownLocations(_ isA: Bool, _ loc: Int) {
        if !isKnown(isA, Position.left) { setLocation(isA, Position.left, loc) }
        if !isKnown(isA, Position.right) { setLocation(isA, Position.right, loc) }
        if !isKnown(isA, Position.on) { setLocation(isA, Position.on, loc) }
    }

    private func setLeft(_ isA: Bool, _ loc: Int) { if isA { aLocLeft = loc } else { bLocLeft = loc } }
    private func setRight(_ isA: Bool, _ loc: Int) { if isA { aLocRight = loc } else { bLocRight = loc } }
    private func setOn(_ isA: Bool, _ loc: Int) { if isA { aLocLine = loc } else { bLocLine = loc } }

    func location(_ isA: Bool, _ position: Int) -> Int {
        switch (isA, position) {
        case (true, Position.left): return aLocLeft
        case (true, Position.right): return aLocRight
        case (true, Position.on): return aLocLine
        case (false, Position.left): return bLocLeft
        case (false, Position.right): return bLocRight
        case (false, Position.on): return bLocLine
        default: return RelateEdge.locUnknown
        }
    }

    private func dimension(_ isA: Bool) -> Int { isA ? aDim : bDim }
    private func isKnown(_ isA: Bool) -> Bool { (isA ? aDim : bDim) != RelateEdge.dimUnknown }
    private func isKnown(_ isA: Bool, _ pos: Int) -> Bool { location(isA, pos) != RelateEdge.locUnknown }

    func isInterior(_ isA: Bool, _ position: Int) -> Bool { location(isA, position) == Location.interior }

    func setAreaInterior(_ isA: Bool) {
        if isA {
            aLocLeft = Location.interior; aLocRight = Location.interior; aLocLine = Location.interior
        } else {
            bLocLeft = Location.interior; bLocRight = Location.interior; bLocLine = Location.interior
        }
    }
}
