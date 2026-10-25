/// Overlay that does not fail on valid inputs: floating precision first,
/// then snapping with a growing tolerance (the inputs as they are, then each
/// cleaned by a snapped union of itself), then snap rounding at a safe
/// precision: JTS's `OverlayNGRobust`, as GEOS 3.13 runs it. An input of a
/// fixed precision is overlaid at it, with no retries.
///
/// As in GEOS, the first try gives up on any failure, the later tries only
/// on a `TopologyException` (another error ends the overlay), and when all
/// fail the first try's error is thrown.
public enum OverlayNGRobust {
    static let numSnapTries = 5
    static let snapTolFactor = 1e12

    /// The union of one geometry: unary union with this overlay.
    public static func union(_ geom: Geometry) throws -> Geometry {
        let op = UnaryUnionOp(geom)
        op.unionFunction = .overlayNGRobust
        return try op.union()
    }

    public static func overlay(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int) throws -> Geometry {
        if !geom0.precisionModel.isFloating {
            return try NonFinite.scope { try OverlayNG.overlay(geom0, geom1, opCode, geom0.precisionModel) }
        }
        let exOriginal: Error
        do {
            let r = try NonFinite.scope { try OverlayNG.overlay(geom0, geom1, opCode, PrecisionModel.floating) }
            trace?("floating")
            return r
        } catch {
            trace?("floating fails: \(error)")
            exOriginal = error
        }
        if let result = try overlaySnapTries(geom0, geom1, opCode) { return result }
        if let result = try overlaySR(geom0, geom1, opCode) {
            trace?("snap rounding")
            return result
        }
        // GEOS keeps the first failure as a `std::runtime_error` (sliced from
        // whatever it was) and throws that.
        throw RuntimeError(String(describing: exOriginal))
    }

    /// Told which stage each overlay ended at, when set (a test's probe).
    nonisolated(unsafe) public static var trace: ((String) -> Void)?

    private static func overlaySnapTries(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int) throws -> Geometry? {
        var snapTol = snapTolerance(geom0, geom1)
        for _ in 0..<numSnapTries {
            if let result = try overlaySnapping(geom0, geom1, opCode, snapTol) {
                trace?("snapping \(snapTol)")
                return result
            }
            if let result = try overlaySnapBoth(geom0, geom1, opCode, snapTol) {
                trace?("snapping both \(snapTol)")
                return result
            }
            snapTol = snapTol * 10
        }
        return nil
    }

    private static func overlaySnapping(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int, _ snapTol: Double) throws -> Geometry? {
        do {
            return try NonFinite.scope { try overlaySnapTol(geom0, geom1, opCode, snapTol) }
        } catch is TopologyException {
            return nil
        }
    }

    private static func overlaySnapBoth(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int, _ snapTol: Double) throws -> Geometry? {
        do {
            return try NonFinite.scope {
                let snap0 = try snapSelf(geom0, snapTol)
                let snap1 = try snapSelf(geom1, snapTol)
                return try overlaySnapTol(snap0, snap1, opCode, snapTol)
            }
        } catch is TopologyException {
            return nil
        }
    }

    /// The geometry cleaned by a strict union of itself, with snapping.
    private static func snapSelf(_ geom: Geometry, _ snapTol: Double) throws -> Geometry {
        let ov = OverlayNG(geom, nil, nil, OverlayNG.union)
        ov.noder = SnappingNoder(snapTol)
        ov.isStrictMode = true
        return try ov.getResult()
    }

    private static func overlaySnapTol(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int, _ snapTol: Double) throws -> Geometry {
        try OverlayNG.overlay(geom0, geom1, opCode, noder: SnappingNoder(snapTol))
    }

    /// The snap tolerance: the inputs' largest ordinate magnitude over 1e12.
    public static func snapTolerance(_ geom0: Geometry, _ geom1: Geometry) -> Double {
        cxxMax(snapTolerance(geom0), snapTolerance(geom1))
    }

    private static func snapTolerance(_ geom: Geometry) -> Double { ordinateMagnitude(geom) / snapTolFactor }

    private static func ordinateMagnitude(_ geom: Geometry) -> Double {
        if geom.isEmpty() { return 0 }
        let env = geom.getEnvelopeInternal()
        let magMax = cxxMax(abs(env.maxX), abs(env.maxY))
        let magMin = cxxMax(abs(env.minX), abs(env.minY))
        return cxxMax(magMax, magMin)
    }

    private static func overlaySR(_ geom0: Geometry, _ geom1: Geometry, _ opCode: Int) throws -> Geometry? {
        do {
            let scaleSafe = PrecisionUtil.safeScale(geom0, geom1)
            return try NonFinite.scope { try OverlayNG.overlay(geom0, geom1, opCode, PrecisionModel(scale: scaleSafe)) }
        } catch is TopologyException {
            return nil
        }
    }
}
