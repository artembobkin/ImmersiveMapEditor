/// A 2-d tree of points, splitting on x and y in turn: JTS's `KdTree` and
/// `KdNode`. A point within `tolerance` of a node already in the tree is
/// counted on it instead of inserted. The nodes live in one array, referred
/// to by index.
public final class KdTree<Data> {
    public struct Node {
        public let coordinate: Coordinate
        public let data: Data?
        public internal(set) var count = 1
        var left = -1
        var right = -1

        public var isRepeated: Bool { count > 1 }

        func splitValue(_ isSplitOnX: Bool) -> Double { isSplitOnX ? coordinate.x : coordinate.y }

        func isRangeOverLeft(_ isSplitOnX: Bool, _ env: Envelope) -> Bool {
            (isSplitOnX ? env.minX : env.minY) < splitValue(isSplitOnX)
        }

        func isRangeOverRight(_ isSplitOnX: Bool, _ env: Envelope) -> Bool {
            splitValue(isSplitOnX) <= (isSplitOnX ? env.maxX : env.maxY)
        }

        func isPointOnLeft(_ isSplitOnX: Bool, _ pt: Coordinate) -> Bool {
            (isSplitOnX ? pt.x : pt.y) < splitValue(isSplitOnX)
        }
    }

    @exclusivity(unchecked) public private(set) var nodes: [Node] = []
    /// The stack of the range queries, kept to spare an allocation each.
    @exclusivity(unchecked) private var queryStack: [(Int, Bool)] = []
    let tolerance: Double

    public init(tolerance: Double = 0.0) { self.tolerance = tolerance }

    public var isEmpty: Bool { nodes.isEmpty }
    public var size: Int { nodes.count }

    /// Inserts a point: the index of its node, new or the one it matched.
    @discardableResult
    public func insert(_ p: Coordinate, _ data: Data? = nil) -> Int {
        if nodes.isEmpty {
            nodes.append(Node(coordinate: p, data: data))
            return 0
        }
        if tolerance > 0, let match = findBestMatchNode(p) {
            nodes[match].count += 1
            return match
        }
        return insertExact(p, data)
    }

    /// The node within tolerance nearest to `p`, the least coordinate of
    /// equally near ones.
    func findBestMatchNode(_ p: Coordinate) -> Int? {
        var queryEnv = Envelope(p)
        queryEnv.expandBy(tolerance)
        var matchNode: Int?
        var matchDist = 0.0
        query(queryEnv) { i in
            let dist = p.distance(nodes[i].coordinate)
            guard dist <= tolerance else { return }
            if matchNode == nil || dist < matchDist
                || (dist == matchDist && nodes[i].coordinate.compareTo(nodes[matchNode!].coordinate) < 1) {
                matchNode = i
                matchDist = dist
            }
        }
        return matchNode
    }

    func insertExact(_ p: Coordinate, _ data: Data?) -> Int {
        var current = 0
        var leaf = 0
        var isXLevel = true
        var isLessThan = true
        while current >= 0 {
            if p.distance(nodes[current].coordinate) <= tolerance {
                nodes[current].count += 1
                return current
            }
            let split = nodes[current].splitValue(isXLevel)
            isLessThan = isXLevel ? p.x < split : p.y < split
            leaf = current
            current = isLessThan ? nodes[current].left : nodes[current].right
            isXLevel = !isXLevel
        }
        nodes.append(Node(coordinate: p, data: data))
        let index = nodes.count - 1
        if isLessThan { nodes[leaf].left = index } else { nodes[leaf].right = index }
        return index
    }

    /// Visits every node in `queryEnv`, in JTS's order (an in-order walk with
    /// an explicit stack).
    public func query(_ queryEnv: Envelope, _ visit: (Int) -> Void) {
        if nodes.isEmpty { return }
        // The stack is the tree's own, kept between queries.
        var stack = queryStack
        stack.removeAll(keepingCapacity: true)
        defer { queryStack = stack }
        var current = 0
        var isXLevel = true
        while true {
            if current >= 0 {
                stack.append((current, isXLevel))
                if nodes[current].isRangeOverLeft(isXLevel, queryEnv) {
                    current = nodes[current].left
                    if current >= 0 { isXLevel = !isXLevel }
                } else {
                    current = -1
                }
            } else if let frame = stack.popLast() {
                current = frame.0
                isXLevel = frame.1
                if queryEnv.contains(nodes[current].coordinate) { visit(current) }
                if nodes[current].isRangeOverRight(isXLevel, queryEnv) {
                    current = nodes[current].right
                    if current >= 0 { isXLevel = !isXLevel }
                } else {
                    current = -1
                }
            } else {
                return
            }
        }
    }

    public func query(_ queryEnv: Envelope) -> [Int] {
        var r: [Int] = []
        query(queryEnv) { r.append($0) }
        return r
    }

    /// The node at exactly `queryPt`, if any.
    public func query(_ queryPt: Coordinate) -> Int? {
        if nodes.isEmpty { return nil }
        var current = 0
        var isXLevel = true
        while current >= 0 {
            if nodes[current].coordinate.equals2D(queryPt) { return current }
            current = nodes[current].isPointOnLeft(isXLevel, queryPt) ? nodes[current].left : nodes[current].right
            isXLevel = !isXLevel
        }
        return nil
    }

    public func depth() -> Int {
        func d(_ i: Int) -> Int { i < 0 ? 0 : 1 + max(d(nodes[i].left), d(nodes[i].right)) }
        return d(nodes.isEmpty ? -1 : 0)
    }
}
