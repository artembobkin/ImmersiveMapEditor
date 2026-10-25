/// The overlay of points with a lineal or areal input: the points located
/// in the other input (unioned first when the result keeps it): JTS's
/// `OverlayMixedPoints`. GEOS sorts the result's points and drops repeats
/// (JTS: a hash set's order), so the port does too.
final class OverlayMixedPoints {
    private let opCode: Int
    private let pm: PrecisionModel?
    private let geomPoint: Geometry
    private let geomNonPointInput: Geometry
    private let factory: GeometryFactory
    private let isPointRHS: Bool
    @exclusivity(unchecked) private var geomNonPoint: Geometry!
    @exclusivity(unchecked) private var geomNonPointDim = 0
    @exclusivity(unchecked) private var locator: PointOnGeometryLocator!
    private let resultDim: Int

    static func overlay(_ opCode: Int, _ geom0: Geometry, _ geom1: Geometry, _ pm: PrecisionModel?) throws -> Geometry {
        try OverlayMixedPoints(opCode, geom0, geom1, pm).getResult()
    }

    init(_ opCode: Int, _ geom0: Geometry, _ geom1: Geometry, _ pm: PrecisionModel?) {
        self.opCode = opCode
        self.pm = pm
        factory = geom0.factory
        resultDim = OverlayUtil.resultDimension(opCode, geom0.getDimension(), geom1.getDimension())
        if geom0.getDimension() == 0 {
            geomPoint = geom0
            geomNonPointInput = geom1
            isPointRHS = false
        } else {
            geomPoint = geom1
            geomNonPointInput = geom0
            isPointRHS = true
        }
    }

    func getResult() throws -> Geometry {
        geomNonPoint = try prepareNonPoint(geomNonPointInput)
        geomNonPointDim = geomNonPoint.getDimension()
        locator = geomNonPointDim == 2 ? IndexedPointInAreaLocator(geomNonPoint) : IndexedPointOnLineLocator(geomNonPoint)
        let coords = OverlayMixedPoints.extractCoordinates(geomPoint, pm)
        switch opCode {
        case OverlayNG.intersection: return createPointResult(findPoints(true, coords))
        case OverlayNG.union, OverlayNG.symDifference: return computeUnion(coords)
        case OverlayNG.difference: return computeDifference(coords)
        default: throw Assert.shouldNeverReachHere("Unknown overlay op code")
        }
    }

    /// The non-point input, unioned to clean it unless the result is points.
    private func prepareNonPoint(_ geomInput: Geometry) throws -> Geometry {
        if resultDim == 0 { return geomInput.copy() }
        return try OverlayNG.union(geomNonPointInput, pm)
    }

    /// The points outside the other input, with its lines or polygons. The
    /// union of the other input may hold lines beside its polygons: JTS
    /// fails on them, GEOS 3.13 takes every non-empty member, as the port does.
    private func computeUnion(_ coords: [Coordinate]) -> Geometry {
        let resultPointList: [Geometry] = findPoints(false, coords)
        var parts: [Geometry] = []
        if geomNonPointDim == 1 || geomNonPointDim == 2 { parts = geomNonPoint.childGeometries.filter { !$0.isEmpty() } }
        return factory.buildGeometry(parts + resultPointList)
    }

    private func computeDifference(_ coords: [Coordinate]) -> Geometry {
        if isPointRHS { return geomNonPoint.copy() }
        return createPointResult(findPoints(false, coords))
    }

    private func createPointResult(_ points: [Point]) -> Geometry {
        if points.isEmpty { return factory.createEmpty(0) }
        if points.count == 1 { return points[0] }
        return factory.createMultiPoint(points)
    }

    /// The points covered by the other input, or not, sorted and each once.
    private func findPoints(_ isCovered: Bool, _ coords: [Coordinate]) -> [Point] {
        var resultCoords = coords.filter { hasLocation(isCovered, $0) }
        CxxAlgorithms.sort(&resultCoords) { $0 < $1 }
        return CoordinateArrays.removeRepeatedPoints(resultCoords).map { factory.createPoint($0) }
    }

    private func hasLocation(_ isCovered: Bool, _ coord: Coordinate) -> Bool {
        let isExterior = Location.exterior == locator.locate(coord)
        return isCovered ? !isExterior : isExterior
    }

    private static func extractCoordinates(_ points: Geometry, _ pm: PrecisionModel?) -> [Coordinate] {
        var coords = CoordinateList()
        for c in points.getCoordinates() { coords.add(OverlayUtil.round(c, pm), false) }
        return coords.points
    }
}

extension Geometry {
    /// The members of a collection, or the geometry itself.
    var childGeometries: [Geometry] { (0..<getNumGeometries()).map { getGeometryN($0) } }
}
