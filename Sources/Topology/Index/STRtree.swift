/// A query-only R-tree packed by the Sort-Tile-Recursive algorithm: JTS's
/// `STRtree` (with `AbstractSTRtree`, `AbstractNode`, `ItemBoundable` and
/// `BoundablePair`), generic over its items. Items are inserted, then the
/// tree is built once, at the first query: the items sorted by the x of their
/// envelope's centre and cut into vertical slices, each slice sorted by y and
/// packed into nodes of `nodeCapacity`, level by level.
public final class STRtree<Item> {
    /// A node or an item, with its envelope.
    enum Boundable {
        case node(Node)
        case item(Envelope, Item)

        var bounds: Envelope {
            switch self {
            case .node(let n): return n.bounds
            case .item(let e, _): return e
            }
        }
    }

    final class Node {
        let level: Int
        var children: [Boundable] = []
        /// For a node of the lowest level, the index of its first item
        /// among the leaves in the order the tree packed them.
        var firstLeaf = 0
        private var cached: Envelope?

        init(level: Int) { self.level = level }

        var bounds: Envelope {
            if let c = cached { return c }
            var e: Envelope?
            for c in children {
                if e == nil { e = c.bounds } else { e!.expandToInclude(c.bounds) }
            }
            // An empty node has no bounds in JTS (null): the null envelope.
            let b = e ?? Envelope()
            cached = b
            return b
        }
    }

    public let nodeCapacity: Int
    /// How ties are broken: as JTS (a stable sort, Java's heap) or as GEOS
    /// (libc++'s sort and heap, `CxxAlgorithms`), the default: equal
    /// envelope centres and equal distances come out in another order.
    public enum TieOrder { case jts, geos }
    public let tieOrder: TieOrder
    private var itemBoundables: [Boundable] = []
    /// The items in the order the tree packed them (sorted by x, then each
    /// slice by y), the order GEOS keeps its leaves in.
    private var leaves: [(Envelope, Item)] = []
    private var root: Node?
    /// The built tree in one array for the queries: each node's children
    /// next to each other, in their order (`flat[0]` the root). An entry
    /// with `item >= 0` is an item, its index among `leaves`.
    private struct FlatEntry {
        var env: Envelope
        var first = 0
        var count = 0
        var item = -1
    }
    private var flat: [FlatEntry] = []

    public init(nodeCapacity: Int = 10, tieOrder: TieOrder = .geos) {
        precondition(nodeCapacity > 1, "Node capacity must be greater than 1")
        self.nodeCapacity = nodeCapacity
        self.tieOrder = tieOrder
    }

    /// Sorted by a key, ties broken by the tree's order.
    func sorted(_ b: [Boundable], by key: (Envelope) -> Double) -> [Boundable] {
        switch tieOrder {
        case .jts: return javaSorted(b) { STRtree.compareDoubles(key($0.bounds), key($1.bounds)) }
        case .geos:
            var a = b
            CxxAlgorithms.sort(&a) { key($0.bounds) < key($1.bounds) }
            return a
        }
    }

    /// Adds an item. One with a null envelope is not indexed, as in JTS.
    public func insert(_ env: Envelope, _ item: Item) {
        precondition(root == nil, "Cannot insert items into an STR packed R-tree after it has been built.")
        if env.isNull { return }
        itemBoundables.append(.item(env, item))
    }

    public func build() {
        if root != nil { return }
        root = itemBoundables.isEmpty ? Node(level: 0) : createHigherLevels(itemBoundables, -1)
        itemBoundables = []
        flatten()
    }

    private func flatten() {
        let root = root!
        flat = [FlatEntry(env: root.bounds)]
        var queue: [(Int, Node)] = [(0, root)]
        var head = 0
        while head < queue.count {
            let (idx, node) = queue[head]
            head += 1
            let first = flat.count
            for (k, c) in node.children.enumerated() {
                switch c {
                case .node(let n):
                    flat.append(FlatEntry(env: n.bounds))
                    queue.append((flat.count - 1, n))
                case .item(let e, _):
                    flat.append(FlatEntry(env: e, item: node.firstLeaf + k))
                }
            }
            flat[idx].first = first
            flat[idx].count = node.children.count
        }
    }

    public var isEmpty: Bool {
        guard let root else { return itemBoundables.isEmpty }
        return root.children.isEmpty
    }

    public var size: Int {
        if isEmpty { return 0 }
        build()
        func count(_ n: Node) -> Int {
            n.children.reduce(0) { s, c in
                if case .node(let m) = c { return s + count(m) }
                return s + 1
            }
        }
        return count(root!)
    }

    // MARK: Building

    static func centreX(_ e: Envelope) -> Double { (e.minX + e.maxX) / 2 }
    static func centreY(_ e: Envelope) -> Double { (e.minY + e.maxY) / 2 }

