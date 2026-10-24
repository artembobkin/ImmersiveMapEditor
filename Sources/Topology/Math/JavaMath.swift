/// Java's semantics where JTS relies on them and the port follows: `Math.min`
/// and `Math.max` of doubles, `Math.round`, and `Arrays.sort`, which is stable.

/// Java's `Math.min` of doubles: NaN wins, and -0.0 is less than 0.0.
@inline(__always) func javaMin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return a }
    if a == 0 && b == 0 && (a.sign == .minus || b.sign == .minus) { return -0.0 }
    return a <= b ? a : b
}

/// Java's `Math.max` of doubles: NaN wins, and 0.0 is greater than -0.0.
@inline(__always) func javaMax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN { return a }
    if a == 0 && b == 0 && (a.sign == .plus || b.sign == .plus) { return 0.0 }
    return a >= b ? a : b
}

/// Java's `Math.round` of a double, as a double: the nearest integer, ties
/// toward positive infinity. NaN gives 0, and values beyond the range of a
/// `long` clamp to it, as in Java.
@inline(__always) func javaRound(_ v: Double) -> Double {
    if v.isNaN { return 0 }
    let f = v.rounded(.down)
    let r = v - f >= 0.5 ? f + 1 : f
    if r >= 9.223372036854775807e18 { return 9.223372036854775807e18 }
    if r <= -9.223372036854775808e18 { return -9.223372036854775808e18 }
    return r
}

/// A stable merge sort by a JTS `compareTo`: Java's `Arrays.sort` of objects
/// keeps equal elements in their order, so this does too.
func javaSorted<T>(_ a: [T], _ compare: (T, T) -> Int) -> [T] {
    if a.count < 2 { return a }
    let mid = a.count / 2
    let left = javaSorted(Array(a[..<mid]), compare), right = javaSorted(Array(a[mid...]), compare)
    var out: [T] = []
    out.reserveCapacity(a.count)
    var i = 0, j = 0
    while i < left.count && j < right.count {
        if compare(right[j], left[i]) < 0 { out.append(right[j]); j += 1 } else { out.append(left[i]); i += 1 }
    }
    out.append(contentsOf: left[i...])
    out.append(contentsOf: right[j...])
    return out
}
