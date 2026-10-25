/// A static index of intervals of the line, built at the first query: GEOS
/// 3.13's `TemplateSTRtree` with its `IntervalTraits` (one dimension), which
/// `IndexedPointInAreaLocator` keeps the segments of its rings in (JTS 1.20:
/// a `SortedPackedIntervalRTree`, which answers the same for finite
/// intervals).
///
/// Each level sorts its nodes by `min + max` with libc++'s `std::sort`, cuts
/// them into slices of `ceil(n / ceil(sqrt(ceil(n / capacity))))`, and
/// fills parents of `capacity` children in turn within each slice; a parent
/// spans its children by `std::min` and `std::max` from its first child.
/// The nodes live in one array, a parent's children a range of it. For
/// finite intervals any packing gives the same items to a query; with a NaN
/// end the parents' bounds depend on the order of their children (a NaN
/// first child's end stays, a later one's is passed over), so the packing
/// is GEOS's to the letter.
final class IntervalSTRtree<Item> {
    struct Node {
        var min: Double
        var max: Double
        /// The item of a leaf (its index), -1 for a branch.
        var item: Int
        /// A branch's children: `nodes[first..<end]`.
        var first = 0
        var end = 0
    }

    let nodeCapacity: Int
    @exclusivity(unchecked) private var items: [Item] = []
    @exclusivity(unchecked) private var nodes: [Node] = []
    @exclusivity(unchecked) private var root = -1

    init(nodeCapacity: Int = 10) { self.nodeCapacity = nodeCapacity }

    /// Room for `n` intervals.
    func reserveCapacity(_ n: Int) {
        items.reserveCapacity(n)
        nodes.reserveCapacity(2 * n)
    }

    func insert(_ min: Double, _ max: Double, _ item: Item) {
        precondition(root < 0, "Index cannot be added to once it has been queried")
        nodes.append(Node(min: min, max: max, item: items.count))
        items.append(item)
    }

    private func sliceCount(_ numNodes: Int) -> Int {
        let minLeafCount = (Double(numNodes) / Double(nodeCapacity)).rounded(.up)
        return Int(minLeafCount.squareRoot().rounded(.up))
    }

    private static func sliceCapacity(_ numNodes: Int, _ numSlices: Int) -> Int {
        Int((Double(numNodes) / Double(numSlices)).rounded(.up))
    }

    private func build() {
        if root >= 0 || nodes.isEmpty { return }
        var begin = 0
        var number = nodes.count
        while number > 1 {
            createParentNodes(begin, number)
            begin += number
            number = nodes.count - begin
        }
        root = nodes.count - 1
    }

    private func createParentNodes(_ begin: Int, _ number: Int) {
        let numSlices = sliceCount(number)
        let nodesPerSlice = IntervalSTRtree.sliceCapacity(number, numSlices)
        let end = begin + number
        CxxAlgorithms.sort(&nodes, begin, end) { $0.min + $0.max < $1.min + $1.max }
        var startOfSlice = begin
        for _ in 0..<numSlices {
            let nodesInSlice = Swift.min(end - startOfSlice, nodesPerSlice)
            let endOfSlice = startOfSlice + nodesInSlice
            var firstChild = startOfSlice
            while firstChild != endOfSlice {
                let children = Swift.min(nodeCapacity, endOfSlice - firstChild)
                var node = Node(min: nodes[firstChild].min, max: nodes[firstChild].max, item: -1,
                                first: firstChild, end: firstChild + children)
                for c in (firstChild + 1)..<(firstChild + children) {
                    // Interval::expandToInclude: std::max and std::min.
                    node.max = cxxMax(node.max, nodes[c].max)
                    node.min = cxxMin(node.min, nodes[c].min)
                }
                nodes.append(node)
                firstChild += children
            }
            startOfSlice = endOfSlice
        }
    }

    /// Visits the items whose intervals meet [`min`, `max`]: a node is
    /// passed over when `min > node.max || max < node.min`, so a NaN bound
    /// never excludes it.
    func query(_ min: Double, _ max: Double, _ visit: (Item) -> Void) {
        build()
        if root < 0 { return }
        nodes.withUnsafeBufferPointer { nb in
            items.withUnsafeBufferPointer { ib in
                let r = nb[root]
                if min > r.max || max < r.min { return }
                if r.item >= 0 {
                    visit(ib[r.item])
                } else {
                    IntervalSTRtree.query(nb, ib, root, min, max, visit)
                }
            }
        }
    }

    private static func query(_ nodes: UnsafeBufferPointer<Node>, _ items: UnsafeBufferPointer<Item>, _ i: Int,
                              _ queryMin: Double, _ queryMax: Double, _ visit: (Item) -> Void) {
        let n = nodes[i]
        for c in n.first..<n.end {
            let child = nodes[c]
            if queryMin > child.max || queryMax < child.min { continue }
            if child.item >= 0 {
                visit(items[child.item])
            } else {
                query(nodes, items, c, queryMin, queryMax, visit)
            }
        }
    }
}
