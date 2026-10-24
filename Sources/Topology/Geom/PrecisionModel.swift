import Darwin

/// The precision of coordinates: JTS's `PrecisionModel`. Floating (doubles,
/// the default), floating single (floats) or fixed: a grid of `1 / scale`,
/// or of `gridSize` when made from a negative scale.
public struct PrecisionModel: Equatable, Sendable {
    public enum Kind: Sendable { case fixed, floating, floatingSingle }

    public let kind: Kind
    public private(set) var scale: Double = 0
    private var storedGridSize: Double = 0

    /// The largest integer a double holds exactly.
    public static let maximumPreciseValue = 9007199254740992.0

    public static let floating = PrecisionModel()

    public init() { kind = .floating }

    public init(kind: Kind) {
        self.kind = kind
        if kind == .fixed { setScale(1.0) }
    }

    /// A fixed model: a positive scale, or the grid size as a negative one.
    public init(scale: Double) {
        kind = .fixed
        setScale(scale)
    }

    public static func mostPrecise(_ a: PrecisionModel, _ b: PrecisionModel) -> PrecisionModel {
        a.compareTo(b) >= 0 ? a : b
    }

    public var isFloating: Bool { kind == .floating || kind == .floatingSingle }

    public var maximumSignificantDigits: Int {
        switch kind {
        case .floating: return 16
        case .floatingSingle: return 6
        case .fixed: return 1 + Int(ceil(log(scale) / log(10)))
        }
    }

    public var gridSize: Double {
        if isFloating { return .nan }
        if storedGridSize != 0 { return storedGridSize }
        return 1.0 / scale
    }

    private mutating func setScale(_ s: Double) {
        if s < 0 {
            storedGridSize = abs(s)
            scale = 1.0 / storedGridSize
        } else {
            scale = abs(s)
            storedGridSize = 0
        }
    }

    public func makePrecise(_ v: Double) -> Double {
        if v.isNaN { return v }
        switch kind {
        case .floatingSingle: return Double(Float(v))
        case .fixed:
            if storedGridSize > 0 { return javaRound(v / storedGridSize) * storedGridSize }
            return javaRound(v * scale) / scale
        case .floating: return v
        }
    }

    public func makePrecise(_ c: Coordinate) -> Coordinate {
        if kind == .floating { return c }
        return Coordinate(makePrecise(c.x), makePrecise(c.y))
    }

    public static func == (a: PrecisionModel, b: PrecisionModel) -> Bool { a.kind == b.kind && a.scale == b.scale }

    public func compareTo(_ o: PrecisionModel) -> Int {
        let a = maximumSignificantDigits, b = o.maximumSignificantDigits
        return a < b ? -1 : (a > b ? 1 : 0)
    }
}
