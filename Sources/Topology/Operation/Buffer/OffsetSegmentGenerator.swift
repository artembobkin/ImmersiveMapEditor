import Darwin

/// The points of an offset curve as they are generated, each made precise
/// and dropped when it is within a small distance of the last: JTS's
/// `OffsetSegmentString`. As in GEOS 3.13, the coordinates are taken with
/// the ring closed.
final class OffsetSegmentString {
    @exclusivity(unchecked) private(set) var ptList: [Coordinate] = []
    @exclusivity(unchecked) var precisionModel: PrecisionModel = .floating
    @exclusivity(unchecked) var minimumVertexDistance = 0.0

    func addPt(_ pt: Coordinate) {
        let bufPt = precisionModel.makePrecise(pt)
        if isRedundant(bufPt) { return }
        ptList.append(bufPt)
    }

    func addPts(_ pts: [Coordinate], _ isForward: Bool) {
        if isForward {
            for p in pts { addPt(p) }
        } else {
            for p in pts.reversed() { addPt(p) }
        }
    }

    private func isRedundant(_ pt: Coordinate) -> Bool {
        guard let lastPt = ptList.last else { return false }
        return pt.distance(lastPt) < minimumVertexDistance
    }

    func closeRing() {
        guard let startPt = ptList.first else { return }
        if startPt.equals2D(ptList[ptList.count - 1]) { return }
        ptList.append(startPt)
    }

    func getCoordinates() -> [Coordinate] {
        closeRing()
        return ptList
    }
}

/// Generates the segments of an offset curve along a line, with the joins
/// between them and the end caps: JTS's `OffsetSegmentGenerator`.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS:
/// - a segment is not offset again when its next point repeats its end
///   (JTS moves on and stops after);
/// - at an outside turn whose offsets nearly meet (closer than 1e-3 of the
///   distance, JTS 0.05) the end of the first offset is taken (JTS: the end
///   of the longer segment's offset);
/// - a limited mitre join is built from the bisector's outward direction
///   (the same bevel as JTS's, reached from the other side);
/// - the offset of a segment divides by `sqrt(dx * dx + dy * dy)` (JTS:
///   `hypot`), and sums of products are fused as GEOS's compiler fuses them
///   (`Fused.swift`).
final class OffsetSegmentGenerator {
    private static let offsetSegmentSeparationFactor = 1.0e-3
    private static let insideTurnVertexSnapDistanceFactor = 1.0e-3
    private static let curveVertexSnapDistanceFactor = 1.0e-6
    private static let maxClosingSegLenFactor = 80

    @exclusivity(unchecked) private var filletAngleQuantum: Double
    @exclusivity(unchecked) private var closingSegLengthFactor = 1
    let segList = OffsetSegmentString()
    @exclusivity(unchecked) private var distance = 0.0
    private let precisionModel: PrecisionModel
    private let bufParams: BufferParameters
    @exclusivity(unchecked) private var li = RobustLineIntersector()
    @exclusivity(unchecked) private var s0 = Coordinate(0, 0), s1 = Coordinate(0, 0), s2 = Coordinate(0, 0)
    @exclusivity(unchecked) private var seg0 = LineSegment(), seg1 = LineSegment()
    @exclusivity(unchecked) private var offset0 = LineSegment(), offset1 = LineSegment()
    @exclusivity(unchecked) private var side = 0

    init(_ precisionModel: PrecisionModel, _ bufParams: BufferParameters, _ distance: Double) {
        self.precisionModel = precisionModel
        self.bufParams = bufParams
        var quadSegs = bufParams.quadrantSegments
        if quadSegs < 1 { quadSegs = 1 }
        filletAngleQuantum = Angle.piOver2 / Double(quadSegs)
        if bufParams.quadrantSegments >= 8 && bufParams.joinStyle == BufferParameters.joinRound {
            closingSegLengthFactor = OffsetSegmentGenerator.maxClosingSegLenFactor
        }
        self.distance = distance
        segList.precisionModel = precisionModel
        segList.minimumVertexDistance = distance * OffsetSegmentGenerator.curveVertexSnapDistanceFactor
    }

    func initSideSegments(_ s1: Coordinate, _ s2: Coordinate, _ side: Int) {
        self.s1 = s1
        self.s2 = s2
        self.side = side
        seg1 = LineSegment(s1, s2)
        offset1 = OffsetSegmentGenerator.computeOffsetSegment(seg1, side, distance)
    }

    func getCoordinates() -> [Coordinate] { segList.getCoordinates() }

    func closeRing() { segList.closeRing() }

    func addSegments(_ pts: [Coordinate], _ isForward: Bool) { segList.addPts(pts, isForward) }

    func addFirstSegment() { segList.addPt(offset1.p0) }

    func addLastSegment() { segList.addPt(offset1.p1) }

