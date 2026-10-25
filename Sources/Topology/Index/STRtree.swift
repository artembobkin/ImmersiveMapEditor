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
        @exclusivity(unchecked) var children: [Boundable] = []
        /// For a node of the lowest level, the index of its first item
        /// among the leaves in the order the tree packed them.
        @exclusivity(unchecked) var firstLeaf = 0
        @exclusivity(unchecked) private var cached: Envelope?

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
    /// The items as inserted, before the tree is built.
    @exclusivity(unchecked) private var items: [(Envelope, Item)] = []
    @exclusivity(unchecked) private var isBuilt = false
    /// The items in the order the tree packed them (sorted by x, then each
    /// slice by y), the order GEOS keeps its leaves in.
    @exclusivity(unchecked) private var leaves: [(Envelope, Item)] = []
    /// The built tree in one array for the queries: each node's children
    /// next to each other, in their order (`flat[0]` the root). An entry
    /// with `item >= 0` is an item, its index among `leaves`.
    private struct FlatEntry {
        var env: Envelope
        var first = 0
        var count = 0
        var item = -1
    }
    @exclusivity(unchecked) private var flat: [FlatEntry] = []
    /// The tree as nodes, made from `flat` for the nearest neighbour search.
    @exclusivity(unchecked) private var nodeRoot: Node?

    public init(nodeCapacity: Int = 10, tieOrder: TieOrder = .geos) {
        precondition(nodeCapacity > 1, "Node capacity must be greater than 1")
        self.nodeCapacity = nodeCapacity
        self.tieOrder = tieOrder
    }

    /// Adds an item. One with a null envelope is not indexed, as in JTS.
    public func insert(_ env: Envelope, _ item: Item) {
        precondition(!isBuilt, "Cannot insert items into an STR packed R-tree after it has been built.")
        if env.isNull { return }
        items.append((env, item))
    }

    // MARK: Building

    /// A node of a level while the tree is packed: its envelope and its
    /// children, a range of the level's child list (indices into the level
    /// below; for the lowest level, into the items).
    private struct PackNode {
        var env: Envelope
        var first: Int
        var count: Int
    }

    /// Packs the tree, as JTS's `AbstractSTRtree` packs it, into value
    /// arrays: level by level, the boundables sorted by the x of their
    /// centre, cut into vertical slices, each slice sorted by the y of the
    /// centre and packed into nodes of `nodeCapacity`, until one node is
    /// left. The sorts see the same sequences and the same comparisons as
    /// JTS's (or libc++'s) sort of the boundables, so the packing is theirs.
    public func build() {
        if isBuilt { return }
        isBuilt = true
        flat = []
        if items.isEmpty {
            flat = [FlatEntry(env: Envelope())]
            return
        }
        var levels: [(nodes: [PackNode], children: [Int])] = []
        // The boundables of the level below: their envelopes, by index.
        var envs = items.map(\.0)
        var level = 0
        while true {
            var nodes: [PackNode] = []
            var children: [Int] = []
            let n = envs.count
            children.reserveCapacity(n)
            nodes.reserveCapacity(n / nodeCapacity + Int(Double(n).squareRoot()) + 2)
            let minLeafCount = Int((Double(n) / Double(nodeCapacity)).rounded(.up))
            let sliceCount = Int(Double(minLeafCount).squareRoot().rounded(.up))
            var order = Array(0..<n)
            // The centres once per level: the comparisons see the same values.
            let centreX = envs.map { ($0.minX + $0.maxX) / 2 }, centreY = envs.map { ($0.minY + $0.maxY) / 2 }
            sortIndices(&order, centreX)
            let sliceCapacity = Int((Double(n) / Double(sliceCount)).rounded(.up))
            var i = 0
            for _ in 0..<sliceCount {
                let end = min(n, i + sliceCapacity)
                var slice = Array(order[i..<end])
                i = end
                // An empty slice gives one empty node in JTS; only the last
                // slices can be empty, and only when n is small (JTS asserts
                // a slice is not empty).
                precondition(!slice.isEmpty)
                sortIndices(&slice, centreY)
                var k = 0
                while k < slice.count {
                    let count = min(nodeCapacity, slice.count - k)
                    var env = envs[slice[k]]
                    for c in (k + 1)..<(k + count) { env.expandToInclude(envs[slice[c]]) }
                    nodes.append(PackNode(env: env, first: children.count, count: count))
                    children.append(contentsOf: slice[k..<(k + count)])
                    k += count
                }
            }
            levels.append((nodes, children))
            if nodes.count == 1 { break }
            envs = nodes.map(\.env)
            level += 1
        }
        // The leaves in packed order: the items of the lowest level's nodes.
        let lowest = levels[0]
        var firstLeaf = [Int](repeating: 0, count: lowest.nodes.count)
        leaves.reserveCapacity(items.count)
        for (k, node) in lowest.nodes.enumerated() {
            firstLeaf[k] = leaves.count
            for c in node.first..<(node.first + node.count) { leaves.append(items[lowest.children[c]]) }
        }
        items = []
        // The flat tree, breadth first from the root, as the nodes had it.
        let top = levels.count - 1
        flat.reserveCapacity(leaves.count + levels.reduce(0) { $0 + $1.nodes.count })
        flat.append(FlatEntry(env: levels[top].nodes[0].env))
        var queue: [(flatIndex: Int, level: Int, node: Int)] = [(0, top, 0)]
        queue.reserveCapacity(levels.reduce(0) { $0 + $1.nodes.count })
        var head = 0
        while head < queue.count {
            let (idx, lvl, nodeIndex) = queue[head]
            head += 1
            let node = levels[lvl].nodes[nodeIndex]
            let first = flat.count
            for c in node.first..<(node.first + node.count) {
                let child = levels[lvl].children[c]
                if lvl == 0 {
                    flat.append(FlatEntry(env: leaves[firstLeaf[nodeIndex] + (c - node.first)].0, item: firstLeaf[nodeIndex] + (c - node.first)))
                } else {
                    flat.append(FlatEntry(env: levels[lvl - 1].nodes[child].env))
                    queue.append((flat.count - 1, lvl - 1, child))
                }
            }
            flat[idx].first = first
            flat[idx].count = node.count
        }
    }

    /// Sorts indices by their keys, ties as the tree breaks them.
    private func sortIndices(_ a: inout [Int], _ keys: [Double]) {
        keys.withUnsafeBufferPointer { k in
            switch tieOrder {
            case .jts: a = javaSorted(a) { STRtree.compareDoubles(k[$0], k[$1]) }
            case .geos: CxxAlgorithms.sort(&a) { k[$0] < k[$1] }
            }
        }
    }


    public var isEmpty: Bool { isBuilt ? leaves.isEmpty : items.isEmpty }

    public var size: Int { isBuilt ? leaves.count : items.count }

    static func compareDoubles(_ a: Double, _ b: Double) -> Int { a > b ? 1 : (a < b ? -1 : 0) }

    /// The tree as nodes, for the nearest neighbour search.
    private func nodes() -> Node {
        if let n = nodeRoot { return n }
        func make(_ idx: Int, _ level: Int) -> Node {
            let node = Node(level: level)
            let e = flat[idx]
            for c in e.first..<(e.first + e.count) {
                let ch = flat[c]
                node.children.append(ch.item >= 0 ? .item(ch.env, leaves[ch.item].1) : .node(make(c, level - 1)))
            }
            return node
        }
        let n = make(0, 0)
        nodeRoot = n
        return n
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
            guard ch.env.intersectsNonNull(searchEnv) else { continue }
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
        leaves.withUnsafeBufferPointer { l in
            queryPairIndices { visit(l[$0].1, l[$1].1) }
        }
    }

    /// `queryPairs` by the items' positions in the packed order
    /// (`itemsInPackedOrder`), for callers that keep the items themselves.
    public func queryPairIndices(_ visit: (Int, Int) -> Bool) {
        build()
        guard leaves.count >= 2 else { return }
        flat.withUnsafeBufferPointer { f in
            leaves.withUnsafeBufferPointer { l in
                for i in l.indices { _ = STRtree.queryPairsFlat(f, i, l[i].0, 0, visit) }
            }
        }
    }

    private static func queryPairsFlat(_ f: UnsafeBufferPointer<FlatEntry>, _ i: Int, _ queryEnv: Envelope, _ idx: Int,
                                       _ visit: (Int, Int) -> Bool) -> Bool {
        let e = f[idx]
        for c in e.first..<(e.first + e.count) {
            let ch = f[c]
            if ch.item >= 0 {
                if ch.item > i && ch.env.intersectsNonNull(queryEnv) && !visit(i, ch.item) { return false }
            } else if ch.env.intersectsNonNull(queryEnv) && !queryPairsFlat(f, i, queryEnv, c, visit) {
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

        func expandToQueue(_ priQ: inout PairQueue, _ minDistance: Double, _ geos: Bool,
                           _ itemDistance: (Item, Item) -> Double) {
            switch (b1, b2) {
            case (.node(let n1), .node(let n2)):
                if n1.bounds.area > n2.bounds.area {
                    expand(n1, b2, false, &priQ, minDistance, geos, itemDistance)
                } else {
                    expand(n2, b1, true, &priQ, minDistance, geos, itemDistance)
                }
            case (.node(let n1), _): expand(n1, b2, false, &priQ, minDistance, geos, itemDistance)
            case (_, .node(let n2)): expand(n2, b1, true, &priQ, minDistance, geos, itemDistance)
            default: preconditionFailure("neither boundable is composite")
            }
        }

        func expand(_ composite: Node, _ other: Boundable, _ isFlipped: Bool, _ priQ: inout PairQueue,
                    _ minDistance: Double, _ geos: Bool, _ itemDistance: (Item, Item) -> Double) {
            for child in composite.children {
                let bp = isFlipped ? BoundablePair(other, child, itemDistance) : BoundablePair(child, other, itemDistance)
                if (geos && minDistance == .infinity) || bp.distance < minDistance { priQ.add(bp) }
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
        let initial = BoundablePair(.node(nodes()), .item(env, item), itemDistance)
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
            // GEOS stops only once it has a pair, and keeps pairs of any
            // distance while the bound is infinite (`expand`): the same for
            // finite distances, apart for infinite and NaN ones.
            if (tieOrder == .jts || minPair != nil) && pairDistance >= distanceLowerBound { break }
            if bndPair.isLeaves {
                distanceLowerBound = pairDistance
                minPair = bndPair
            } else {
                bndPair.expandToQueue(&priQ, distanceLowerBound, tieOrder == .geos, itemDistance)
            }
        }
        return minPair
    }
}
