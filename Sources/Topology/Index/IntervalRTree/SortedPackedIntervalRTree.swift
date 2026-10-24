/// A static index of intervals of the line, built once at the first query
/// by pairing neighbours bottom up after sorting by the intervals' middles:
/// JTS's `SortedPackedIntervalRTree` (with its leaf and branch nodes). The
/// nodes live in one array, the children of a branch referred to by index.
public final class SortedPackedIntervalRTree<Item> {
    struct Node {
        var min: Double
        var max: Double
        /// The item of a leaf, nil for a branch.
        var item: Item?
        var child1 = -1
        var child2 = -1
    }

    private var leaves: [Node] = []
    private var nodes: [Node] = []
    private var root = -1

    public init() {}

    public func insert(_ min: Double, _ max: Double, _ item: Item) {
        precondition(root < 0, "Index cannot be added to once it has been queried")
        leaves.append(Node(min: min, max: max, item: item))
    }

    private func build() {
        if root >= 0 || leaves.isEmpty { return }
        // JTS sorts the leaves by their middles with Java's stable sort; the
        // order of equal middles changes no query's set of items.
        let sorted = javaSorted(leaves) { a, b in
            let mid1 = (a.min + a.max) / 2, mid2 = (b.min + b.max) / 2
            return mid1 < mid2 ? -1 : (mid1 > mid2 ? 1 : 0)
        }
        nodes = sorted
        var src = Array(nodes.indices)
        while src.count > 1 {
            var dest: [Int] = []
            var i = 0
            while i < src.count {
                if i + 1 < src.count {
                    let n1 = nodes[src[i]], n2 = nodes[src[i + 1]]
                    nodes.append(Node(min: Swift.min(n1.min, n2.min), max: Swift.max(n1.max, n2.max), item: nil,
                                      child1: src[i], child2: src[i + 1]))
                    dest.append(nodes.count - 1)
                } else {
                    dest.append(src[i])
                }
                i += 2
            }
            src = dest
        }
        root = src[0]
        leaves = []
    }

    /// Visits the items whose intervals meet [`min`, `max`].
    public func query(_ min: Double, _ max: Double, _ visit: (Item) -> Void) {
        build()
        if root < 0 { return }
        query(root, min, max, visit)
    }

    private func query(_ i: Int, _ queryMin: Double, _ queryMax: Double, _ visit: (Item) -> Void) {
        let n = nodes[i]
        if n.min > queryMax || n.max < queryMin { return }
        if let item = n.item {
            visit(item)
            return
        }
        query(n.child1, queryMin, queryMax, visit)
        query(n.child2, queryMin, queryMax, visit)
    }
}
