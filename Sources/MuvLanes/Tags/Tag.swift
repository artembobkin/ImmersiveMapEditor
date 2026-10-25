/// muv-osm's `Tag`: OSM tags as a tree split at the colons (`cycleway:left:width`
/// is `cycleway` → `left` → `width`), each node with an optional value, and
/// `Taglike`, what Muv reads tags through (a tree node, or `DoubleTag`, a
/// node with a fallback). Subtags iterate in the order of Rust's `HashMap`
/// with rustc-hash (see `HashOrder`).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// One node of the tree. Built once, then only read.
public final class Tag {
    public private(set) var value: String?
    private var keys: [String] = []
    private var children: [Tag] = []
    private var index: [String: Int] = [:]
    private var hashOrder: HashOrder
    private var cachedOrder: [Int]?

    /// `Tag::new()`, `Tag::with_capacity(capacity)`.
    init(capacity: Int = 0) {
        hashOrder = HashOrder(capacity: capacity)
    }

    /// `FromIterator<(K, V)> for Tag`: the pairs in order, the root sized for half of them.
    public convenience init(pairs: [(String, String)]) {
        self.init(capacity: pairs.count / 2)
        for (k, v) in pairs { insertRaw(k, v) }
    }

    /// `Tag::insert_raw`: walks down the key's colon-separated parts,
    /// making the missing nodes, and sets the value of the last.
    func insertRaw(_ key: String, _ val: String) {
        var tag = self
        for part in key.rustSplit(":") { tag = tag.entry(part) }
        tag.value = val
    }

    /// `subtags.entry(key).or_default()`.
    func entry(_ key: String) -> Tag {
        if let i = index[key] { return children[i] }
        let child = Tag()
        index[key] = keys.count
        keys.append(key)
        children.append(child)
        hashOrder.insert(hash: fxHashStr(key))
        cachedOrder = nil
        return child
    }

    /// `subtags.get(key)`.
    public func subtag(_ key: String) -> Tag? {
        index[key].map { children[$0] }
    }

    /// `subtags.iter()`, in the `HashMap`'s order.
    public func subtags() -> [(String, Tag)] {
        if cachedOrder == nil { cachedOrder = hashOrder.order() }
        return cachedOrder!.map { (keys[$0], children[$0]) }
    }
}

/// `Taglike`: a value, subtags by key, and the subtags in order.
protocol Taglike {
    var value: String? { get }
    func get(_ key: String) -> Self?
    func iterSubtags() -> [(String, Self)]
}

extension Taglike {
    /// `get_value(key)`, `get_tag!(tags, key)`.
    func getValue(_ key: String) -> String? { get(key)?.value }

    /// `get_tag!(tags, a:b:)`: the node at a path of keys.
    func sub(_ path: String...) -> Self? {
        var t: Self? = self
        for k in path { t = t?.get(k) }
        return t
    }

    /// `get_tag!(tags, a:b)`: the value at a path of keys.
    func subValue(_ path: String...) -> String? {
        var t: Self? = self
        for k in path { t = t?.get(k) }
        return t?.value
    }
}

extension Tag: Taglike {
    func get(_ key: String) -> Tag? { subtag(key) }
    func iterSubtags() -> [(String, Tag)] { subtags() }
}

/// `DoubleTag`: a node read through first, then a fallback node (the
/// `both` side under a `left` or `right` one). Its subtags are only the first's.
struct DoubleTag: Taglike {
    let a: Tag
    let b: Tag?

    /// `DoubleTag::new_reverse(a, b)`.
    static func newReverse(_ a: Tag?, _ b: Tag) -> DoubleTag {
        if let a { return DoubleTag(a: a, b: b) }
        return DoubleTag(a: b, b: nil)
    }

    /// `DoubleTag::maybe_new(a, b)`.
    static func maybeNew(_ a: Tag?, _ b: Tag?) -> DoubleTag? {
        if let a { return DoubleTag(a: a, b: b) }
        if let b { return DoubleTag(a: b, b: nil) }
        return nil
    }

    var value: String? { a.value ?? b?.value }

    func get(_ key: String) -> DoubleTag? {
        if let x = a.get(key) { return DoubleTag(a: x, b: b?.get(key)) }
        guard let y = b?.get(key) else { return nil }
        return DoubleTag(a: y, b: nil)
    }

    func iterSubtags() -> [(String, DoubleTag)] {
        a.iterSubtags().map { ($0.0, DoubleTag(a: $0.1, b: nil)) }
    }
}