    static func compareDoubles(_ a: Double, _ b: Double) -> Int { a > b ? 1 : (a < b ? -1 : 0) }

    func createHigherLevels(_ boundablesOfALevel: [Boundable], _ level: Int) -> Node {
        let parents = createParentBoundables(boundablesOfALevel, level + 1)
        if parents.count == 1, case .node(let n) = parents[0] { return n }
        return createHigherLevels(parents, level + 1)
    }

    func createParentBoundables(_ children: [Boundable], _ newLevel: Int) -> [Boundable] {
        let minLeafCount = Int((Double(children.count) / Double(nodeCapacity)).rounded(.up))
        let sorted = self.sorted(children, by: STRtree.centreX)
        let slices = verticalSlices(sorted, Int(Double(minLeafCount).squareRoot().rounded(.up)))
        return slices.flatMap { createParentBoundablesFromVerticalSlice($0, newLevel) }
    }

    func verticalSlices(_ children: [Boundable], _ sliceCount: Int) -> [[Boundable]] {
        let sliceCapacity = Int((Double(children.count) / Double(sliceCount)).rounded(.up))
        var slices: [[Boundable]] = []
        var i = 0
        for _ in 0..<sliceCount {
            var slice: [Boundable] = []
            while i < children.count && slice.count < sliceCapacity {
                slice.append(children[i])
                i += 1
            }
            slices.append(slice)
        }
        return slices
    }

    /// AbstractSTRtree's packing of one slice: sorted by the y of the centre,
    /// into nodes of `nodeCapacity`.
    func createParentBoundablesFromVerticalSlice(_ children: [Boundable], _ newLevel: Int) -> [Boundable] {
        precondition(!children.isEmpty)
        var parents = [Node(level: newLevel)]
        let sorted = self.sorted(children, by: STRtree.centreY)
        for c in sorted {
            if parents.last!.children.count == nodeCapacity { parents.append(Node(level: newLevel)) }
            parents.last!.children.append(c)
        }
        if newLevel == 0 {
            for p in parents {
                p.firstLeaf = leaves.count
                for case .item(let e, let item) in p.children { leaves.append((e, item)) }
            }
        }
        return parents.map { .node($0) }
    }

    // MARK: Querying

    /// The items whose envelopes meet `searchEnv`, in the tree's order.
    public func query(_ searchEnv: Envelope) -> [Item] {
        var matches: [Item] = []
        query(searchEnv) { matches.append($0) }
        return matches
    }

    public func query(_ searchEnv: Envelope, _ visit: (Item) -> Void) {
        build()
        if isEmpty { return }
        guard flat[0].env.intersects(searchEnv) else { return }
        flat.withUnsafeBufferPointer { f in
            leaves.withUnsafeBufferPointer { l in STRtree.queryFlat(f, l, searchEnv, 0, visit) }
        }
    }

    private static func queryFlat(_ f: UnsafeBufferPointer<FlatEntry>, _ l: UnsafeBufferPointer<(Envelope, Item)>,
                                  _ searchEnv: Envelope, _ idx: Int, _ visit: (Item) -> Void) {
        let e = f[idx]
        for c in e.first..<(e.first + e.count) {
            let ch = f[c]
            guard ch.env.intersects(searchEnv) else { continue }
            if ch.item >= 0 { visit(l[ch.item].1) } else { queryFlat(f, l, searchEnv, c, visit) }
        }
    }


    /// The items in the order the tree packed them: sorted by the x of
    /// their envelope's centre, then each vertical slice by the y.
    public func itemsInPackedOrder() -> [Item] {
        build()
        return leaves.map(\.1)
    }

    /// Every pair of items whose envelopes meet, once: for each item in the
    /// packed order, the items after it in that order that the tree finds
    /// for its envelope, in the tree's depth-first order. This is the order
    /// GEOS 3.13's STR tree reports pairs in (JTS queries the tree for each
    /// item in insertion order instead). The visit returns false to stop the
    /// search of the current item's pairs only: as in GEOS, the search goes
    /// on with the next item, so a noder whose intersector is done still
    /// sees the first pair of each later item.
    public func queryPairs(_ visit: (Item, Item) -> Bool) {
        build()
        guard leaves.count >= 2 else { return }
        flat.withUnsafeBufferPointer { f in
            leaves.withUnsafeBufferPointer { l in
                for i in l.indices { _ = STRtree.queryPairsFlat(f, l, i, l[i].0, 0, visit) }
            }
        }
    }

