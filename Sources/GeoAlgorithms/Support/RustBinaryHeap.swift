/// A port of Rust's `std::collections::BinaryHeap` (Rust 1.98), a max-heap. The ported
/// algorithms pop elements that compare equal, so the exact sift order of the Rust heap is kept:
/// `push` sifts up, `pop` moves the last element to the root, sifts it down to the bottom and then
/// up again, `init(_:)` heapifies with `rebuild`, and `extend` appends and runs `rebuild_tail`.

public struct RustBinaryHeap<Element, Failure: Error> {
    private(set) var data: [Element]
    /// Rust's `Ord::cmp` of the element type.
    private let cmp: (Element, Element) throws(Failure) -> RustOrdering

    public init(cmp: @escaping (Element, Element) throws(Failure) -> RustOrdering) {
        self.data = []
        self.cmp = cmp
    }

    /// Rust's `BinaryHeap::from(Vec)`: takes the elements in place and rebuilds the heap.
    public init(
        _ elements: [Element],
        cmp: @escaping (Element, Element) throws(Failure) -> RustOrdering
    ) throws(Failure) {
        self.data = elements
        self.cmp = cmp
        try rebuild()
    }

    public var count: Int { data.count }
    public var isEmpty: Bool { data.isEmpty }

    /// Rust's `peek`: the greatest element.
    public func peek() -> Element? { data.first }

    // `PartialOrd` derived from `Ord`: `a <= b` is `cmp(a, b) != Greater`, and so on.
    private func le(_ a: Element, _ b: Element) throws(Failure) -> Bool { try cmp(a, b) != .greater }
    private func ge(_ a: Element, _ b: Element) throws(Failure) -> Bool { try cmp(a, b) != .less }
    private func lt(_ a: Element, _ b: Element) throws(Failure) -> Bool { try cmp(a, b) == .less }

    public mutating func push(_ item: Element) throws(Failure) {
        let oldLen = data.count
        data.append(item)
        _ = try siftUp(start: 0, pos: oldLen)
    }

    public mutating func pop() throws(Failure) -> Element? {
        guard var item = data.popLast() else { return nil }
        if !data.isEmpty {
            swap(&item, &data[0])
            try siftDownToBottom(0)
        }
        return item
    }

    /// Rust's `Extend` for `BinaryHeap`: the items are appended, then the tail is rebuilt.
    public mutating func extend<S: Sequence>(_ items: S) throws(Failure) where S.Element == Element {
        let start = data.count
        data.append(contentsOf: items)
        try rebuildTail(start)
    }

    private mutating func siftUp(start: Int, pos: Int) throws(Failure) -> Int {
        let element = data[pos]
        var hole = pos
        while hole > start {
            let parent = (hole - 1) / 2
            if try le(element, data[parent]) {
                break
            }
            data[hole] = data[parent]
            hole = parent
        }
        data[hole] = element
        return hole
    }

    private mutating func siftDownRange(_ pos: Int, _ end: Int) throws(Failure) -> Int {
        let element = data[pos]
        var hole = pos
        var child = 2 * hole + 1
        while child <= Swift.max(end - 2, 0) {
            if try le(data[child], data[child + 1]) {
                child += 1
            }
            if try ge(element, data[child]) {
                data[hole] = element
                return hole
            }
            data[hole] = data[child]
            hole = child
            child = 2 * hole + 1
        }
        if child == end - 1, try lt(element, data[child]) {
            data[hole] = data[child]
            hole = child
        }
        data[hole] = element
        return hole
    }

    private mutating func siftDownToBottom(_ pos: Int) throws(Failure) {
        let end = data.count
        let start = pos
        let element = data[pos]
        var hole = pos
        var child = 2 * hole + 1
        while child <= Swift.max(end - 2, 0) {
            if try le(data[child], data[child + 1]) {
                child += 1
            }
            data[hole] = data[child]
            hole = child
            child = 2 * hole + 1
        }
        if child == end - 1 {
            data[hole] = data[child]
            hole = child
        }
        data[hole] = element
        _ = try siftUp(start: start, pos: hole)
    }

    private mutating func rebuildTail(_ start: Int) throws(Failure) {
        if start == data.count {
            return
        }
        let tailLen = data.count - start
        func log2Fast(_ x: Int) -> Int {
            Int.bitWidth - x.leadingZeroBitCount - 1
        }
        let betterToRebuild: Bool
        if start < tailLen {
            betterToRebuild = true
        } else if data.count <= 2048 {
            betterToRebuild = 2 * data.count < tailLen * log2Fast(start)
        } else {
            betterToRebuild = 2 * data.count < tailLen * 11
        }
        if betterToRebuild {
            try rebuild()
        } else {
            for i in start..<data.count {
                _ = try siftUp(start: 0, pos: i)
            }
        }
    }

    private mutating func rebuild() throws(Failure) {
        var n = data.count / 2
        while n > 0 {
            n -= 1
            _ = try siftDownRange(n, data.count)
        }
    }
}
