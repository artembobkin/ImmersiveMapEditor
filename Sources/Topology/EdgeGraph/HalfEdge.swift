/// A directed edge of a planar graph, paired with its opposite: JTS's
/// `HalfEdge`. The edges leaving a node are linked in a ring sorted by
/// angle, counter-clockwise from the positive x axis (`oNext`); `next` is
/// the edge after this one around the face to its left.
///
/// The links are unowned (unsafe): the graph that makes the edges keeps them
/// all alive as long as it is used, and following them costs no reference
/// counting. The graph still clears its edges' strong references when done
/// (`unlink`).
public class HalfEdge {
    public let orig: Coordinate
    @exclusivity(unchecked) public internal(set) unowned(unsafe) var sym: HalfEdge!
    @exclusivity(unchecked) public internal(set) unowned(unsafe) var next: HalfEdge!

    public init(_ orig: Coordinate) { self.orig = orig }

    /// Links this edge and `sym` as a pair.
    public func link(_ sym: HalfEdge) {
        self.sym = sym
        sym.sym = self
        next = sym
        sym.next = self
    }

    /// Clears the links, so the edges can be freed.
    func unlink() {
        sym = nil
        next = nil
    }

    public var dest: Coordinate { sym.orig }

    /// The point that gives the edge's direction: its other end, or a nearer
    /// vertex of a longer edge.
    public func directionPt() -> Coordinate { dest }

    final func directionX() -> Double { directionPt().x - orig.x }
    final func directionY() -> Double { directionPt().y - orig.y }

    /// The next edge counter-clockwise around the origin.
    public final func oNext() -> HalfEdge { sym.next }

    /// The edge whose `next` is this one.
    public final func prev() -> HalfEdge {
        var curr: HalfEdge = self
        var prev: HalfEdge = self
        repeat {
            prev = curr
            curr = curr.oNext()
        } while curr !== self
        return prev.sym
    }

    /// The edge from this origin to `dest`, if there is one.
    public final func find(_ dest: Coordinate) -> HalfEdge? {
        var oNext: HalfEdge = self
        repeat {
            if oNext.dest.equals2D(dest) { return oNext }
            oNext = oNext.oNext()
        } while oNext !== self
        return nil
    }

    /// Inserts an edge of the same origin in its place in the sorted ring.
    public final func insert(_ eAdd: HalfEdge) throws {
        if oNext() === self {
            insertAfter(eAdd)
            return
        }
        try insertionEdge(eAdd).insertAfter(eAdd)
    }

    private func insertionEdge(_ eAdd: HalfEdge) throws -> HalfEdge {
        var ePrev: HalfEdge = self
        repeat {
            let eNext = ePrev.oNext()
            // eAdd between ePrev and eNext, which is higher.
            if eNext.compareTo(ePrev) > 0 && eAdd.compareTo(ePrev) >= 0 && eAdd.compareTo(eNext) <= 0 { return ePrev }
            // The gap across the origin of the angles, eNext not higher than ePrev.
            if eNext.compareTo(ePrev) <= 0 && (eAdd.compareTo(eNext) <= 0 || eAdd.compareTo(ePrev) >= 0) { return ePrev }
            ePrev = eNext
        } while ePrev !== self
        throw Assert.shouldNeverReachHere()
    }

    private func insertAfter(_ e: HalfEdge) {
        let save = oNext()
        sym.next = e
        e.sym.next = save
    }

    /// The order of the edges around a node: by quadrant, then by orientation.
    public final func compareTo(_ e: HalfEdge) -> Int { compareAngularDirection(e) }

    public final func compareAngularDirection(_ e: HalfEdge) -> Int {
        let dx = directionX(), dy = directionY()
        let dx2 = e.directionX(), dy2 = e.directionY()
        if dx == dx2 && dy == dy2 { return 0 }
        let quadrant = Quadrant.quadrant(dx, dy)
        let quadrant2 = Quadrant.quadrant(dx2, dy2)
        if quadrant > quadrant2 { return 1 }
        if quadrant < quadrant2 { return -1 }
        return Orientation.index(e.orig, e.directionPt(), directionPt())
    }

    /// The number of edges leaving the origin.
    public final func degree() -> Int {
        var degree = 0
        var e: HalfEdge = self
        repeat {
            degree += 1
            e = e.oNext()
        } while e !== self
        return degree
    }

    /// The first node going back along the edges, past nodes of degree 2.
    public final func prevNode() -> HalfEdge? {
        var e: HalfEdge = self
        while e.degree() == 2 {
            e = e.prev()
            if e === self { return nil }
        }
        return e
    }
}
