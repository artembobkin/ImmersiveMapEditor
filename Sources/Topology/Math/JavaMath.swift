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

/// A stable merge sort by a JTS `compareTo`: Java's `Arrays.sort` of objects
/// keeps equal elements in their order, so this does too.
/// Top down (each half from `count / 2`), merging with one scratch buffer;
/// of two elements the left one is taken unless the right one is less.
func javaSorted<T>(_ a: [T], _ compare: (T, T) -> Int) -> [T] {
    if a.count < 2 { return a }
    var out = a
    var scratch = a
    out.withUnsafeMutableBufferPointer { o in
        scratch.withUnsafeMutableBufferPointer { s in
            javaMergeSort(o, s, 0, o.count, compare)
        }
    }
    return out
}

private func javaMergeSort<T>(_ a: UnsafeMutableBufferPointer<T>, _ s: UnsafeMutableBufferPointer<T>,
                              _ lo: Int, _ hi: Int, _ compare: (T, T) -> Int) {
    let n = hi - lo
    if n < 2 { return }
    let mid = lo + n / 2
    javaMergeSort(a, s, lo, mid, compare)
    javaMergeSort(a, s, mid, hi, compare)
    var i = lo, j = mid, k = lo
    while i < mid && j < hi {
        if compare(a[j], a[i]) < 0 { s[k] = a[j]; j += 1 } else { s[k] = a[i]; i += 1 }
        k += 1
    }
    while i < mid { s[k] = a[i]; i += 1; k += 1 }
    while j < hi { s[k] = a[j]; j += 1; k += 1 }
    for t in lo..<hi { a[t] = s[t] }
}

/// GEOS's rounding (`util::round`, its `java_math_round`): the nearest
/// integer, halves toward positive infinity, as Java's `Math.round`, but
/// from `floor` and `ceil`, so a value in (-0.5, 0] rounds to `-0.0` (Java
/// gives `0.0`), and with no clamping to a `long`. NaN stays NaN.
@inline(__always) func geosRound(_ val: Double) -> Double {
    let n = val.rounded(.towardZero)
    let f = abs(val - n)
    if val >= 0 {
        if f < 0.5 { return val.rounded(.down) }
        if f > 0.5 { return val.rounded(.up) }
        return n + 1.0
    }
    if f < 0.5 { return val.rounded(.up) }
    if f > 0.5 { return val.rounded(.down) }
    return n
}
