import Darwin

/// The precision of coordinates: JTS's `PrecisionModel`. Floating (doubles,
/// the default), floating single (floats) or fixed: a grid of `1 / scale`,
/// or of the grid size given as a negative scale.
///
/// A fixed model is GEOS 3.13's, which differs from JTS 1.20's: a scale (or
/// grid size) within 1e-5 of an integer is made that integer, the grid size
/// is always kept beside the scale, and a value is rounded on the grid size
/// when it is above 1, else by the scale, with GEOS's rounding (`geosRound`,
/// which keeps the sign of a zero, JTS's `Math.round` does not).
public struct PrecisionModel: Equatable, Sendable {
    public enum Kind: Sendable { case fixed, floating, floatingSingle }

    public let kind: Kind
    public private(set) var scale: Double = 0
    private var storedGridSize: Double = 0

    /// The largest integer a double holds exactly.
    public static let maximumPreciseValue = 9007199254740992.0
    static let gridSizeIntegerTolerance = 1e-5

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
        return storedGridSize
    }

    private mutating func setScale(_ newScale: Double) {
        if newScale == 0 {
            scale = 0
            storedGridSize = 0
        }
        scale = newScale < 0 ? 1.0 / abs(newScale) : newScale
        // A nearly integral scale or grid size is made exact: the common
        // case of fractional powers of ten.
        if scale < 1 {
            storedGridSize = PrecisionModel.snapToInt(1.0 / scale, PrecisionModel.gridSizeIntegerTolerance)
        } else {
            scale = PrecisionModel.snapToInt(scale, PrecisionModel.gridSizeIntegerTolerance)
            storedGridSize = 1.0 / scale
        }
    }

    private static func snapToInt(_ val: Double, _ tolerance: Double) -> Double {
        let valInt = val.rounded(.toNearestOrAwayFromZero)
        if abs(val - valInt) < tolerance { return valInt }
        return val
    }

    public func makePrecise(_ v: Double) -> Double {
        switch kind {
        case .floatingSingle: return Double(Float(v))
        case .fixed:
            if storedGridSize > 1 { return geosRound(v / storedGridSize) * storedGridSize }
            if scale != 0 { return geosRound(v * scale) / scale }
            return v
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
