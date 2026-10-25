/// The side of an edge a location is on: JTS's `Position`.
public enum Position {
    /// On the edge itself.
    public static let on = 0
    public static let left = 1
    public static let right = 2

    /// The other side: left for right and the reverse, on for on.
    public static func opposite(_ position: Int) -> Int {
        if position == left { return right }
        if position == right { return left }
        return position
    }
}
