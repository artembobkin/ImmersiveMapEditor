/// Why a geometry is not valid, and where: JTS's `TopologyValidationError`.
public struct TopologyValidationError: CustomStringConvertible, Sendable {
    public static let error = 0
    public static let repeatedPoint = 1
    public static let holeOutsideShell = 2
    public static let nestedHoles = 3
    public static let disconnectedInterior = 4
    public static let selfIntersection = 5
    public static let ringSelfIntersection = 6
    public static let nestedShells = 7
    public static let duplicateRings = 8
    public static let tooFewPoints = 9
    public static let invalidCoordinate = 10
    public static let ringNotClosed = 11

    public static let errMsg = [
        "Topology Validation Error",
        "Repeated Point",
        "Hole lies outside shell",
        "Holes are nested",
        "Interior is disconnected",
        "Self-intersection",
        "Ring Self-intersection",
        "Nested shells",
        "Duplicate Rings",
        // GEOS 3.13's text (JTS: "Too few distinct points in geometry component").
        "Too few points in geometry component",
        "Invalid Coordinate",
        "Ring is not closed",
    ]

    public let errorType: Int
    /// The place of the error, nil where JTS has none (GEOS's default
    /// coordinate, (0, 0), there).
    public let coordinate: Coordinate?

    public init(_ errorType: Int, _ pt: Coordinate?) {
        self.errorType = errorType
        coordinate = pt
    }

    public func getErrorType() -> Int { errorType }
    public func getCoordinate() -> Coordinate? { coordinate }
    public func getMessage() -> String { TopologyValidationError.errMsg[errorType] }

    public var description: String { getMessage() + (coordinate.map { " at or near point \($0.x) \($0.y)" } ?? "") }
}
