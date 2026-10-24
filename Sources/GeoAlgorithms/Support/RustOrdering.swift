/// Rust's `std::cmp::Ordering` and the float helpers of Rust's standard library that the ported
/// algorithms depend on, reproduced so the Swift code makes the same decisions as the Rust.

/// The result of a comparison, as Rust's `Ordering`. The cases are declared in Rust's order
/// (`Less < Equal < Greater`), so the raw values compare the same way.
public enum RustOrdering: Int, Comparable, Sendable {
    case less = -1
    case equal = 0
    case greater = 1

    public static func < (lhs: RustOrdering, rhs: RustOrdering) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Rust's `Ordering::reverse`.
    @inlinable
    public var reversed: RustOrdering {
        switch self {
        case .less: return .greater
        case .equal: return .equal
        case .greater: return .less
        }
    }

    /// Rust's `Ordering::then`: `self` unless it is `Equal`, then `other`.
    @inlinable
    public func then(_ other: RustOrdering) -> RustOrdering {
        self == .equal ? other : self
    }

    /// Rust's `Ordering::then_with`: like `then`, with the second comparison evaluated lazily.
    @inlinable
    public func thenWith<E: Error>(_ other: () throws(E) -> RustOrdering) throws(E) -> RustOrdering {
        self == .equal ? try other() : self
    }

    /// Rust's `Ord::cmp` for two values with a total order.
    @inlinable
    public static func compare<T: Comparable>(_ a: T, _ b: T) -> RustOrdering {
        a < b ? .less : (a == b ? .equal : .greater)
    }
}

/// Rust's `f64::partial_cmp`: `nil` when either value is NaN.
func rustPartialCmp(_ a: Double, _ b: Double) -> RustOrdering? {
    if a < b { return .less }
    if a > b { return .greater }
    if a == b { return .equal }
    return nil
}

/// Rust's `f64::min`, which LLVM lowers to `minnum` and Apple silicon executes as `FMINNM`:
/// a NaN operand is ignored, and of two zeros of different signs the negative one is returned.
func rustMin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return b }
    if b.isNaN { return a }
    if a < b { return a }
    if b < a { return b }
    // Equal values: only the sign of a zero can still differ.
    return a.sign == .minus ? a : b
}

/// Rust's `f64::max` (`maxnum`, `FMAXNM` on Apple silicon): a NaN operand is ignored, and of two
/// zeros of different signs the positive one is returned.
func rustMax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return b }
    if b.isNaN { return a }
    if a > b { return a }
    if b > a { return b }
    return a.sign == .plus ? a : b
}

/// A Rust panic, reported as a Swift error so a caller can recover from it the way geom does with
/// `std::panic::catch_unwind`. The message is the one the Rust code panics with.
public struct GeoPanic: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "GeoPanic: \(message)" }

    /// The message of Rust's `Option::unwrap` on `None`.
    static let unwrapNone = GeoPanic("called `Option::unwrap()` on a `None` value")
    /// The message of Rust's `unreachable!()`.
    static let unreachable = GeoPanic("internal error: entered unreachable code")

    /// The message of an out of bounds slice index in Rust.
    static func indexOutOfBounds(_ index: Int, _ count: Int) -> GeoPanic {
        GeoPanic("index out of bounds: the len is \(count) but the index is \(index)")
    }
}

extension Array {
    /// Indexes the array, throwing Rust's out of bounds panic instead of trapping.
    func checked(_ index: Int) throws(GeoPanic) -> Element {
        guard index >= 0 && index < count else { throw GeoPanic.indexOutOfBounds(index, count) }
        return self[index]
    }
}
