/// A minimal ring of result edges, a shell (clockwise) or a hole
/// (counter-clockwise), with the holes it holds: JTS's `OverlayEdgeRing`.
final class OverlayEdgeRing {
    unowned(unsafe) let startEdge: OverlayEdge
    @exclusivity(unchecked) private(set) var ring: LinearRing!
    @exclusivity(unchecked) private(set) var isHole = false
    @exclusivity(unchecked) private var ringPts: [Coordinate] = []
    @exclusivity(unchecked) private var locator: IndexedPointInAreaLocator?
    @exclusivity(unchecked) private(set) weak var shell: OverlayEdgeRing?
    @exclusivity(unchecked) private(set) var holes: [OverlayEdgeRing] = []

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

    /// The smallest ring of the list holding this one, as GEOS 3.13 finds it
    /// (JTS 1.20 tests a proper envelope containment and the first vertex
    /// off the ring, inside or out): a ring of the same envelope is passed
    /// over, the envelope must contain this one's, and this ring's first
    /// vertex not on the other (a null coordinate when there is none) must
    /// not be outside it.
    func findEdgeRingContaining(_ erList: [OverlayEdgeRing]) -> OverlayEdgeRing? {
        let testEnv = envelope
        var minRing: OverlayEdgeRing?
        for tryEdgeRing in erList {
            let tryShellEnv = tryEdgeRing.envelope
            if OverlayEdgeRing.equals(tryShellEnv, testEnv) { continue }
            if !tryShellEnv.contains(testEnv) { continue }
            let testPt = CoordinateArrays.ptNotInList(ringPts, tryEdgeRing.ringPts) ?? Coordinate.null
            if tryEdgeRing.locate(testPt) != Location.exterior {
                if minRing == nil || minRing!.envelope.contains(tryShellEnv) { minRing = tryEdgeRing }
            }
        }
        return minRing
    }

    /// GEOS's `Envelope::equals`: null equals null, else every side equal.
    private static func equals(_ a: Envelope, _ b: Envelope) -> Bool {
        if a.isNull { return b.isNull }
        return b.minX == a.minX && b.maxX == a.maxX && b.minY == a.minY && b.maxY == a.maxY
    }

    func locate(_ pt: Coordinate) -> Int {
        if locator == nil { locator = IndexedPointInAreaLocator(ring) }
        return locator!.locate(pt)
    }

    func toPolygon(_ factory: GeometryFactory) -> Polygon {
        factory.createPolygon(ring, holes.map(\.ring))
    }
}
