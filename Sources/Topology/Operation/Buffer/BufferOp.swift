import Darwin

/// The buffer of a geometry: the area within a distance of it (or, for a
/// negative distance, the area of it farther than the distance from its
/// boundary): JTS's `BufferOp`, run as GEOS 3.13 runs it.
///
/// The buffer is first built in the input's precision. If that fails on a
/// topology error, it is built again with the input snap-rounded to a fixed
/// precision, from 12 significant digits of the result's extent down to 6
/// (JTS goes down to 0), each try catching only topology errors. In the
/// first try too only a topology error leads on (JTS catches any runtime
/// error there).
public final class BufferOp {
    private static let maxPrecisionDigits = 12
    private static let minPrecisionDigits = 6

    private let argGeom: Geometry
    @exclusivity(unchecked) private var distance = 0.0
    private let bufParams: BufferParameters
    @exclusivity(unchecked) private var resultGeometry: Geometry?
    @exclusivity(unchecked) private var saveException: Error?
    @exclusivity(unchecked) var isInvertOrientation = false

    public init(_ g: Geometry, _ bufParams: BufferParameters = BufferParameters()) {
        argGeom = g
        self.bufParams = bufParams
    }

    public static func bufferOp(_ g: Geometry, _ distance: Double, _ params: BufferParameters = BufferParameters()) throws -> Geometry {
        try BufferOp(g, params).getResultGeometry(distance)
    }

    /// The scale of a precision model keeping `maxPrecisionDigits` digits
    /// of the extent of the buffer.
    static func precisionScaleFactor(_ g: Geometry, _ distance: Double, _ maxPrecisionDigits: Int) -> Double {
        let env = g.getEnvelopeInternal()
        let envMax = cxxMax(cxxMax(abs(env.maxX), abs(env.minX)), cxxMax(abs(env.maxY), abs(env.minY)))
        let expandByDistance = distance > 0.0 ? distance : 0.0
        let bufEnvMax = fusedAdd(2, expandByDistance, envMax)
        let bufEnvPrecisionDigits = Int(log(bufEnvMax) / log(10.0) + 1.0)
        let minUnitLog10 = maxPrecisionDigits - bufEnvPrecisionDigits
        return pow(10.0, Double(minUnitLog10))
    }

    public func getResultGeometry(_ distance: Double) throws -> Geometry {
        if !distance.isFinite {
            throw IllegalArgumentException("BufferOp::getResultGeometry distance must be a finite value")
        }
        self.distance = distance
        try computeGeometry()
        return resultGeometry!
    }

    private func computeGeometry() throws {
        try bufferOriginalPrecision()
        if resultGeometry != nil { return }
        let argPM = argGeom.factory.precisionModel
        if argPM.kind == .fixed {
            try bufferFixedPrecision(argPM)
        } else {
            try bufferReducedPrecision()
        }
    }

    private func bufferReducedPrecision() throws {
        for precDigits in stride(from: BufferOp.maxPrecisionDigits, through: BufferOp.minPrecisionDigits, by: -1) {
            do {
                try bufferReducedPrecision(precDigits)
            } catch let e as TopologyException {
                saveException = e
            }
            if resultGeometry != nil { return }
        }
        throw saveException!
    }

    private func bufferOriginalPrecision() throws {
        let bufBuilder = BufferBuilder(bufParams)
        bufBuilder.isInvertOrientation = isInvertOrientation
        do {
            resultGeometry = try bufBuilder.buffer(argGeom, distance)
        } catch let e as TopologyException {
            saveException = e
        }
    }

    private func bufferReducedPrecision(_ precisionDigits: Int) throws {
        let sizeBasedScaleFactor = BufferOp.precisionScaleFactor(argGeom, distance, precisionDigits)
        try bufferFixedPrecision(PrecisionModel(scale: sizeBasedScaleFactor))
    }

    /// The buffer with its curves snap-rounded to a fixed precision.
    private func bufferFixedPrecision(_ fixedPM: PrecisionModel) throws {
        let noder = ScaledNoder(SnapRoundingNoder(PrecisionModel(scale: 1.0)), fixedPM.scale)
        let bufBuilder = BufferBuilder(bufParams)
        bufBuilder.workingPrecisionModel = fixedPM
        bufBuilder.workingNoder = noder
        bufBuilder.isInvertOrientation = isInvertOrientation
        resultGeometry = try bufBuilder.buffer(argGeom, distance)
    }
}

extension Geometry {
    /// The buffer of the geometry, as `GEOSBufferWithStyle` makes it: `quadSegs`
    /// segments a quadrant of a round arc, the cap and join styles of
    /// `BufferParameters`, and the mitre limit.
    public func buffer(_ distance: Double, quadSegs: Int = BufferParameters.defaultQuadrantSegments,
                       endCapStyle: Int = BufferParameters.capRound, joinStyle: Int = BufferParameters.joinRound,
                       mitreLimit: Double = BufferParameters.defaultMitreLimit) throws -> Geometry {
        if endCapStyle > BufferParameters.capSquare { throw IllegalArgumentException("Invalid buffer endCap style") }
        if joinStyle > BufferParameters.joinBevel { throw IllegalArgumentException("Invalid buffer join style") }
        let params = BufferParameters(quadrantSegments: quadSegs, endCapStyle: endCapStyle, joinStyle: joinStyle, mitreLimit: mitreLimit)
        return try BufferOp.bufferOp(self, distance, params)
    }
}
