/// A static index of intervals of the line, built once at the first query
/// by pairing neighbours bottom up after sorting by the intervals' middles:
/// JTS's `SortedPackedIntervalRTree` (with its leaf and branch nodes). The
/// nodes live in one array, the children of a branch referred to by index,
/// the items in another.
///
/// JTS sorts the leaves with Java's stable sort; here the leaves are sorted
/// by Swift's sort of their middles. Leaves of equal middles may come in
/// another order, which changes no query's set of items, and the one user
/// (`IndexedPointInAreaLocator`, counting ray crossings) depends only on
/// the set. GEOS 3.13 indexes the segments in an STR tree there instead.
public final class SortedPackedIntervalRTree<Item> {
    struct Node {
        var min: Double
        var max: Double
        /// The item of a leaf (its index), -1 for a branch.
        var item: Int
        var child1 = -1
        var child2 = -1
    }

    @exclusivity(unchecked) private var items: [Item] = []
    @exclusivity(unchecked) private var mins: [Double] = []
    @exclusivity(unchecked) private var maxs: [Double] = []
    @exclusivity(unchecked) private var nodes: [Node] = []
    @exclusivity(unchecked) private var root = -1

    public init() {}

    /// Room for `n` intervals.
    public func reserveCapacity(_ n: Int) {
        items.reserveCapacity(n)
        mins.reserveCapacity(n)
        maxs.reserveCapacity(n)
    }

    public func insert(_ min: Double, _ max: Double, _ item: Item) {
        precondition(root < 0, "Index cannot be added to once it has been queried")
        items.append(item)
        mins.append(min)
        maxs.append(max)
    }

    private func build() {
        if root >= 0 || items.isEmpty { return }
        let n = items.count
        var order = Array(0..<n)
        mins.withUnsafeBufferPointer { lo in
            maxs.withUnsafeBufferPointer { hi in
                order.sort { (lo[$0] + hi[$0]) / 2 < (lo[$1] + hi[$1]) / 2 }
            }
        }
        nodes.reserveCapacity(2 * n)
        for i in order { nodes.append(Node(min: mins[i], max: maxs[i], item: i)) }
        var src = Array(0..<n)
        var dest: [Int] = []
        dest.reserveCapacity((n + 1) / 2)
        while src.count > 1 {
            dest.removeAll(keepingCapacity: true)
            var i = 0
            while i < src.count {
                if i + 1 < src.count {
                    let n1 = nodes[src[i]], n2 = nodes[src[i + 1]]
                    nodes.append(Node(min: Swift.min(n1.min, n2.min), max: Swift.max(n1.max, n2.max), item: -1,
                                      child1: src[i], child2: src[i + 1]))
                    dest.append(nodes.count - 1)
                } else {
                    dest.append(src[i])
                }
                i += 2
            }
            swap(&src, &dest)
        }
        root = src[0]
        mins = []
        maxs = []
    }

    /// Visits the items whose intervals meet [`min`, `max`].
    public func query(_ min: Double, _ max: Double, _ visit: (Item) -> Void) {
        build()
        if root < 0 { return }
        nodes.withUnsafeBufferPointer { nb in
            items.withUnsafeBufferPointer { ib in
                SortedPackedIntervalRTree.query(nb, ib, root, min, max, visit)
            }
        }
    }

    private static func query(_ nodes: UnsafeBufferPointer<Node>, _ items: UnsafeBufferPointer<Item>, _ i: Int,
                              _ queryMin: Double, _ queryMax: Double, _ visit: (Item) -> Void) {
        let n = nodes[i]
        if n.min > queryMax || n.max < queryMin { return }
        if n.item >= 0 {
            visit(items[n.item])
            return
        }
        query(nodes, items, n.child1, queryMin, queryMax, visit)
        query(nodes, items, n.child2, queryMin, queryMax, visit)
    }
}
