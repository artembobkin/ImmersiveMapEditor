/// geo's `VecSet<Active<IMSegment>>`: the segments crossing the sweep line, bottom to top, in a
/// sorted array searched with Rust's `binary_search`. `Active::cmp` asserts a total order and
/// panics when two segments cannot be compared.

struct ActiveSet<C: SweepCross> {
    private(set) var data: [IMSegment<C>] = []

    var count: Int { data.count }

    subscript(index: Int) -> IMSegment<C> { data[index] }

    /// `Active::cmp(element, target)`.
    private static func activeCmp(_ a: IMSegment<C>, _ b: IMSegment<C>) throws(GeoPanic) -> RustOrdering {
        guard let c = a.partialCmp(b) else {
            throw GeoPanic("unable to compare active segments!")
        }
        return c
    }

    private func search(_ segment: IMSegment<C>) throws(GeoPanic) -> RustSearchResult {
        try rustBinarySearch(data) { (element: IMSegment<C>) throws(GeoPanic) -> RustOrdering in
            try Self.activeCmp(element, segment)
        }
    }

    /// `index_of`: the index of a segment that must be in the set.
    func indexOf(_ segment: IMSegment<C>) throws(GeoPanic) -> Int {
        switch try search(segment) {
        case .found(let i): return i
        case .notFound(let i): throw GeoPanic("segment not found in active-vec-set: \(i)")
        }
    }

    /// `index_not_of`: the insertion index of a segment that must not be in the set.
    func indexNotOf(_ segment: IMSegment<C>) throws(GeoPanic) -> Int {
        switch try search(segment) {
        case .found(let i): throw GeoPanic("segment already found in active-vec-set: \(i)")
        case .notFound(let i): return i
        }
    }

    mutating func insertAt(_ index: Int, _ segment: IMSegment<C>) throws(GeoPanic) {
        guard index >= 0 && index <= data.count else {
            throw GeoPanic("insertion index (is \(index)) should be <= len (is \(data.count))")
        }
        data.insert(segment, at: index)
    }

    mutating func removeAt(_ index: Int) throws(GeoPanic) -> IMSegment<C> {
        guard index >= 0 && index < data.count else {
            throw GeoPanic("removal index (is \(index)) should be < len (is \(data.count))")
        }
        return data.remove(at: index)
    }

    /// `ActiveSet::previous`: the segment just below `segment`.
    func previous(_ segment: IMSegment<C>) throws(GeoPanic) -> IMSegment<C>? {
        let ub = try search(segment).index
        return ub > 0 ? data[ub - 1] : nil
    }

    /// `ActiveSet::next`: the segment just above `segment`.
    func next(_ segment: IMSegment<C>) throws(GeoPanic) -> IMSegment<C>? {
        let start: Int
        switch try search(segment) {
        case .found(let i): start = i + 1
        case .notFound(let i): start = i
        }
        return start < data.count ? data[start] : nil
    }
}
