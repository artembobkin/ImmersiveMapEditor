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
    private var root: Node?

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
        guard root!.bounds.intersects(searchEnv) else { return }
        queryInternal(searchEnv, root!, visit)
    }

    func queryInternal(_ searchEnv: Envelope, _ node: Node, _ visit: (Item) -> Void) {
        for child in node.children {
            guard child.bounds.intersects(searchEnv) else { continue }
            switch child {
            case .node(let n): queryInternal(searchEnv, n, visit)
            case .item(_, let item): visit(item)
            }
        }
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
