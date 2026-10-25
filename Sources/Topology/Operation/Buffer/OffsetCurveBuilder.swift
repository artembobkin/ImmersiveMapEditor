/// The raw offset curves of points, lines and rings, which the buffer then
/// nodes and polygonizes: JTS's `OffsetCurveBuilder`.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: the
/// tolerance of the input simplification is the distance divided by 100
/// (JTS multiplies by its simplify factor, 0.01: not the same double), a
/// ring buffered by zero is itself whatever its size, a curve's points are
/// taken with the ring closed (so the raw offset curve of a line is closed
/// too), and an offset of a line that simplifies to one vertex fails.
final class OffsetCurveBuilder {
    private static let simplifyFactor = 100.0

    @exclusivity(unchecked) private var distance = 0.0
    private let precisionModel: PrecisionModel
    let bufParams: BufferParameters

    init(_ precisionModel: PrecisionModel, _ bufParams: BufferParameters) {
        self.precisionModel = precisionModel
        self.bufParams = bufParams
    }

    /// The closed curve around a line or a point, nil when a line has none
    /// (a zero or negative distance).
    func getLineCurve(_ inputPts: [Coordinate], _ distance: Double) -> [Coordinate]? {
        self.distance = distance
        if isLineOffsetEmpty(distance) { return nil }
        let segGen = OffsetSegmentGenerator(precisionModel, bufParams, abs(distance))
        if inputPts.count <= 1 {
            computePointCurve(inputPts[0], segGen)
        } else {
            computeLineBufferCurve(inputPts, segGen)
        }
        return segGen.getCoordinates()
    }

    func isLineOffsetEmpty(_ distance: Double) -> Bool { distance <= 0.0 }

    /// The curve on one side of a ring.
    func getRingCurve(_ inputPts: [Coordinate], _ side: Int, _ distance: Double) -> [Coordinate]? {
        self.distance = distance
        if distance == 0.0 { return inputPts }
        if inputPts.count <= 2 { return getLineCurve(inputPts, distance) }
        let segGen = OffsetSegmentGenerator(precisionModel, bufParams, abs(distance))
        computeRingBufferCurve(inputPts, side, segGen)
        return segGen.getCoordinates()
    }

    /// The offset of a line on one side (the left for a positive distance),
    /// nil for a zero distance.
    func getOffsetCurve(_ inputPts: [Coordinate], _ distance: Double) throws -> [Coordinate]? {
        self.distance = distance
        if distance == 0.0 { return nil }
        let isRightSide = distance < 0.0
        let segGen = OffsetSegmentGenerator(precisionModel, bufParams, abs(distance))
        if inputPts.count <= 1 {
            computePointCurve(inputPts[0], segGen)
        } else {
            try computeOffsetCurve(inputPts, isRightSide, segGen)
        }
        let curvePts = segGen.getCoordinates()
        return isRightSide ? curvePts.reversed() : curvePts
    }

    private func simplifyTolerance(_ bufDistance: Double) -> Double { bufDistance / OffsetCurveBuilder.simplifyFactor }

    private func computePointCurve(_ pt: Coordinate, _ segGen: OffsetSegmentGenerator) {
        switch bufParams.endCapStyle {
        case BufferParameters.capRound: segGen.createCircle(pt, distance)
        case BufferParameters.capSquare: segGen.createSquare(pt, distance)
        default: break
        }
    }

    private func computeLineBufferCurve(_ inputPts: [Coordinate], _ segGen: OffsetSegmentGenerator) {
        let distTol = simplifyTolerance(distance)
        // The left side, along the line.
        let simp1 = BufferInputLineSimplifier.simplify(inputPts, distTol)
        let n1 = simp1.count - 1
        segGen.initSideSegments(simp1[0], simp1[1], Position.left)
        if n1 >= 2 {
            for i in 2...n1 { segGen.addNextSegment(simp1[i], true) }
        }
        segGen.addLastSegment()
        segGen.addLineEndCap(simp1[n1 - 1], simp1[n1])
        // The right side, back along it.
        let simp2 = BufferInputLineSimplifier.simplify(inputPts, -distTol)
        let n2 = simp2.count - 1
        segGen.initSideSegments(simp2[n2], simp2[n2 - 1], Position.left)
        for i in stride(from: n2 - 2, through: 0, by: -1) { segGen.addNextSegment(simp2[i], true) }
        segGen.addLastSegment()
        segGen.addLineEndCap(simp2[1], simp2[0])
        segGen.closeRing()
    }

    private func computeOffsetCurve(_ inputPts: [Coordinate], _ isRightSide: Bool, _ segGen: OffsetSegmentGenerator) throws {
        let distTol = simplifyTolerance(abs(distance))
        if isRightSide {
            let simp2 = BufferInputLineSimplifier.simplify(inputPts, -distTol)
            let n2 = simp2.count - 1
            if n2 == 0 { throw IllegalArgumentException("Cannot get offset of single-vertex line") }
            segGen.initSideSegments(simp2[n2], simp2[n2 - 1], Position.left)
            segGen.addFirstSegment()
            for i in stride(from: n2 - 2, through: 0, by: -1) { segGen.addNextSegment(simp2[i], true) }
        } else {
            let simp1 = BufferInputLineSimplifier.simplify(inputPts, distTol)
            let n1 = simp1.count - 1
            if n1 == 0 { throw IllegalArgumentException("Cannot get offset of single-vertex line") }
            segGen.initSideSegments(simp1[0], simp1[1], Position.left)
            segGen.addFirstSegment()
            if n1 >= 2 {
                for i in 2...n1 { segGen.addNextSegment(simp1[i], true) }
            }
        }
        segGen.addLastSegment()
    }

    private func computeRingBufferCurve(_ inputPts: [Coordinate], _ side: Int, _ segGen: OffsetSegmentGenerator) {
        var distTol = simplifyTolerance(distance)
        if side == Position.right { distTol = -distTol }
        let simp = BufferInputLineSimplifier.simplify(inputPts, distTol)
        let n = simp.count - 1
        segGen.initSideSegments(simp[n - 1], simp[0], side)
        if n >= 1 {
            for i in 1...n { segGen.addNextSegment(simp[i], i != 1) }
        }
        segGen.closeRing()
    }
}
