/// The dimensionally extended nine-intersection matrix of two geometries
/// (DE-9IM): the dimension of the intersection of each pair of their
/// interiors, boundaries and exteriors, rows for the first geometry: JTS's
/// `IntersectionMatrix`, a value. Indexed by `Location`.
public struct IntersectionMatrix: CustomStringConvertible, Sendable {
    private var matrix = [Int](repeating: Dimension.false, count: 9)

    /// Every entry `F`.
    public init() {}

    /// The matrix of nine symbols, row by row (`"212101212"`).
    public init(_ elements: String) { set(elements) }

    public static func isTrue(_ actualDimensionValue: Int) -> Bool {
        actualDimensionValue >= 0 || actualDimensionValue == Dimension.true
    }

    public static func matches(_ actualDimensionValue: Int, _ requiredDimensionSymbol: Character) -> Bool {
        switch requiredDimensionSymbol {
        case Dimension.symDontCare: return true
        case Dimension.symTrue: return actualDimensionValue >= 0 || actualDimensionValue == Dimension.true
        case Dimension.symFalse: return actualDimensionValue == Dimension.false
        case Dimension.symP: return actualDimensionValue == Dimension.p
        case Dimension.symL: return actualDimensionValue == Dimension.l
        case Dimension.symA: return actualDimensionValue == Dimension.a
        default: return false
        }
    }

    public static func matches(_ actualDimensionSymbols: String, _ requiredDimensionSymbols: String) -> Bool {
        IntersectionMatrix(actualDimensionSymbols).matches(requiredDimensionSymbols)
    }

    public mutating func set(_ row: Int, _ column: Int, _ dimensionValue: Int) { matrix[row * 3 + column] = dimensionValue }

    public mutating func set(_ dimensionSymbols: String) {
        for (i, c) in dimensionSymbols.enumerated() { matrix[i] = Dimension.toDimensionValue(c) }
    }

    public mutating func setAtLeast(_ row: Int, _ column: Int, _ minimumDimensionValue: Int) {
        if matrix[row * 3 + column] < minimumDimensionValue { matrix[row * 3 + column] = minimumDimensionValue }
    }

    public mutating func setAll(_ dimensionValue: Int) {
        for i in 0..<9 { matrix[i] = dimensionValue }
    }

    public func get(_ row: Int, _ column: Int) -> Int { matrix[row * 3 + column] }

    private func m(_ a: Int, _ b: Int) -> Int { matrix[a * 3 + b] }

    private static let i = Location.interior, b = Location.boundary, e = Location.exterior

    public func isDisjoint() -> Bool {
        let (i, b) = (IntersectionMatrix.i, IntersectionMatrix.b)
        return m(i, i) == Dimension.false && m(i, b) == Dimension.false && m(b, i) == Dimension.false && m(b, b) == Dimension.false
    }

    public func isIntersects() -> Bool { !isDisjoint() }

    public func isTouches(_ dimA: Int, _ dimB: Int) -> Bool {
        if dimA > dimB { return isTouches(dimB, dimA) }
        let (i, b) = (IntersectionMatrix.i, IntersectionMatrix.b)
        if (dimA == Dimension.a && dimB == Dimension.a) || (dimA == Dimension.l && dimB == Dimension.l)
            || (dimA == Dimension.l && dimB == Dimension.a) || (dimA == Dimension.p && dimB == Dimension.a)
            || (dimA == Dimension.p && dimB == Dimension.l) {
            return m(i, i) == Dimension.false
                && (IntersectionMatrix.isTrue(m(i, b)) || IntersectionMatrix.isTrue(m(b, i)) || IntersectionMatrix.isTrue(m(b, b)))
        }
        return false
    }

