/// The nodes of a segment string, sorted along it, and the split edges
/// between them: JTS's `SegmentNodeList`.
///
/// JTS keeps the nodes in a `TreeMap`, so the first of two equal nodes
/// stays. GEOS 3.13, as its results show, appends them as they come, sorts
/// them with libc++'s `std::sort` when they are next read and drops the
/// duplicates, keeping the first of each run of equal nodes. Which of two
/// equal nodes (`0.0` and `-0.0`) stays follows from that, so the port does
/// the same, with the sort translated in `CxxAlgorithms`.
public final class SegmentNodeList {
    @exclusivity(unchecked) private var nodes: [SegmentNode] = []
    /// Whether `nodes` is sorted and free of duplicates.
    @exclusivity(unchecked) private var ready = true
    /// The string the list belongs to, which owns the list.
    unowned(unsafe) let edge: NodedSegmentString

    init(_ edge: NodedSegmentString) { self.edge = edge }

    /// The nodes in order along the string, each once.
    var sortedNodes: [SegmentNode] {
        prepare()
        return nodes
    }

    public func size() -> Int {
        prepare()
        return nodes.count
    }

    public func getEdge() -> NodedSegmentString { edge }

    /// Adds a node at a point of a segment (a duplicate goes when the list
    /// is next read).
    @discardableResult
    public func add(_ intPt: Coordinate, _ segmentIndex: Int) -> SegmentNode {
        let n = SegmentNode(edge, intPt, segmentIndex, edge.getSegmentOctant(segmentIndex))
        nodes.append(n)
        ready = false
        return n
    }

    private func prepare() {
        if ready { return }
        CxxAlgorithms.sort(&nodes) { $0.compareTo($1) < 0 }
        var unique: [SegmentNode] = []
        unique.reserveCapacity(nodes.count)
        for n in nodes where unique.last.map({ $0.compareTo(n) != 0 }) ?? true { unique.append(n) }
        nodes = unique
        ready = true
    }

    func addEndpoints() {
        let maxSegIndex = edge.size() - 1
        add(edge.getCoordinate(0), 0)
        add(edge.getCoordinate(maxSegIndex), maxSegIndex)
    }

    /// Nodes at the vertices where the string doubles back on itself, so the
    /// split edges do not collapse.
    func addCollapsedNodes() {
        var collapsed: [Int] = []
        findCollapsesFromInsertedNodes(&collapsed)
        findCollapsesFromExistingVertices(&collapsed)
        for i in collapsed { add(edge.getCoordinate(i), i) }
    }

    func findCollapsesFromExistingVertices(_ collapsed: inout [Int]) {
        guard edge.size() > 2 else { return }
        for i in 0..<(edge.size() - 2) where edge.getCoordinate(i).equals2D(edge.getCoordinate(i + 2)) {
            collapsed.append(i + 1)
        }
    }

    func findCollapsesFromInsertedNodes(_ collapsed: inout [Int]) {
        let sorted = sortedNodes
        guard var prev = sorted.first else { return }
        for ei in sorted.dropFirst() {
            if let i = findCollapseIndex(prev, ei) { collapsed.append(i) }
            prev = ei
        }
    }

    func findCollapseIndex(_ ei0: SegmentNode, _ ei1: SegmentNode) -> Int? {
        if !ei0.coord.equals2D(ei1.coord) { return nil }
        var between = ei1.segmentIndex - ei0.segmentIndex
        if !ei1.isInterior { between -= 1 }
        return between == 1 ? ei0.segmentIndex + 1 : nil
    }

    /// The edges between consecutive nodes, endpoints included.
    public func addSplitEdges(_ edgeList: inout [SegmentString]) {
        addEndpoints()
        addCollapsedNodes()
        let sorted = sortedNodes
        var prev = sorted[0]
        for ei in sorted.dropFirst() {
            edgeList.append(NodedSegmentString(createSplitEdgePts(prev, ei), edge.getData()))
            prev = ei
        }
    }

    func createSplitEdgePts(_ ei0: SegmentNode, _ ei1: SegmentNode) -> [Coordinate] {
        var npts = ei1.segmentIndex - ei0.segmentIndex + 2
        if npts == 2 { return [ei0.coord, ei1.coord] }
        let lastSegStartPt = edge.getCoordinate(ei1.segmentIndex)
        let useIntPt1 = ei1.isInterior || !ei1.coord.equals2D(lastSegStartPt)
        if !useIntPt1 { npts -= 1 }
        var pts: [Coordinate] = []
        pts.reserveCapacity(npts)
        pts.append(ei0.coord)
        if ei0.segmentIndex + 1 <= ei1.segmentIndex {
            for i in (ei0.segmentIndex + 1)...ei1.segmentIndex { pts.append(edge.getCoordinate(i)) }
        }
        if useIntPt1 { pts.append(ei1.coord) }
        return pts
    }

    /// The string's coordinates with every node in place, no point repeated
    /// in a row.
    public func getSplitCoordinates() -> [Coordinate] {
        addEndpoints()
        let sorted = sortedNodes
        var list: [Coordinate] = []
        var prev = sorted[0]
        // GEOS 3.13 starts with the first node paired with itself (two points,
        // JTS skips it): the same for finite nodes, which are then repeated
        // and dropped, while a NaN node, never equal to itself, stays twice.
        for ei in sorted {
            for p in createSplitEdgePts(prev, ei) where list.last != p { list.append(p) }
            prev = ei
        }
        return list
    }
}
