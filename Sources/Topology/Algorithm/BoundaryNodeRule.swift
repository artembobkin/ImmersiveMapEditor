/// Which endpoints of lines are on the boundary: JTS's `BoundaryNodeRule`,
/// by how many line ends meet at a point.
public enum BoundaryNodeRule: Sendable {
    /// The OGC rule: an odd number of ends (the default).
    case mod2
    case endPoint
    case multiValentEndPoint
    case monoValentEndPoint

    public static let ogcSFS = BoundaryNodeRule.mod2

    public func isInBoundary(_ boundaryCount: Int) -> Bool {
        switch self {
        case .mod2: return boundaryCount % 2 == 1
        case .endPoint: return boundaryCount > 0
        case .multiValentEndPoint: return boundaryCount > 1
        case .monoValentEndPoint: return boundaryCount == 1
        }
    }
}
