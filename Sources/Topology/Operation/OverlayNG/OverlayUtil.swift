/// The helpers of OverlayNG: the clipping envelope, empty results and their
/// dimension, the result's geometry, rounding, and the check of the result
/// area against the inputs': JTS's `OverlayUtil`.
enum OverlayUtil {
    static func isFloating(_ pm: PrecisionModel?) -> Bool {
        guard let pm else { return true }
        return pm.isFloating
    }

    /// The envelope edges can be clipped to without changing the result,
    /// nil when they cannot be (union and symmetric difference).
    static func clippingEnvelope(_ opCode: Int, _ inputGeom: InputGeometry, _ pm: PrecisionModel?) -> Envelope? {
        guard let resultEnv = resultEnvelope(opCode, inputGeom, pm) else { return nil }
        let clipEnv = RobustClipEnvelopeComputer.getEnvelope(inputGeom.getGeometry(0), inputGeom.getGeometry(1), resultEnv)
        return safeEnv(clipEnv, pm)
    }

    private static func resultEnvelope(_ opCode: Int, _ inputGeom: InputGeometry, _ pm: PrecisionModel?) -> Envelope? {
        switch opCode {
        case OverlayNG.intersection:
            let envA = safeEnv(inputGeom.getEnvelope(0), pm)
            let envB = safeEnv(inputGeom.getEnvelope(1), pm)
            return envA.intersection(envB)
        case OverlayNG.difference:
            return safeEnv(inputGeom.getEnvelope(0), pm)
        default:
            return nil
        }
    }

    private static func safeEnv(_ env: Envelope, _ pm: PrecisionModel?) -> Envelope {
        var safeEnv = env
        safeEnv.expandBy(safeExpandDistance(env, pm))
        return safeEnv
    }

    private static let safeEnvBufferFactor = 0.1
    private static let safeEnvGridFactor = 3

    private static func safeExpandDistance(_ env: Envelope, _ pm: PrecisionModel?) -> Double {
        if isFloating(pm) {
            var minSize = javaMin(env.height, env.width)
            // A flat envelope: its length.
            if minSize <= 0.0 { minSize = javaMax(env.height, env.width) }
            return safeEnvBufferFactor * minSize
        }
        let gridSize = 1.0 / pm!.scale
        return Double(safeEnvGridFactor) * gridSize
    }

    /// Whether the result is empty whatever the inputs' edges are.
    static func isEmptyResult(_ opCode: Int, _ a: Geometry?, _ b: Geometry?, _ pm: PrecisionModel?) -> Bool {
        switch opCode {
        case OverlayNG.intersection: return isEnvDisjoint(a, b, pm)
        case OverlayNG.difference: return isEmpty(a)
        case OverlayNG.union, OverlayNG.symDifference: return isEmpty(a) && isEmpty(b)
        default: return false
        }
    }

    private static func isEmpty(_ geom: Geometry?) -> Bool { geom == nil || geom!.isEmpty() }

    static func isEnvDisjoint(_ a: Geometry?, _ b: Geometry?, _ pm: PrecisionModel?) -> Bool {
        if isEmpty(a) || isEmpty(b) { return true }
        if isFloating(pm) { return a!.getEnvelopeInternal().disjoint(b!.getEnvelopeInternal()) }
        return isDisjoint(a!.getEnvelopeInternal(), b!.getEnvelopeInternal(), pm!)
    }

    /// Envelopes disjoint once rounded to the precision.
    private static func isDisjoint(_ envA: Envelope, _ envB: Envelope, _ pm: PrecisionModel) -> Bool {
        if pm.makePrecise(envB.minX) > pm.makePrecise(envA.maxX) { return true }
        if pm.makePrecise(envB.maxX) < pm.makePrecise(envA.minX) { return true }
        if pm.makePrecise(envB.minY) > pm.makePrecise(envA.maxY) { return true }
        if pm.makePrecise(envB.maxY) < pm.makePrecise(envA.minY) { return true }
        return false
    }

    /// The empty geometry of a dimension (-1: an empty collection).
    static func createEmptyResult(_ dim: Int, _ factory: GeometryFactory) -> Geometry {
        switch dim {
        case 0: return factory.createPoint()
        case 1: return factory.createLineString()
        case 2: return factory.createPolygon()
        default: return factory.createGeometryCollection()
        }
    }

    static func resultDimension(_ opCode: Int, _ dim0: Int, _ dim1: Int) -> Int {
        switch opCode {
        case OverlayNG.intersection: return min(dim0, dim1)
        case OverlayNG.union: return max(dim0, dim1)
        case OverlayNG.difference: return dim0
        case OverlayNG.symDifference: return max(dim0, dim1)
        default: return -1
        }
    }

    /// The result's parts in the order areas, lines, points, as the most
    /// specific geometry.
    static func createResultGeometry(_ polys: [Polygon]?, _ lines: [LineString]?, _ points: [Point]?,
                                     _ factory: GeometryFactory) -> Geometry {
        var geomList: [Geometry] = []
        if let polys { geomList.append(contentsOf: polys as [Geometry]) }
        if let lines { geomList.append(contentsOf: lines as [Geometry]) }
        if let points { geomList.append(contentsOf: points as [Geometry]) }
        return factory.buildGeometry(geomList)
    }

    static func round(_ p: Coordinate, _ pm: PrecisionModel?) -> Coordinate {
        if !isFloating(pm) { return pm!.makePrecise(p) }
        return p
    }

    private static let areaHeuristicTolerance = 0.1

    /// Whether the result's area is possible for the operation, within a
    /// tenth: a noding that moved vertices can turn an area inside out.
    ///
    /// As GEOS 3.13 checks it, which differs from JTS 1.20 twice: a result
    /// of lines or points is checked too (its area is zero, so a union of
    /// areas that collapsed to lines fails the check), and a difference is
    /// checked as at least the difference of the areas, less a tenth of it
    /// (JTS: less a tenth of the first area).
    static func isResultAreaConsistent(_ geom0: Geometry?, _ geom1: Geometry?, _ opCode: Int, _ result: Geometry) -> Bool {
        guard let geom0, let geom1 else { return true }
        let areaResult = result.getArea()
        let areaA = geom0.getArea()
        let areaB = geom1.getArea()
        let tol = areaHeuristicTolerance
        switch opCode {
        case OverlayNG.intersection:
            return isLess(areaResult, areaA, tol) && isLess(areaResult, areaB, tol)
        case OverlayNG.difference:
            return isLess(areaResult, areaA, tol) && isGreater(areaResult, areaA - areaB, tol)
        case OverlayNG.symDifference:
            return isLess(areaResult, areaA + areaB, tol)
        case OverlayNG.union:
            return isLess(areaA, areaResult, tol) && isLess(areaB, areaResult, tol)
                && isGreater(areaResult, areaA - areaB, tol)
        default:
            return true
        }
    }

    private static func isLess(_ v1: Double, _ v2: Double, _ tol: Double) -> Bool { v1 <= v2 * (1 + tol) }
    private static func isGreater(_ v1: Double, _ v2: Double, _ tol: Double) -> Bool { v1 >= v2 * (1 - tol) }
}
