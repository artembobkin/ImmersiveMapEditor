/// The ids of a street network (opaque, not contiguous) and the small types
/// that pair them: `CommonEndpoint`, `SideOfRoad`, `RoadSideID`.

import OSMReader

public struct RoadID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var id: Int
    public init(_ id: Int) { self.id = id }
    public static func < (a: RoadID, b: RoadID) -> Bool { a.id < b.id }
    public var description: String { "Road #\(id)" }
}

public struct IntersectionID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var id: Int
    public init(_ id: Int) { self.id = id }
    public static func < (a: IntersectionID, b: IntersectionID) -> Bool { a.id < b.id }
    public var description: String { "Intersection #\(id)" }
}

/// Whether two roads share one endpoint, both or none.
public enum CommonEndpoint: Equatable {
    case one(IntersectionID)
    case both
    case none

    public init(_ obj1: (IntersectionID, IntersectionID), _ obj2: (IntersectionID, IntersectionID)) {
        let src = obj1.0 == obj2.0 || obj1.0 == obj2.1
        let dst = obj1.1 == obj2.0 || obj1.1 == obj2.1
        if src && dst { self = .both } else if src { self = .one(obj1.0) } else if dst { self = .one(obj1.1) } else {
            self = .none
        }
    }
}

public enum SideOfRoad: Int, Hashable, Comparable, Sendable {
    case left, right
    public func opposite() -> SideOfRoad { self == .left ? .right : .left }
    public static func < (a: SideOfRoad, b: SideOfRoad) -> Bool { a.rawValue < b.rawValue }
}

public struct RoadSideID: Hashable, Sendable {
    public var road: RoadID
    public var side: SideOfRoad
}

/// A restriction on turns: banned, or the only ones allowed.
public enum RestrictionType: Int, Hashable, Comparable, Sendable {
    case banTurns, onlyAllowTurns

    public static func < (a: RestrictionType, b: RestrictionType) -> Bool { a.rawValue < b.rawValue }

    /// Buckets an OSM `restriction` value into ban or allow.
    public static func new(_ restriction: String) -> RestrictionType? {
        if restriction.contains("no_") || restriction == "psv" { return .banTurns }
        if restriction.contains("only_") { return .onlyAllowTurns }
        return nil
    }
}