    private static func queryPairsFlat(_ f: UnsafeBufferPointer<FlatEntry>, _ l: UnsafeBufferPointer<(Envelope, Item)>,
                                       _ i: Int, _ queryEnv: Envelope, _ idx: Int, _ visit: (Item, Item) -> Bool) -> Bool {
        let e = f[idx]
        for c in e.first..<(e.first + e.count) {
            let ch = f[c]
            if ch.item >= 0 {
                if ch.item > i && ch.env.intersects(queryEnv) && !visit(l[i].1, l[ch.item].1) { return false }
            } else if ch.env.intersects(queryEnv) && !queryPairsFlat(f, l, i, queryEnv, c, visit) {
                return false
            }
        }
        return true
    }


    // MARK: Nearest neighbour

    /// A pair of boundables and their distance: of the items when both are
    /// items, else of the envelopes.
    struct BoundablePair {
        let b1: Boundable
        let b2: Boundable
        let distance: Double

        init(_ b1: Boundable, _ b2: Boundable, _ itemDistance: (Item, Item) -> Double) {
            self.b1 = b1
            self.b2 = b2
            if case .item(_, let i1) = b1, case .item(_, let i2) = b2 {
                distance = itemDistance(i1, i2)
            } else {
                distance = b1.bounds.distance(b2.bounds)
            }
        }

        var isLeaves: Bool {
            if case .node = b1 { return false }
            if case .node = b2 { return false }
            return true
        }

        static func compare(_ a: BoundablePair, _ b: BoundablePair) -> Int {
            if a.distance < b.distance { return -1 }
            if a.distance > b.distance { return 1 }
            return 0
        }

        func expandToQueue(_ priQ: inout PairQueue, _ minDistance: Double,
                           _ itemDistance: (Item, Item) -> Double) {
            switch (b1, b2) {
            case (.node(let n1), .node(let n2)):
                if n1.bounds.area > n2.bounds.area {
                    expand(n1, b2, false, &priQ, minDistance, itemDistance)
                } else {
                    expand(n2, b1, true, &priQ, minDistance, itemDistance)
                }
            case (.node(let n1), _): expand(n1, b2, false, &priQ, minDistance, itemDistance)
            case (_, .node(let n2)): expand(n2, b1, true, &priQ, minDistance, itemDistance)
            default: preconditionFailure("neither boundable is composite")
            }
        }

        func expand(_ composite: Node, _ other: Boundable, _ isFlipped: Bool, _ priQ: inout PairQueue,
                    _ minDistance: Double, _ itemDistance: (Item, Item) -> Double) {
            for child in composite.children {
                let bp = isFlipped ? BoundablePair(other, child, itemDistance) : BoundablePair(child, other, itemDistance)
                if bp.distance < minDistance { priQ.add(bp) }
            }
        }
    }

    /// The queue of pairs by distance, the least first: Java's
    /// `PriorityQueue` or libc++'s `std::priority_queue`.
    struct PairQueue {
        var java: JavaPriorityQueue<BoundablePair>?
        var cxx: CxxPriorityQueue<BoundablePair>?

        init(_ order: TieOrder) {
            switch order {
            case .jts: java = JavaPriorityQueue(BoundablePair.compare)
            case .geos: cxx = CxxPriorityQueue { $0.distance > $1.distance }
            }
        }

        var isEmpty: Bool { java?.isEmpty ?? cxx!.isEmpty }

        mutating func add(_ p: BoundablePair) {
            if java != nil { java!.add(p) } else { cxx!.push(p) }
        }

        mutating func poll() -> BoundablePair? {
            if java != nil { return java!.poll() }
            guard let t = cxx!.top else { return nil }
            cxx!.pop()
            return t
        }
    }

    /// The item nearest to `item` (of envelope `env`), by `itemDistance`
    /// (a tree item first, `item` second): JTS's branch and bound search.
    public func nearestNeighbour(_ env: Envelope, _ item: Item, _ itemDistance: (Item, Item) -> Double) -> Item? {
        if isEmpty { return nil }
        build()
        let initial = BoundablePair(.node(root!), .item(env, item), itemDistance)
        guard let pair = nearestNeighbour(initial, itemDistance), case .item(_, let found) = pair.b1 else { return nil }
        return found
    }

    func nearestNeighbour(_ initial: BoundablePair, _ itemDistance: (Item, Item) -> Double) -> BoundablePair? {
        var distanceLowerBound = Double.infinity
        var minPair: BoundablePair?
        var priQ = PairQueue(tieOrder)
        priQ.add(initial)
        while !priQ.isEmpty && distanceLowerBound > 0.0 {
            let bndPair = priQ.poll()!
            let pairDistance = bndPair.distance
            if pairDistance >= distanceLowerBound { break }
            if bndPair.isLeaves {
                distanceLowerBound = pairDistance
                minPair = bndPair
            } else {
                bndPair.expandToQueue(&priQ, distanceLowerBound, itemDistance)
            }
        }
        return minPair
    }
}
