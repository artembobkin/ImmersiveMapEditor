/// The raw offset curves of every component of a geometry, each labelled
/// with the locations on its left and right, for the buffer to node: JTS's
/// `BufferCurveSetBuilder`.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: a shell is
/// tested for complete erosion before its repeated points are removed, a
/// shell with no valid point fails, and the test of an inverted ring curve
/// looks at every vertex of the curve, its closing one too.
final class BufferCurveSetBuilder {
    private static let maxInvertedRingSize = 9
    private static let invertedCurveVertexFactor = 4
    private static let nearnessFactor = 0.99

    private let inputGeom: Geometry
    private let distance: Double
    private let curveBuilder: OffsetCurveBuilder
    @exclusivity(unchecked) private var curveList: [SegmentString] = []
    @exclusivity(unchecked) var isInvertOrientation = false

    init(_ inputGeom: Geometry, _ distance: Double, _ precisionModel: PrecisionModel, _ bufParams: BufferParameters) {
        self.inputGeom = inputGeom
        self.distance = distance
        curveBuilder = OffsetCurveBuilder(precisionModel, bufParams)
    }

    /// The curves, each a `NodedSegmentString` whose data is its label.
    func getCurves() throws -> [SegmentString] {
        try add(inputGeom)
        return curveList
    }

    private func isRingCCW(_ coord: [Coordinate]) -> Bool {
        let isCCW = Orientation.isCCWArea(coord)
        return isInvertOrientation ? !isCCW : isCCW
    }

    private func addCurve(_ coord: [Coordinate]?, _ leftLoc: Int, _ rightLoc: Int) {
        guard let coord, coord.count >= 2 else { return }
        curveList.append(NodedSegmentString(coord, GeomGraph.Label(0, Location.boundary, leftLoc, rightLoc)))
    }

    private func add(_ g: Geometry) throws {
        if g.isEmpty() { return }
        if let p = g as? Polygon {
            try addPolygon(p)
        } else if let l = g as? LineString {
            addLineString(l)
        } else if let p = g as? Point {
            addPoint(p)
        } else if let gc = g as? GeometryCollection {
            for i in 0..<gc.getNumGeometries() { try add(gc.getGeometryN(i)) }
        }
    }

    private func addPoint(_ p: Point) {
        if distance <= 0.0 { return }
        let coord = p.getCoordinates()
        if coord.count >= 1 && !BufferCurveSetBuilder.isValid(coord[0]) { return }
        addCurve(curveBuilder.getLineCurve(coord, distance), Location.exterior, Location.interior)
    }

    private func addLineString(_ line: LineString) {
        if curveBuilder.isLineOffsetEmpty(distance) { return }
        let coord = BufferCurveSetBuilder.clean(line.points)
        if CoordinateSequences.isRing(coord) {
            addRingBothSides(coord, distance)
        } else {
            addCurve(curveBuilder.getLineCurve(coord, distance), Location.exterior, Location.interior)
        }
    }

    /// The points without repeats and without invalid (infinite or NaN)
    /// ones: GEOS's `RepeatedPointRemover::removeRepeatedAndInvalidPoints`.
    static func clean(_ coords: [Coordinate]) -> [Coordinate] {
        var out: [Coordinate] = []
        out.reserveCapacity(coords.count)
        for c in coords {
            let invalid = !isValid(c)
            if let last = out.last {
                let dx = c.x - last.x, dy = c.y - last.y
                if invalid || c.equals2D(last) || fusedAdd(dx, dx, dy * dy) <= 0.0 { continue }
            } else if invalid {
                continue
            }
            out.append(c)
        }
        return out
    }

    static func isValid(_ c: Coordinate) -> Bool { c.x.isFinite && c.y.isFinite }