    /// Adds the next segment, ending at `p`, with the join at its start.
    func addNextSegment(_ p: Coordinate, _ addStartPoint: Bool) {
        if s2 == p { return }
        s0 = s1
        s1 = s2
        s2 = p
        seg0 = LineSegment(s0, s1)
        offset0 = OffsetSegmentGenerator.computeOffsetSegment(seg0, side, distance)
        seg1 = LineSegment(s1, s2)
        offset1 = OffsetSegmentGenerator.computeOffsetSegment(seg1, side, distance)
        let orientation = Orientation.index(s0, s1, s2)
        let outsideTurn = (orientation == Orientation.clockwise && side == Position.left)
            || (orientation == Orientation.counterclockwise && side == Position.right)
        if orientation == 0 {
            addCollinear(addStartPoint)
        } else if outsideTurn {
            addOutsideTurn(orientation, addStartPoint)
        } else {
            addInsideTurn()
        }
    }

    private func addCollinear(_ addStartPoint: Bool) {
        // The segments are collinear: a join only where they double back.
        li.computeIntersection(s0, s1, s1, s2)
        if li.getIntersectionNum() >= 2 {
            if bufParams.joinStyle == BufferParameters.joinBevel || bufParams.joinStyle == BufferParameters.joinMitre {
                if addStartPoint { segList.addPt(offset0.p1) }
                segList.addPt(offset1.p0)
            } else {
                addCornerFillet(s1, offset0.p1, offset1.p0, Orientation.clockwise, distance)
            }
        }
    }

    private func addOutsideTurn(_ orientation: Int, _ addStartPoint: Bool) {
        if offset0.p1.distance(offset1.p0) < distance * OffsetSegmentGenerator.offsetSegmentSeparationFactor {
            segList.addPt(offset0.p1)
            return
        }
        if bufParams.joinStyle == BufferParameters.joinMitre {
            addMitreJoin(s1, offset0, offset1, distance)
        } else if bufParams.joinStyle == BufferParameters.joinBevel {
            addBevelJoin(offset0, offset1)
        } else {
            if addStartPoint { segList.addPt(offset0.p1) }
            addCornerFillet(s1, offset0.p1, offset1.p0, orientation, distance)
            segList.addPt(offset1.p0)
        }
    }

    private func addInsideTurn() {
        li.computeIntersection(offset0.p0, offset0.p1, offset1.p0, offset1.p1)
        if li.hasIntersection() {
            segList.addPt(li.getIntersection(0))
            return
        }
        // The offsets do not meet (a narrow concave angle): close the gap
        // through points near the corner, so the curve stays well formed.
        if offset0.p1.distance(offset1.p0) < distance * OffsetSegmentGenerator.insideTurnVertexSnapDistanceFactor {
            segList.addPt(offset0.p1)
        } else {
            segList.addPt(offset0.p1)
            if closingSegLengthFactor > 0 {
                let f = Double(closingSegLengthFactor), f1 = Double(closingSegLengthFactor + 1)
                segList.addPt(Coordinate(fusedAdd(f, offset0.p1.x, s1.x) / f1, fusedAdd(f, offset0.p1.y, s1.y) / f1))
                segList.addPt(Coordinate(fusedAdd(f, offset1.p0.x, s1.x) / f1, fusedAdd(f, offset1.p0.y, s1.y) / f1))
            } else {
                segList.addPt(s1)
            }
            segList.addPt(offset1.p0)
        }
    }

    /// The segment moved by `distance` to one side.
    static func computeOffsetSegment(_ seg: LineSegment, _ side: Int, _ distance: Double) -> LineSegment {
        let sideSign = side == Position.left ? 1.0 : -1.0
        let dx = seg.p1.x - seg.p0.x
        let dy = seg.p1.y - seg.p0.y
        let len = fusedAdd(dx, dx, dy * dy).squareRoot()
        let ux = sideSign * distance * dx / len
        let uy = sideSign * distance * dy / len
        return LineSegment(Coordinate(seg.p0.x - uy, seg.p0.y + ux), Coordinate(seg.p1.x - uy, seg.p1.y + ux))
    }

    /// The cap at the end of a line, from `p0` to `p1`.
    func addLineEndCap(_ p0: Coordinate, _ p1: Coordinate) {
        let seg = LineSegment(p0, p1)
        let offsetL = OffsetSegmentGenerator.computeOffsetSegment(seg, Position.left, distance)
        let offsetR = OffsetSegmentGenerator.computeOffsetSegment(seg, Position.right, distance)
        let angle = atan2(p1.y - p0.y, p1.x - p0.x)
        switch bufParams.endCapStyle {
        case BufferParameters.capRound:
            segList.addPt(offsetL.p1)
            addDirectedFillet(p1, angle + Angle.piOver2, angle - Angle.piOver2, Orientation.clockwise, distance)
            segList.addPt(offsetR.p1)
        case BufferParameters.capFlat:
            segList.addPt(offsetL.p1)
            segList.addPt(offsetR.p1)
        case BufferParameters.capSquare:
            let sideX = abs(distance) * Angle.cosSnap(angle)
            let sideY = abs(distance) * Angle.sinSnap(angle)
            segList.addPt(Coordinate(offsetL.p1.x + sideX, offsetL.p1.y + sideY))
            segList.addPt(Coordinate(offsetR.p1.x + sideX, offsetR.p1.y + sideY))
        default:
            break
        }
    }

