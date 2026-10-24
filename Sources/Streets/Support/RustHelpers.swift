/// Small pieces of Rust's standard library and abstutil the port leans on:
/// saturating float to integer casts, `wraparound_get`, stable sorts and
/// `max_by_key`'s tie-breaking.

/// Rust's `x as i64`: truncates, saturates, NaN becomes 0.
@inlinable
func rustAsI64(_ x: Double) -> Int64 {
    if x.isNaN { return 0 }
    if x >= 9_223_372_036_854_775_807.0 { return Int64.max }
    if x <= -9_223_372_036_854_775_808.0 { return Int64.min }
    return Int64(x)
}

/// Rust's `x as usize`: truncates, saturates at 0 and the maximum, NaN becomes 0.
@inlinable
func rustAsUsize(_ x: Double) -> Int {
    if x.isNaN || x <= 0 { return 0 }
    if x >= 9_223_372_036_854_775_807.0 { return Int.max }
    return Int(x)
}

/// abstutil's `wraparound_get`: Rust's `%` keeps the sign of the dividend.
func wraparoundGet<T>(_ vec: [T], _ idx: Int) -> T {
    let len = vec.count
    let i = idx % len
    return vec[i >= 0 ? i : i + len]
}

extension Array {
    /// Rust's `sort_by_key`: a stable sort by a key.
    func stableSorted<K: Comparable>(by key: (Element) -> K) -> [Element] {
        let keyed = enumerated().map { (offset: $0.offset, key: key($0.element), element: $0.element) }
        return keyed.sorted { a, b in
            if a.key != b.key { return a.key < b.key }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Rust's `Iterator::max_by_key`: on ties, the last maximum wins.
    func rustMaxByKey<K: Comparable>(_ key: (Element) -> K) -> Element? {
        var best: (Element, K)?
        for x in self {
            let k = key(x)
            if let b = best, k < b.1 { continue }
            best = (x, k)
        }
        return best?.0
    }

    /// Rust's `Iterator::min_by_key`: on ties, the first minimum wins.
    func rustMinByKey<K: Comparable>(_ key: (Element) -> K) -> Element? {
        var best: (Element, K)?
        for x in self {
            let k = key(x)
            if let b = best, !(k < b.1) { continue }
            best = (x, k)
        }
        return best?.0
    }
}

/// A pair of comparable values compared as a Rust tuple: first, then second.
struct Pair<A: Comparable, B: Comparable>: Comparable {
    var a: A
    var b: B
    init(_ a: A, _ b: B) {
        self.a = a
        self.b = b
    }
    static func < (l: Pair, r: Pair) -> Bool { l.a != r.a ? l.a < r.a : l.b < r.b }
}

extension Bool: @retroactive Comparable {
    /// Rust's order: false before true.
    public static func < (a: Bool, b: Bool) -> Bool { !a && b }
}

extension Pair: Hashable where A: Hashable, B: Hashable {}