    public func isCrosses(_ dimA: Int, _ dimB: Int) -> Bool {
        let (i, e) = (IntersectionMatrix.i, IntersectionMatrix.e)
        if (dimA == Dimension.p && dimB == Dimension.l) || (dimA == Dimension.p && dimB == Dimension.a)
            || (dimA == Dimension.l && dimB == Dimension.a) {
            return IntersectionMatrix.isTrue(m(i, i)) && IntersectionMatrix.isTrue(m(i, e))
        }
        if (dimA == Dimension.l && dimB == Dimension.p) || (dimA == Dimension.a && dimB == Dimension.p)
            || (dimA == Dimension.a && dimB == Dimension.l) {
            return IntersectionMatrix.isTrue(m(i, i)) && IntersectionMatrix.isTrue(m(e, i))
        }
        if dimA == Dimension.l && dimB == Dimension.l { return m(i, i) == 0 }
        return false
    }

    public func isWithin() -> Bool {
        let (i, b, e) = (IntersectionMatrix.i, IntersectionMatrix.b, IntersectionMatrix.e)
        return IntersectionMatrix.isTrue(m(i, i)) && m(i, e) == Dimension.false && m(b, e) == Dimension.false
    }

    public func isContains() -> Bool {
        let (i, b, e) = (IntersectionMatrix.i, IntersectionMatrix.b, IntersectionMatrix.e)
        return IntersectionMatrix.isTrue(m(i, i)) && m(e, i) == Dimension.false && m(e, b) == Dimension.false
    }

    private func hasPointInCommon() -> Bool {
        let (i, b) = (IntersectionMatrix.i, IntersectionMatrix.b)
        return IntersectionMatrix.isTrue(m(i, i)) || IntersectionMatrix.isTrue(m(i, b))
            || IntersectionMatrix.isTrue(m(b, i)) || IntersectionMatrix.isTrue(m(b, b))
    }

    public func isCovers() -> Bool {
        let (i, b, e) = (IntersectionMatrix.i, IntersectionMatrix.b, IntersectionMatrix.e)
        return hasPointInCommon() && m(e, i) == Dimension.false && m(e, b) == Dimension.false
    }

    public func isCoveredBy() -> Bool {
        let (i, b, e) = (IntersectionMatrix.i, IntersectionMatrix.b, IntersectionMatrix.e)
        return hasPointInCommon() && m(i, e) == Dimension.false && m(b, e) == Dimension.false
    }

    public func isEquals(_ dimA: Int, _ dimB: Int) -> Bool {
        if dimA != dimB { return false }
        let (i, b, e) = (IntersectionMatrix.i, IntersectionMatrix.b, IntersectionMatrix.e)
        return IntersectionMatrix.isTrue(m(i, i)) && m(i, e) == Dimension.false && m(b, e) == Dimension.false
            && m(e, i) == Dimension.false && m(e, b) == Dimension.false
    }

    public func isOverlaps(_ dimA: Int, _ dimB: Int) -> Bool {
        let (i, e) = (IntersectionMatrix.i, IntersectionMatrix.e)
        if (dimA == Dimension.p && dimB == Dimension.p) || (dimA == Dimension.a && dimB == Dimension.a) {
            return IntersectionMatrix.isTrue(m(i, i)) && IntersectionMatrix.isTrue(m(i, e)) && IntersectionMatrix.isTrue(m(e, i))
        }
        if dimA == Dimension.l && dimB == Dimension.l {
            return m(i, i) == 1 && IntersectionMatrix.isTrue(m(i, e)) && IntersectionMatrix.isTrue(m(e, i))
        }
        return false
    }

    /// Whether the matrix matches a pattern of nine symbols (`T`, `F`, `*`,
    /// `0`, `1`, `2`).
    public func matches(_ pattern: String) -> Bool {
        precondition(pattern.count == 9, "Should be length 9: \(pattern)")
        for (k, c) in pattern.enumerated() where !IntersectionMatrix.matches(matrix[k], c) { return false }
        return true
    }

    public var description: String { String(matrix.map(Dimension.toDimensionSymbol)) }
}
