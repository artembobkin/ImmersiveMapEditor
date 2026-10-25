import Darwin

/// The parameters of a buffer: segments per quadrant of a round arc, the
/// style of the end caps and the joins, and the mitre limit: JTS's
/// `BufferParameters`. Single-sided buffers are not ported (GEOS 3.13
/// builds them with its polygonizer and line merger, and the package never
/// asks for one), nor the simplify factor (GEOS divides the distance by a
/// fixed 100, `OffsetCurveBuilder`).
public struct BufferParameters {
    public static let capRound = 1
    public static let capFlat = 2
    public static let capSquare = 3
    public static let joinRound = 1
    public static let joinMitre = 2
    public static let joinBevel = 3
    public static let defaultQuadrantSegments = 8
    public static let defaultMitreLimit = 5.0

    public var quadrantSegments = BufferParameters.defaultQuadrantSegments
    public var endCapStyle = BufferParameters.capRound
    public var joinStyle = BufferParameters.joinRound
    public var mitreLimit = BufferParameters.defaultMitreLimit

    public init() {}

    public init(quadrantSegments: Int, endCapStyle: Int = BufferParameters.capRound,
                joinStyle: Int = BufferParameters.joinRound, mitreLimit: Double = BufferParameters.defaultMitreLimit) {
        self.quadrantSegments = quadrantSegments
        self.endCapStyle = endCapStyle
        self.joinStyle = joinStyle
        self.mitreLimit = mitreLimit
    }

    /// The largest distance of an arc of `quadSegs` segments a quadrant
    /// from the true circle, as a fraction of the radius.
    public static func bufferDistanceError(_ quadSegs: Int) -> Double {
        let alpha = Angle.piOver2 / Double(quadSegs)
        return 1 - cos(alpha / 2.0)
    }
}
