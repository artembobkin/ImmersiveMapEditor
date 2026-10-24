/// osm2streets's `simple_path`: a driving path between intersections, by
/// petgraph's A* (with a zero estimate) over a `DiGraphMap` of the roads.
/// The graph keeps petgraph's order: a node's outgoing edges in the order
/// first added, a repeated edge only replacing the weight. The open set is
/// Rust's `BinaryHeap` of petgraph's `MinScored`, so equal scores pop in the
/// Rust's order.

import GeoAlgorithms
import StreetGeom

/// petgraph's `DiGraphMap<IntersectionID, (RoadID, Direction)>`, the parts A* reads.
struct DirectedGraphMap {
    private var adjacency: [IntersectionID: [IntersectionID]] = [:]
    private var weights: [Pair<IntersectionID, IntersectionID>: (RoadID, Direction)] = [:]

    mutating func addEdge(_ a: IntersectionID, _ b: IntersectionID, _ weight: (RoadID, Direction)) {
        let key = Pair(a, b)
        if weights.updateValue(weight, forKey: key) == nil { adjacency[a, default: []].append(b) }
    }

    func edges(_ a: IntersectionID) -> [(IntersectionID, (RoadID, Direction))] {
        (adjacency[a] ?? []).map { ($0, weights[Pair(a, $0)]!) }
    }

    func edgeWeight(_ a: IntersectionID, _ b: IntersectionID) -> (RoadID, Direction)? { weights[Pair(a, b)] }
}


extension StreetNetwork {
    /// A driving path from one intersection to another, with the direction
    /// each road is crossed in.
    public func simplePath(_ from: IntersectionID, _ to: IntersectionID, _ laneTypes: [LaneType]) -> [(RoadID, Direction)]? {
        var graph = DirectedGraphMap()
        for r in roads.values {
            var fwd = false
            var back = false
            for lane in r.laneSpecsLTR where laneTypes.contains(lane.lt) {
                if lane.dir == .forward { fwd = true } else { back = true }
            }
            if fwd { graph.addEdge(r.srcI, r.dstI, (r.id, .forward)) }
            if back { graph.addEdge(r.dstI, r.srcI, (r.id, .backward)) }
        }
        guard let path = astar(graph, from, to) else { return nil }
        var result: [(RoadID, Direction)] = []
        if path.count >= 2 {
            for k in 1..<path.count { result.append(graph.edgeWeight(path[k - 1], path[k])!) }
        }
        return result
    }

    /// petgraph's `astar` with an estimate of zero and a road's untrimmed length as the cost.
    private func astar(_ graph: DirectedGraphMap, _ start: IntersectionID, _ goal: IntersectionID) -> [IntersectionID]? {
        typealias Scored = (Distance, IntersectionID)
        // `MinScored`: the lower score is the greater.
        var visitNext = RustBinaryHeap<Scored, Never>(cmp: { a, b in
            a.0 == b.0 ? .equal : (a.0 < b.0 ? .greater : .less)
        })
        var scores: [IntersectionID: Distance] = [start: .zero]
        var estimateScores: [IntersectionID: Distance] = [:]
        var cameFrom: [IntersectionID: IntersectionID] = [:]
        visitNext.push((.zero, start))
        while let (estimateScore, node) = visitNext.pop() {
            if node == goal {
                var path = [node]
                var current = node
                while let previous = cameFrom[current] {
                    path.append(previous)
                    current = previous
                }
                return path.reversed()
            }
            let nodeScore = scores[node]!
            if let existing = estimateScores[node], existing <= estimateScore { continue }
            estimateScores[node] = estimateScore
            for (next, weight) in graph.edges(node) {
                let nextScore = nodeScore + roads[weight.0]!.untrimmedLength()
                if let existing = scores[next], existing <= nextScore { continue }
                scores[next] = nextScore
                cameFrom[next] = node
                visitNext.push((nextScore + .zero, next))
            }
        }
        return nil
    }
}
