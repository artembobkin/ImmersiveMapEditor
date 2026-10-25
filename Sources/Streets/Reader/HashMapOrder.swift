/// Where the Rust's random `HashMap` order reaches osm2streets's output, made
/// explicit for the parity tests. streets_reader applies traffic signals and
/// crossings to the stop lines of roads by iterating `HashMap`s (random per
/// process), so when two signals, or two crossings, set the same end of the
/// same road, the one met last wins. The port iterates in insertion (node id)
/// order. A `HashMapOrder` lets a test choose which point of each such group
/// comes last, and records the groups the default order meets, so that every
/// order the Rust can take is reproduced and checked, not sampled.

import StreetGeom

final class HashMapOrder {
    /// The points to apply after all others of their map, in their own order.
    var signalsLast: Set<HashablePt2D> = []
    var crossingsLast: Set<HashablePt2D> = []

    /// One road end set by a map: the points that set it, in the order applied.
    struct Group: Hashable {
        var map: String
        var road: RoadID
        var atEnd: Bool
    }
    private(set) var groups: [Group: [HashablePt2D]] = [:]
    private(set) var groupOrder: [Group] = []

    init() {}

    func record(_ map: String, _ road: RoadID, atEnd: Bool, _ pt: HashablePt2D) {
        let g = Group(map: map, road: road, atEnd: atEnd)
        if groups[g] == nil { groupOrder.append(g) }
        if !(groups[g]?.contains(pt) ?? false) { groups[g, default: []].append(pt) }
    }

    /// The groups set by more than one point: the only places the order matters.
    var contested: [(Group, [HashablePt2D])] {
        groupOrder.compactMap { g in groups[g]!.count > 1 ? (g, groups[g]!) : nil }
    }

    /// The entries in the order to apply: the chosen last points after the rest.
    func order<V>(_ entries: [(HashablePt2D, V)], last: Set<HashablePt2D>) -> [(HashablePt2D, V)] {
        entries.filter { !last.contains($0.0) } + entries.filter { last.contains($0.0) }
    }
}
