/// Numeric building blocks of the earcutr port: the flat vertex array with its signed area,
/// the point type, the z-order hash, and helpers that reproduce the semantics of the Rust
/// `f64` methods and `num_traits` casts the crate relies on.

/// The number of coordinates per vertex that the triangulation supports (`DIM` in earcutr).
let dim = 2

/// The index of the sentinel node at the start of every node arena (`NULL` in earcutr).
let null = 0

/// Returns the smaller value the way Rust's `f64::min` does on Apple silicon.
///
/// A NaN argument yields the other argument, and negative zero counts as smaller than positive zero.
@inline(__always)
func rustMin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return b }
    if b.isNaN { return a }
    if a == b { return a.sign == .minus ? a : b }
    return a < b ? a : b
}

/// Returns the larger value the way Rust's `f64::max` does on Apple silicon.
///
/// A NaN argument yields the other argument, and positive zero counts as larger than negative zero.
@inline(__always)
func rustMax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return b }
    if b.isNaN { return a }
    if a == b { return a.sign == .minus ? b : a }
    return a > b ? a : b
}

/// Converts a value to `Int64` the way `num_traits::cast::<f64, i64>` does.
///
/// The value is truncated toward zero. It must lie in the open range (-2^63, 2^63), otherwise
/// (and for NaN) the conversion fails with `EarcutError.unknown`.
@inline(__always)
func castToInt64(_ value: Double) throws -> Int64 {
    guard value > -9_223_372_036_854_775_808.0 && value < 9_223_372_036_854_775_808.0 else {
        throw EarcutError.unknown
    }
    return Int64(value)
}

/// A point in the plane (`Coord` in earcutr).
struct Coord: Equatable {
    var x: Double
    var y: Double

    /// The z-order of the point, given the inverse of the longer side of the data's bounding box.
    ///
    /// The coordinates are scaled into a non-negative 15-bit integer range, stored in two 32-bit
    /// halves of one 64-bit integer, interleaved, and folded into 32 bits.
    @inline(__always)
    func zorder(_ invsize: Double) throws -> Int32 {
        let x = try castToInt64(self.x * invsize)
        let y = try castToInt64(self.y * invsize)
        var xy: Int64 = (x &<< 32) | y

        xy = (xy | (xy &<< 8)) & 0x00FF_00FF_00FF_00FF
        xy = (xy | (xy &<< 4)) & 0x0F0F_0F0F_0F0F_0F0F
        xy = (xy | (xy &<< 2)) & 0x3333_3333_3333_3333
        xy = (xy | (xy &<< 1)) & 0x5555_5555_5555_5555

        return Int32(truncatingIfNeeded: (xy &>> 32) | (xy &<< 1))
    }
}

/// The flat array of vertex coordinates the triangulation reads (`Vertices` in earcutr).
struct Vertices {
    let values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    var isEmpty: Bool { values.isEmpty }

    var count: Int { values.count }

    subscript(index: Int) -> Double { values[index] }

    /// The signed area (doubled) of the ring stored in `values[start..<end]`.
    ///
    /// Each vertex is paired with the one before it, the first vertex with the last one, and the
    /// terms are summed in order from the first vertex, as the Rust fold does.
    func signedArea(_ start: Int, _ end: Int) -> Double {
        var sum = 0.0
        var i = start
        var j = end - dim
        while i < end {
            sum = sum + (values[j] - values[i]) * (values[i + 1] + values[j + 1])
            j = i
            i += dim
        }
        return sum
    }
}
