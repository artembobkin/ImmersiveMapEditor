/// The dimension of a geometry: JTS's `Dimension` values.
public enum Dimension {
    public static let p = 0
    public static let l = 1
    public static let a = 2
    /// The dimension of the empty set.
    public static let `false` = -1
    /// Any non-empty dimension, in patterns.
    public static let `true` = -2
    /// Any dimension, in patterns.
    public static let dontCare = -3
}

extension Dimension {
    public static let symFalse: Character = "F"
    public static let symTrue: Character = "T"
    public static let symDontCare: Character = "*"
    public static let symP: Character = "0"
    public static let symL: Character = "1"
    public static let symA: Character = "2"

    /// The symbol of a dimension value in a matrix's text.
    public static func toDimensionSymbol(_ dimensionValue: Int) -> Character {
        switch dimensionValue {
        case `false`: return symFalse
        case `true`: return symTrue
        case dontCare: return symDontCare
        case p: return symP
        case l: return symL
        case a: return symA
        default: preconditionFailure("Unknown dimension value: \(dimensionValue)")
        }
    }

    /// The dimension value of a matrix symbol.
    public static func toDimensionValue(_ dimensionSymbol: Character) -> Int {
        switch dimensionSymbol.uppercased() {
        case "F": return `false`
        case "T": return `true`
        case "*": return dontCare
        case "0": return p
        case "1": return l
        case "2": return a
        default: preconditionFailure("Unknown dimension symbol: \(dimensionSymbol)")
        }
    }
}