    private func addPolygon(_ p: Polygon) throws {
        var offsetDistance = distance
        var offsetSide = Position.left
        if distance < 0.0 {
            offsetDistance = -distance
            offsetSide = Position.right
        }
        let shell = p.shell
        if distance < 0.0 && BufferCurveSetBuilder.isErodedCompletely(shell, distance) { return }
        let shellCoord = BufferCurveSetBuilder.clean(shell.points)
        if shellCoord.isEmpty { throw IllegalArgumentException("Shell empty after removing invalid points") }
        if distance <= 0.0 && shellCoord.count < 3 { return }
        addRingSide(shellCoord, offsetDistance, offsetSide, Location.exterior, Location.interior)
        for hole in p.holes {
            // A hole wholly eroded by a positive buffer leaves nothing.
            if distance > 0.0 && BufferCurveSetBuilder.isErodedCompletely(hole, -distance) { continue }
            let holeCoord = BufferCurveSetBuilder.clean(hole.points)
            addRingSide(holeCoord, offsetDistance, Position.opposite(offsetSide), Location.interior, Location.exterior)
        }
    }

    private func addRingBothSides(_ coord: [Coordinate], _ distance: Double) {
        addRingSide(coord, distance, Position.left, Location.exterior, Location.interior)
        addRingSide(coord, distance, Position.right, Location.interior, Location.exterior)
    }

    /// The curve on one side of a ring, labelled as for a clockwise ring
    /// and flipped for a counter-clockwise one.
    private func addRingSide(_ coord: [Coordinate], _ offsetDistance: Double, _ sideIn: Int, _ cwLeftLoc: Int, _ cwRightLoc: Int) {
        if offsetDistance == 0.0 && coord.count < LinearRing.minimumValidRingSize { return }
        var side = sideIn
        var leftLoc = cwLeftLoc
        var rightLoc = cwRightLoc
        let isCCW = isRingCCW(coord)
        if coord.count >= LinearRing.minimumValidRingSize && isCCW {
            leftLoc = cwRightLoc
            rightLoc = cwLeftLoc
            side = Position.opposite(side)
        }
        guard let curve = curveBuilder.getRingCurve(coord, side, offsetDistance) else { return }
        if BufferCurveSetBuilder.isRingCurveInverted(coord, offsetDistance, curve) { return }
        addCurve(curve, leftLoc, rightLoc)
    }

    /// Whether the curve of a small ring with a large negative offset has
    /// turned inside out: none of it lies at the distance from the ring.
    private static func isRingCurveInverted(_ inputRing: [Coordinate], _ distance: Double, _ curveRing: [Coordinate]) -> Bool {
        if distance == 0.0 { return false }
        if inputRing.count <= 3 { return false }
        if inputRing.count >= maxInvertedRingSize { return false }
        if curveRing.count > invertedCurveVertexFactor * inputRing.count { return false }
        if hasPointOnBuffer(inputRing, distance, curveRing) { return false }
        return true
    }

    private static func hasPointOnBuffer(_ inputRing: [Coordinate], _ distance: Double, _ curveRing: [Coordinate]) -> Bool {
        let distTol = nearnessFactor * abs(distance)
        for i in curveRing.indices {
            let v = curveRing[i]
            if Distance.pointToSegmentString(v, inputRing) > distTol { return true }
            let iNext = i < curveRing.count - 1 ? i + 1 : 0
            let midPt = LineSegment.midPoint(v, curveRing[iNext])
            if Distance.pointToSegmentString(midPt, inputRing) > distTol { return true }
        }
        return false
    }

    /// Whether a negative buffer leaves nothing of a ring: a triangle by its
    /// in-centre, any other ring by its envelope.
    private static func isErodedCompletely(_ ring: LinearRing, _ bufferDistance: Double) -> Bool {
        let ringCoord = ring.points
        if ringCoord.count < 4 { return bufferDistance < 0 }
        if ringCoord.count == 4 { return isTriangleErodedCompletely(ringCoord, bufferDistance) }
        let env = ring.getEnvelopeInternal()
        let envMinDimension = cxxMin(env.height, env.width)
        return bufferDistance < 0.0 && 2 * abs(bufferDistance) > envMinDimension
    }

    private static func isTriangleErodedCompletely(_ triangleCoord: [Coordinate], _ bufferDistance: Double) -> Bool {
        let tri = Triangle(triangleCoord[0], triangleCoord[1], triangleCoord[2])
        let inCentre = tri.inCentre()
        let distToCentre = Distance.pointToSegment(inCentre, tri.p0, tri.p1)
        return distToCentre < abs(bufferDistance)
    }
}
