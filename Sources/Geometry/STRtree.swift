import Topology

/// An STR tree over geometries, as shapely's STRtree: `query` gives the
/// indices whose envelopes meet a geometry's, `nearest` the index of the
/// nearest geometry. The port's tree of node capacity 10 with GEOS's ties.
///
/// GEOS's tree held the geometries themselves, and the wrapper found an
/// index by the geometry: a geometry given twice reports its last index,
/// as it did.
public final class STRtree {
    let tree: Topology.STRtree<Int>
    let items: [Geometry]
    /// For each item, the index the wrapper of GEOS reported for it: the
    /// last index of the same geometry.
    let reported: [Int]
    /// Its id in the recording (`Recorder`).
    var recordID: UInt32 = 0

    public init(_ items: [Geometry]) {
        self.items = items
        if let r = Recorder.shared {
            recordID = r.object()
            r.call("STRtree.init", items, [Double(recordID)])
        }
        var last: [ObjectIdentifier: Int] = [:]
        for (i, g) in items.enumerated() { last[ObjectIdentifier(g)] = i }
        reported = items.map { last[ObjectIdentifier($0)]! }
        tree = Topology.STRtree<Int>(nodeCapacity: 10, tieOrder: .geos)
        for (i, g) in items.enumerated() { tree.insert(g.geometry.getEnvelopeInternal(), i) }
    }

    public func query(_ g: Geometry) -> [Int] {
        Recorder.shared?.call("STRtree.query", [g], [Double(recordID)])
        return tree.query(g.geometry.getEnvelopeInternal()).map { reported[$0] }.sorted()
    }

    public func nearest(_ g: Geometry) -> Int? {
        Recorder.shared?.call("STRtree.nearest", [g], [Double(recordID)])
        guard !items.isEmpty else { return nil }
        let found = Failure.attempt(nil) {
            tree.nearestNeighbour(g.geometry.getEnvelopeInternal(), -1) { i, _ in items[i].geometry.distance(g.geometry) }
        }
        return found.map { reported[$0] }
    }
}
