/// A double-double: a number as the unevaluated sum of two doubles, about 106
/// bits of precision. JTS's `DD`, the arithmetic of its robust predicates
/// (`CGAlgorithmsDD`). A value, so JTS's `selfAdd` style mutating methods
/// and its copying ones (`add`) are both here.
///
/// The products inside a multiplication or division are fused as GEOS's
/// compiler fuses the same expressions (see `Fused.swift`).
public struct DD: Sendable, CustomStringConvertible {
    public private(set) var hi: Double
    public private(set) var lo: Double

    static let split = 134217729.0

    public init(_ x: Double) {
        hi = x
        lo = 0.0
    }

    public init(_ hi: Double, _ lo: Double) {
        self.hi = hi
        self.lo = lo
    }

    public static func valueOf(_ x: Double) -> DD { DD(x) }

    public static let nan = DD(.nan, .nan)

    public var isNaN: Bool { hi.isNaN }
    public var isZero: Bool { hi == 0.0 && lo == 0.0 }
    public var isNegative: Bool { hi < 0.0 || (hi == 0.0 && lo < 0.0) }
    public var isPositive: Bool { hi > 0.0 || (hi == 0.0 && lo > 0.0) }
    public var doubleValue: Double { hi + lo }

    public func signum() -> Int {
        if hi > 0 { return 1 }
        if hi < 0 { return -1 }
        if lo > 0 { return 1 }
        if lo < 0 { return -1 }
        return 0
    }

    // MARK: Adding

    @discardableResult
    public mutating func selfAdd(_ y: Double) -> DD {
        var H: Double, h: Double, S: Double, s: Double, e: Double, f: Double
        S = hi + y
        e = S - hi
        s = S - e
        s = (y - e) + (hi - s)
        f = s + lo
        H = S + f
        h = f + (S - H)
        hi = H + h
        lo = h + (H - hi)
        return self
    }

    @discardableResult
    public mutating func selfAdd(_ y: DD) -> DD { selfAdd(y.hi, y.lo) }

    @discardableResult
    mutating func selfAdd(_ yhi: Double, _ ylo: Double) -> DD {
        var H: Double, h: Double, T: Double, t: Double, S: Double, s: Double, e: Double, f: Double
        S = hi + yhi
        T = lo + ylo
        e = S - hi
        f = T - lo
        s = S - e
        t = T - f
        s = (yhi - e) + (hi - s)
        t = (ylo - f) + (lo - t)
        e = s + T
        H = S + e
        h = e + (S - H)
        e = t + h
        let zhi = H + e
        let zlo = e + (H - zhi)
        hi = zhi
        lo = zlo
        return self
    }

    @discardableResult
    public mutating func selfSubtract(_ y: DD) -> DD {
        if isNaN { return self }
        return selfAdd(-y.hi, -y.lo)
    }

    @discardableResult
    public mutating func selfSubtract(_ y: Double) -> DD {
        if isNaN { return self }
        return selfAdd(-y, 0.0)
    }

    public func add(_ y: DD) -> DD { var c = self; return c.selfAdd(y) }
    public func add(_ y: Double) -> DD { var c = self; return c.selfAdd(y) }
    public func subtract(_ y: DD) -> DD { add(y.negate()) }
    public func subtract(_ y: Double) -> DD { add(-y) }

    public func negate() -> DD {
        if isNaN { return self }
        return DD(-hi, -lo)
    }

    // MARK: Multiplying and dividing

    public func multiply(_ y: DD) -> DD {
        if y.isNaN { return .nan }
        var c = self
        return c.selfMultiply(y)
    }

    public func multiply(_ y: Double) -> DD {
        if y.isNaN { return .nan }
        var c = self
        return c.selfMultiply(y, 0.0)
    }

    @discardableResult
    public mutating func selfMultiply(_ y: DD) -> DD { selfMultiply(y.hi, y.lo) }

    @discardableResult
    public mutating func selfMultiply(_ y: Double) -> DD { selfMultiply(y, 0.0) }

    @discardableResult
    mutating func selfMultiply(_ yhi: Double, _ ylo: Double) -> DD {
        var hx: Double, tx: Double, hy: Double, ty: Double, C: Double, c: Double
        C = DD.split * hi
        hx = C - hi
        c = DD.split * yhi
        hx = C - hx
        tx = hi - hx
        hy = c - yhi
        C = hi * yhi
        hy = c - hy
        ty = yhi - hy
        // c = ((((hx*hy-C)+hx*ty)+tx*hy)+tx*ty)+(hi*ylo+lo*yhi), fused.
        let a = fusedAdd(tx, ty, fusedAdd(tx, hy, fusedAdd(hx, ty, fusedSub(hx, hy, C))))
        c = a + fusedAdd(hi, ylo, lo * yhi)
        let zhi = C + c
        hx = C - zhi
        let zlo = c + hx
        hi = zhi
        lo = zlo
        return self
    }

    public func divide(_ y: DD) -> DD {
        var c = self
        return c.selfDivide(y.hi, y.lo)
    }

    public func divide(_ y: Double) -> DD {
        if y.isNaN { return .nan }
        var c = self
        return c.selfDivide(y, 0.0)
    }

    @discardableResult
    public mutating func selfDivide(_ y: DD) -> DD { selfDivide(y.hi, y.lo) }

    @discardableResult
    public mutating func selfDivide(_ y: Double) -> DD { selfDivide(y, 0.0) }

    @discardableResult
    mutating func selfDivide(_ yhi: Double, _ ylo: Double) -> DD {
        var hc: Double, tc: Double, hy: Double, ty: Double, C: Double, c: Double, U: Double, u: Double
        C = hi / yhi
        c = DD.split * C
        hc = c - C
        u = DD.split * yhi
        hc = c - hc
        tc = C - hc
        hy = u - yhi
        U = C * yhi
        hy = u - hy
        ty = yhi - hy
        // u = (((hc*hy-U)+hc*ty)+tc*hy)+tc*ty, fused.
        u = fusedAdd(tc, ty, fusedAdd(tc, hy, fusedAdd(hc, ty, fusedSub(hc, hy, U))))
        // c = ((((hi-U)-u)+lo)-C*ylo)/yhi, fused.
        c = fusedSubProduct(((hi - U) - u) + lo, C, ylo) / yhi
        u = C + c
        hi = u
        lo = (C - u) + c
        return self
    }

    public func sqr() -> DD { multiply(self) }

    public func sqrt() -> DD {
        if isZero { return DD(0.0) }
        if isNegative { return .nan }
        let x = 1.0 / hi.squareRoot()
        let ax = hi * x
        let axdd = DD(ax)
        let diffSq = subtract(axdd.sqr())
        let d2 = diffSq.hi * (x * 0.5)
        return axdd.add(d2)
    }

    public static func determinant(_ x1: DD, _ y1: DD, _ x2: DD, _ y2: DD) -> DD {
        var det = x1.multiply(y2)
        return det.selfSubtract(y1.multiply(x2))
    }

    // MARK: Comparing

    public func gt(_ y: DD) -> Bool { (hi > y.hi) || (hi == y.hi && lo > y.lo) }
    public func ge(_ y: DD) -> Bool { (hi > y.hi) || (hi == y.hi && lo >= y.lo) }
    public func lt(_ y: DD) -> Bool { (hi < y.hi) || (hi == y.hi && lo < y.lo) }
    public func le(_ y: DD) -> Bool { (hi < y.hi) || (hi == y.hi && lo <= y.lo) }

    public var description: String { "DD(\(hi), \(lo))" }
}
