/// A minimal ring of result edges, a shell (clockwise) or a hole
/// (counter-clockwise), with the holes it holds: JTS's `OverlayEdgeRing`.
final class OverlayEdgeRing {
    unowned(unsafe) let startEdge: OverlayEdge
    private(set) var ring: LinearRing!
    private(set) var isHole = false
    private var ringPts: [Coordinate] = []
    private var locator: IndexedPointInAreaLocator?
    private(set) weak var shell: OverlayEdgeRing?
    private(set) var holes: [OverlayEdgeRing] = []

    init(_ start: OverlayEdge, _ factory: GeometryFactory) throws {
        startEdge = start
        var pts = CoordinateList()
        var edge = start
        repeat {
            if edge.edgeRing === self {
                throw TopologyException("Edge visited twice during ring-building at \(edge.coordinate)", edge.coordinate)
            }
            edge.addCoordinates(&pts)
            edge.edgeRing = self
            guard let next = edge.nextResult else { throw TopologyException("Found null edge in ring", edge.dest) }
            edge = next
        } while edge !== start
        pts.closeRing()
        ringPts = pts.points
        ring = try factory.createLinearRingChecked(ringPts)
        isHole = Orientation.isCCW(ring.points)
    }

    var envelope: Envelope { ring.getEnvelopeInternal() }

    func setShell(_ shell: OverlayEdgeRing?) {
        self.shell = shell
        shell?.holes.append(self)
    }

    var hasShell: Bool { shell != nil }

    /// The shell of a hole, a shell itself.
    func getShell() -> OverlayEdgeRing? { isHole ? shell : self }

    var coordinate: Coordinate { ringPts[0] }

    /// The smallest ring of the list holding this one.
    func findEdgeRingContaining(_ erList: [OverlayEdgeRing]) -> OverlayEdgeRing? {
        var minContainingRing: OverlayEdgeRing?
        for edgeRing in erList where edgeRing.contains(self) {
            if minContainingRing == nil || minContainingRing!.envelope.contains(edgeRing.envelope) {
                minContainingRing = edgeRing
            }
        }
        return minContainingRing
    }

    func locate(_ pt: Coordinate) -> Int {
        if locator == nil { locator = IndexedPointInAreaLocator(ring) }
        return locator!.locate(pt)
    }

    private func contains(_ ring: OverlayEdgeRing) -> Bool {
        if !envelope.containsProperly(ring.envelope) { return false }
        return isPointInOrOut(ring)
    }

    /// Whether the first vertex of `ring` that is not on this ring is inside it.
    private func isPointInOrOut(_ ring: OverlayEdgeRing) -> Bool {
        for pt in ring.ringPts {
            let loc = locate(pt)
            if loc == Location.interior { return true }
            if loc == Location.exterior { return false }
        }
        return false
    }

    func toPolygon(_ factory: GeometryFactory) -> Polygon {
        factory.createPolygon(ring, holes.map(\.ring))
    }
}
