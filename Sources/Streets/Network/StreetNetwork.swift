/// osm2streets's `StreetNetwork`: the roads and intersections, kept in
/// Rust's `BTreeMap` order (by id), with the operations that keep their
/// links consistent.

import StreetGeom

/// A map ordered by key, iterated as a Rust `BTreeMap`.
public struct SortedMap<K: Comparable & Hashable, V> {
    private var storage: [K: V] = [:]
    private var sortedKeys: [K] = []

    public init() {}

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var keys: [K] { sortedKeys }
    public var values: [V] { sortedKeys.map { storage[$0]! } }

    public subscript(key: K) -> V? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { insertKey(key) }
            } else {
                removeValue(forKey: key)
            }
        }
    }

    public func contains(_ key: K) -> Bool { storage[key] != nil }

    @discardableResult
    public mutating func removeValue(forKey key: K) -> V? {
        guard let v = storage.removeValue(forKey: key) else { return nil }
        let i = lowerBound(key)
        sortedKeys.remove(at: i)
        return v
    }

    /// Mutates a value in place. The key must exist.
    public mutating func modify(_ key: K, _ body: (inout V) -> Void) {
        body(&storage[key]!)
    }

    private func lowerBound(_ key: K) -> Int {
        var lo = 0
        var hi = sortedKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedKeys[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private mutating func insertKey(_ key: K) {
        if let last = sortedKeys.last, last < key {
            sortedKeys.append(key)
        } else {
            sortedKeys.insert(key, at: lowerBound(key))
        }
    }
}

public struct StreetNetwork {
    public var roads = SortedMap<RoadID, Road>()
    public var intersections = SortedMap<IntersectionID, Intersection>()
    public var boundaryPolygon: Polygon
    public var gpsBounds: GPSBounds
    public var config: MapConfig
    /// Where the lanes of a new road come from (osm2lanes's `get_lane_specs_ltr`).
    public var laneSpecs: LaneSpecSource

    /// Tests only: the order of the Rust's `HashMap`s (`HashMapOrder`).
    var hashMapOrder: HashMapOrder?

    var intersectionIDCounter = 0
    var roadIDCounter = 0

    public static func blank(laneSpecs: LaneSpecSource = MuvLaneSpecs()) -> StreetNetwork {
        StreetNetwork(boundaryPolygon: .rectangle(1.0, 1.0), gpsBounds: GPSBounds(), config: MapConfig(),
                      laneSpecs: laneSpecs)
    }

    public func road(_ id: RoadID) -> Road { roads[id]! }
    public func intersection(_ id: IntersectionID) -> Intersection { intersections[id]! }

    public mutating func insertRoad(_ road: Road) {
        let endpts = road.endpoints()
        let id = road.id
        roads[road.id] = road
        for i in endpts {
            intersections.modify(i) { $0.roads.append(id) }
            sortRoads(i)
            updateI(i)
        }
    }

    @discardableResult
    public mutating func removeRoad(_ id: RoadID) -> Road {
        for i in roads[id]!.endpoints() {
            intersections.modify(i) { $0.roads.removeAll { $0 == id } }
            // The roads are already sorted, removing doesn't break the sort.
            updateI(i)
        }
        return roads.removeValue(forKey: id)!
    }

    public mutating func retainRoads(_ f: (Road) -> Bool) {
        var remove: [RoadID] = []
        for r in roads.values where !f(r) { remove.append(r.id) }
        for id in remove { removeRoad(id) }
    }

    public mutating func removeIntersection(_ id: IntersectionID) {
        let i = intersections.removeValue(forKey: id)!
        precondition(i.roads.isEmpty, "Can't remove_intersection(\(id)), it has roads still connected")
    }

    /// The roads of an intersection, clockwise.
    public func roadsPerIntersection(_ i: IntersectionID) -> [Road] {
        intersections[i]!.roads.map { roads[$0]! }
    }

    public mutating func nextRoadID() -> RoadID {
        let id = RoadID(roadIDCounter)
        roadIDCounter += 1
        return id
    }

    public mutating func nextIntersectionID() -> IntersectionID {
        let id = IntersectionID(intersectionIDCounter)
        intersectionIDCounter += 1
        return id
    }
}
