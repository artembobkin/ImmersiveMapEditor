/// abstutil's `Tags`: a string to string map, iterated in Rust's `BTreeMap`
/// order (by the keys' UTF-8 bytes).

import StreetGeom

/// The revision of osm2streets this target follows.
public enum StreetsPort {
    public static let source = "osm2streets fc119c4"
}

public struct Tags: Equatable, Sendable {
    public private(set) var map: [String: String]

    public init(_ map: [String: String] = [:]) { self.map = map }

    public static func empty() -> Tags { Tags() }

    public func get(_ k: String) -> String? { map[k] }

    public func containsKey(_ k: String) -> Bool { map[k] != nil }

    public func hasAny(_ keys: [String]) -> Bool { keys.contains { containsKey($0) } }

    public func `is`(_ k: String, _ v: String) -> Bool { map[k] == v }

    public func isAny(_ k: String, _ values: [String]) -> Bool {
        guard let v = map[k] else { return false }
        return values.contains(v)
    }

    public mutating func insert(_ k: String, _ v: String) { map[k] = v }

    @discardableResult
    public mutating func remove(_ k: String) -> String? { map.removeValue(forKey: k) }

    public var isEmpty: Bool { map.isEmpty }

    /// The pairs in `BTreeMap` order.
    public func inner() -> [(String, String)] {
        map.keys.sorted(by: rustStringLess).map { ($0, map[$0]!) }
    }
}
