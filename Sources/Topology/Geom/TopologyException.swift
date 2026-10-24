/// A failure of the topology of an operation: JTS's `TopologyException`.
public struct TopologyException: Error, CustomStringConvertible {
    public let message: String
    public let coordinate: Coordinate?

    public init(_ message: String, _ coordinate: Coordinate? = nil) {
        self.message = message
        self.coordinate = coordinate
    }

    public var description: String { coordinate.map { "\(message) [ \($0.x) \($0.y) ]" } ?? message }
}
