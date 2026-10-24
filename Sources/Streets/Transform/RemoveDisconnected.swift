/// osm2streets's `remove_disconnected_roads`: keeps the largest group of
/// connected roads (a flood fill treating every road as two-way), then
/// drops loops and intersections left without roads.

extension StreetNetwork {
    mutating func removeDisconnectedRoads() {
        var partitions: [[RoadID]] = []
        var unvisited = Set(roads.values.filter { !$0.isLightRail() }.map(\.id))
        while !unvisited.isEmpty {
            var queue = [unvisited.min()!]
            var current: [RoadID] = []
            while let r = queue.popLast() {
                if !unvisited.contains(r) { continue }
                unvisited.remove(r)
                current.append(r)
                for i in roads[r]!.endpoints() { queue.append(contentsOf: intersections[i]!.roads) }
            }
            partitions.append(current)
        }
        // Rust's stable sort by size, then reversed: the largest first, the
        // later of equal sizes before the earlier.
        partitions = Array(partitions.stableSorted { $0.count }.reversed())
        for p in partitions.dropFirst() {
            for id in p { removeRoad(id) }
        }
        retainRoads { $0.srcI != $0.dstI }
        for id in intersections.keys where intersections[id]!.roads.isEmpty { intersections.removeValue(forKey: id) }
    }
}
