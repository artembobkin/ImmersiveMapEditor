/// Where a point is relative to a geometry: JTS's `Location`, with its
/// integer values (they index matrices and labels).
public enum Location {
    public static let interior = 0
    public static let boundary = 1
    public static let exterior = 2
    /// No location (an absent value).
    public static let none = -1

    public static func toLocationSymbol(_ l: Int) -> Character {
        switch l {
        case exterior: return "e"
        case boundary: return "b"
        case interior: return "i"
        default: return "-"
        }
    }
}