    private func addMitreJoin(_ cornerPt: Coordinate, _ offset0: LineSegment, _ offset1: LineSegment, _ distance: Double) {
        let mitreLimitDistance = bufParams.mitreLimit * distance
        if let intPt = Intersection.intersection(offset0.p0, offset0.p1, offset1.p0, offset1.p1),
           intPt.distance(cornerPt) <= mitreLimitDistance {
            segList.addPt(intPt)
            return
        }
        let bevelDist = Distance.pointToSegment(cornerPt, offset0.p1, offset1.p0)
        if bevelDist >= mitreLimitDistance {
            addBevelJoin(offset0, offset1)
            return
        }
        addLimitedMitreJoin(offset0, offset1, distance, mitreLimitDistance)
    }

    /// A mitre cut square to the bisector at the mitre limit.
    private func addLimitedMitreJoin(_ offset0: LineSegment, _ offset1: LineSegment, _ distance: Double, _ mitreLimitDistance: Double) {
        let cornerPt = seg0.p1
        let angInterior = Angle.angleBetweenOriented(seg0.p0, cornerPt, seg1.p1)
        let angInterior2 = angInterior / 2.0
        let dir0 = Angle.angle(cornerPt, seg0.p0)
        let dirBisector = Angle.normalize(dir0 + angInterior2)
        let dirBisectorOut = Angle.normalize(dirBisector + Double.pi)
        let bevelMidPt = OffsetSegmentGenerator.project(cornerPt, mitreLimitDistance, dirBisectorOut)
        let dirBevel = Angle.normalize(dirBisectorOut + Angle.piOver2)
        let bevel0 = OffsetSegmentGenerator.project(bevelMidPt, distance, dirBevel)
        let bevel1 = OffsetSegmentGenerator.project(bevelMidPt, distance, dirBevel + Double.pi)
        if let bevelInt0 = Intersection.lineSegment(offset0.p0, offset0.p1, bevel0, bevel1),
           let bevelInt1 = Intersection.lineSegment(offset1.p0, offset1.p1, bevel0, bevel1) {
            segList.addPt(bevelInt0)
            segList.addPt(bevelInt1)
            return
        }
        addBevelJoin(offset0, offset1)
    }

    private static func project(_ pt: Coordinate, _ d: Double, _ dir: Double) -> Coordinate {
        Coordinate(fusedAdd(d, Angle.cosSnap(dir), pt.x), fusedAdd(d, Angle.sinSnap(dir), pt.y))
    }

    private func addBevelJoin(_ offset0: LineSegment, _ offset1: LineSegment) {
        segList.addPt(offset0.p1)
        segList.addPt(offset1.p0)
    }

    /// The arc around `p` from `p0` to `p1`, the ends included.
    private func addCornerFillet(_ p: Coordinate, _ p0: Coordinate, _ p1: Coordinate, _ direction: Int, _ radius: Double) {
        var startAngle = atan2(p0.y - p.y, p0.x - p.x)
        let endAngle = atan2(p1.y - p.y, p1.x - p.x)
        if direction == Orientation.clockwise {
            if startAngle <= endAngle { startAngle += Angle.piTimes2 }
        } else {
            if startAngle >= endAngle { startAngle -= Angle.piTimes2 }
        }
        segList.addPt(p0)
        addDirectedFillet(p, startAngle, endAngle, direction, radius)
        segList.addPt(p1)
    }

    /// The points of an arc around `p`, from its start angle and short of
    /// its end, in steps of about the fillet angle.
    private func addDirectedFillet(_ p: Coordinate, _ startAngle: Double, _ endAngle: Double, _ direction: Int, _ radius: Double) {
        let directionFactor = direction == Orientation.clockwise ? -1 : 1
        let totalAngle = abs(startAngle - endAngle)
        let nSegs = Int(totalAngle / filletAngleQuantum + 0.5)
        if nSegs < 1 { return }
        let angleInc = totalAngle / Double(nSegs)
        for i in 0..<nSegs {
            let angle = fusedAdd(Double(directionFactor * i), angleInc, startAngle)
            segList.addPt(Coordinate(fusedAdd(radius, Angle.cosSnap(angle), p.x), fusedAdd(radius, Angle.sinSnap(angle), p.y)))
        }
    }

    func createCircle(_ p: Coordinate, _ distance: Double) {
        segList.addPt(Coordinate(p.x + distance, p.y))
        addDirectedFillet(p, 0.0, Angle.piTimes2, -1, distance)
        segList.closeRing()
    }

    func createSquare(_ p: Coordinate, _ distance: Double) {
        segList.addPt(Coordinate(p.x + distance, p.y + distance))
        segList.addPt(Coordinate(p.x + distance, p.y - distance))
        segList.addPt(Coordinate(p.x - distance, p.y - distance))
        segList.addPt(Coordinate(p.x - distance, p.y + distance))
        segList.closeRing()
    }
}
