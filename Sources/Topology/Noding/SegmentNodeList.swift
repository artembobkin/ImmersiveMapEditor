/// The nodes of a segment string, sorted along it (a `TreeMap` in JTS: a
/// sorted array here), and the split edges between them: JTS's
/// `SegmentNodeList`.
public final class SegmentNodeList {
    private(set) var nodes: [SegmentNode] = []
    unowned let edge: NodedSegmentString

    init(_ edge: NodedSegmentString) { self.edge = edge }

    public func size() -> Int { nodes.count }
    public func getEdge() -> NodedSegmentString { edge }

    /// The node at a point of a segment, added if it is not there.
    @discardableResult
    public func add(_ intPt: Coordinate, _ segmentIndex: Int) -> SegmentNode {
        let n = SegmentNode(edge, intPt, segmentIndex, edge.getSegmentOctant(segmentIndex))
        var lo = 0, hi = nodes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let c = nodes[mid].compareTo(n)
            if c == 0 {
                precondition(nodes[mid].coord.equals2D(intPt), "Found equal nodes with different coordinates")
                return nodes[mid]
            }
            if c < 0 { lo = mid + 1 } else { hi = mid }
        }
        nodes.insert(n, at: lo)
        return n
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
        guard var prev = nodes.first else { return }
        for ei in nodes.dropFirst() {
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
        var prev = nodes[0]
        for ei in nodes.dropFirst() {
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
        var list: [Coordinate] = []
        var prev = nodes[0]
        for ei in nodes.dropFirst() {
            for p in createSplitEdgePts(prev, ei) where list.last != p { list.append(p) }
            prev = ei
        }
        return list
    }
}
