/// A half-edge of the overlay graph: the edge's points (shared with its
/// pair, read forward or backward), its label, and what the result
/// building marks on it: JTS's `OverlayEdge`.
public final class OverlayEdge: HalfEdge {
    public let pts: [Coordinate]
    /// Whether this half-edge runs along `pts` (else against them).
    public let direction: Bool
    let dirPt: Coordinate
    public let label: OverlayLabel
    @exclusivity(unchecked) public private(set) var isInResultArea = false
    @exclusivity(unchecked) public private(set) var isInResultLine = false
    @exclusivity(unchecked) public private(set) var isVisited = false
    @exclusivity(unchecked) unowned(unsafe) var nextResultEdge: OverlayEdge?
    @exclusivity(unchecked) var edgeRing: OverlayEdgeRing?
    @exclusivity(unchecked) var maxEdgeRing: MaximalEdgeRing?
    @exclusivity(unchecked) unowned(unsafe) var nextResultMaxEdge: OverlayEdge?

    init(_ orig: Coordinate, _ dirPt: Coordinate, _ direction: Bool, _ label: OverlayLabel, _ pts: [Coordinate]) {
        self.dirPt = dirPt
        self.direction = direction
        self.pts = pts
        self.label = label
        super.init(orig)
    }

    static func createEdge(_ pts: [Coordinate], _ lbl: OverlayLabel, _ direction: Bool) -> OverlayEdge {
        if direction { return OverlayEdge(pts[0], pts[1], direction, lbl, pts) }
        let ilast = pts.count - 1
        return OverlayEdge(pts[ilast], pts[ilast - 1], direction, lbl, pts)
    }

    /// Both edges of the pair, linked: the caller keeps both (the links
    /// are unowned).
    static func createEdgePair(_ pts: [Coordinate], _ lbl: OverlayLabel) -> (OverlayEdge, OverlayEdge) {
        let e0 = createEdge(pts, lbl, true)
        let e1 = createEdge(pts, lbl, false)
        e0.link(e1)
        return (e0, e1)
    }

    override func unlink() {
        super.unlink()
        nextResultEdge = nil
        edgeRing = nil
        maxEdgeRing = nil
        nextResultMaxEdge = nil
    }

    public var isForward: Bool { direction }
    override public func directionPt() -> Coordinate { dirPt }
    public func getLocation(_ index: Int, _ position: Int) -> Int { label.getLocation(index, position, direction) }
    public var coordinate: Coordinate { orig }

    public func getCoordinatesOriented() -> [Coordinate] { direction ? pts : pts.reversed() }

    /// Adds the edge's points in its direction, without the first when the
    /// list already has points (it ends where this edge starts).
    public func addCoordinates(_ coords: inout CoordinateList) {
        let isFirstEdge = coords.count > 0
        if direction {
            for i in (isFirstEdge ? 0 : 1)..<pts.count { coords.add(pts[i], false) }
        } else {
            var i = isFirstEdge ? pts.count - 1 : pts.count - 2
            while i >= 0 {
                coords.add(pts[i], false)
                i -= 1
            }
        }
    }

    public var symOE: OverlayEdge { unsafeDowncast(sym, to: OverlayEdge.self) }
    public var oNextOE: OverlayEdge { unsafeDowncast(oNext(), to: OverlayEdge.self) }

    public var isInResultAreaBoth: Bool { isInResultArea && symOE.isInResultArea }

    public func unmarkFromResultAreaBoth() {
        isInResultArea = false
        symOE.isInResultArea = false
    }

    public func markInResultArea() { isInResultArea = true }

    public func markInResultAreaBoth() {
        isInResultArea = true
        symOE.isInResultArea = true
    }

    public func markInResultLine() {
        isInResultLine = true
        symOE.isInResultLine = true
    }

    public var isInResult: Bool { isInResultArea || isInResultLine }
    public var isInResultEither: Bool { isInResult || symOE.isInResult }

    func setNextResult(_ e: OverlayEdge) { nextResultEdge = e }
    public var nextResult: OverlayEdge? { nextResultEdge }
    public var isResultLinked: Bool { nextResultEdge != nil }
    func setNextResultMax(_ e: OverlayEdge) { nextResultMaxEdge = e }
    public var nextResultMax: OverlayEdge? { nextResultMaxEdge }
    public var isResultMaxLinked: Bool { nextResultMaxEdge != nil }

    public func markVisitedBoth() {
        isVisited = true
        symOE.isVisited = true
    }
}
