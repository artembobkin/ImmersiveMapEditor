/// osm2lanes's lane vocabulary: `LaneType`, `BufferType`, `ParkingType`,
/// `Direction`, `TurnDirection`, `TrafficClass`, and what each kind of lane
/// supports.

import StreetGeom

public enum BufferType: Int, Hashable, Comparable, Sendable, CaseIterable {
    case stripes, flexPosts, planters, jerseyBarrier, curb, verge

    public static func < (a: BufferType, b: BufferType) -> Bool { a.rawValue < b.rawValue }

    var rustName: String {
        switch self {
        case .stripes: return "Stripes"
        case .flexPosts: return "FlexPosts"
        case .planters: return "Planters"
        case .jerseyBarrier: return "JerseyBarrier"
        case .curb: return "Curb"
        case .verge: return "Verge"
        }
    }
}

public enum ParkingType: Int, Hashable, Comparable, Sendable, CaseIterable {
    case parallel, diagonal, perpendicular

    public static func < (a: ParkingType, b: ParkingType) -> Bool { a.rawValue < b.rawValue }

    var rustName: String {
        switch self {
        case .parallel: return "Parallel"
        case .diagonal: return "Diagonal"
        case .perpendicular: return "Perpendicular"
        }
    }
}

public enum LaneType: Hashable, Sendable {
    case driving
    case parking(ParkingType)
    case sidewalk
    /// Walkable like a sidewalk, but very narrow.
    case shoulder
    case biking
    case bus
    case sharedLeftTurn
    case construction
    case lightRail
    case buffer(BufferType)
    /// A pedestrian-only path unassociated with a road.
    case footway
    /// A shared pedestrian and bicycle space.
    case sharedUse

    public func isForMovingVehicles() -> Bool {
        switch self {
        case .driving, .biking, .bus, .lightRail, .sharedUse: return true
        default: return false
        }
    }

    public func supportsAnyMovement() -> Bool {
        switch self {
        case .driving, .biking, .bus, .sidewalk, .shoulder, .lightRail, .footway, .sharedUse: return true
        default: return false
        }
    }

    /// Travel lanes represented in OSM `*:lanes` tags.
    public func isTaggedByLanesSuffix() -> Bool {
        switch self {
        case .driving, .biking, .bus, .sharedLeftTurn, .construction: return true
        default: return false
        }
    }

    /// Part of the roadway, the contiguous sealed surface mappers call the road.
    public func isRoadway() -> Bool {
        switch self {
        case .driving, .biking, .bus, .parking, .shoulder, .sharedLeftTurn, .construction, .lightRail: return true
        case .buffer(.curb), .buffer(.verge): return false
        case .buffer: return true
        case .sidewalk, .footway, .sharedUse: return false
        }
    }

    public func isWalkable() -> Bool {
        switch self {
        case .sidewalk, .shoulder, .footway, .sharedUse: return true
        default: return false
        }
    }

    public func trafficClass() -> TrafficClass? {
        switch self {
        case .footway, .sidewalk: return .pedestrian
        case .sharedUse, .biking: return .bicycle
        case .bus, .sharedLeftTurn, .driving: return .motor
        case .lightRail: return .rail
        case .buffer, .shoulder, .construction, .parking: return nil
        }
    }

    /// Rust's derived `Debug`, which the GeoJSON writes as the lane's `type`.
    public var rustDebug: String {
        switch self {
        case .driving: return "Driving"
        case .parking(let p): return "Parking(\(p.rustName))"
        case .sidewalk: return "Sidewalk"
        case .shoulder: return "Shoulder"
        case .biking: return "Biking"
        case .bus: return "Bus"
        case .sharedLeftTurn: return "SharedLeftTurn"
        case .construction: return "Construction"
        case .lightRail: return "LightRail"
        case .buffer(let b): return "Buffer(\(b.rustName))"
        case .footway: return "Footway"
        case .sharedUse: return "SharedUse"
        }
    }

    /// The inverse of `rustDebug`.
    public static func fromRustDebug(_ text: String) -> LaneType? {
        for p in ParkingType.allCases where text == "Parking(\(p.rustName))" { return .parking(p) }
        for b in BufferType.allCases where text == "Buffer(\(b.rustName))" { return .buffer(b) }
        let simple: [LaneType] = [.driving, .sidewalk, .shoulder, .biking, .bus, .sharedLeftTurn, .construction,
                                  .lightRail, .footway, .sharedUse]
        return simple.first { $0.rustDebug == text }
    }
}

/// The broad class of traffic a lane carries.
public enum TrafficClass: Sendable {
    case pedestrian, bicycle, motor, rail
}

public enum Direction: Int, Hashable, Comparable, Sendable {
    case forward, backward

    public func opposite() -> Direction { self == .forward ? .backward : .forward }

    public static func < (a: Direction, b: Direction) -> Bool { a.rawValue < b.rawValue }

    public var rustDebug: String { self == .forward ? "Forward" : "Backward" }
}

/// A turn direction (OSM `turn`). The raw value is the bit of an `EnumSet`,
/// so a set iterates in declaration order.
public enum TurnDirection: Int, CaseIterable, Sendable {
    case through, left, right, slightLeft, slightRight, sharpLeft, sharpRight, mergeLeft, mergeRight, reverse

    public func tagValue() -> String {
        switch self {
        case .through: return "through"
        case .left: return "left"
        case .right: return "right"
        case .slightLeft: return "slight_left"
        case .slightRight: return "slight_right"
        case .sharpLeft: return "sharp_left"
        case .sharpRight: return "sharp_right"
        case .mergeLeft: return "merge_left"
        case .mergeRight: return "merge_right"
        case .reverse: return "reverse"
        }
    }

    public func turnAngle() -> Angle {
        switch self {
        case .through: return .degrees(0.0)
        case .slightRight, .mergeRight: return .degrees(45.0)
        case .slightLeft, .mergeLeft: return .degrees(-45.0)
        case .right: return .degrees(90.0)
        case .left: return .degrees(-90.0)
        case .sharpRight: return .degrees(135.0)
        case .sharpLeft: return .degrees(-135.0)
        case .reverse: return .degrees(180.0)
        }
    }
}

/// enumset's `EnumSet<TurnDirection>`: a bit set, iterated in declaration order.
public struct TurnDirections: Hashable, Sendable {
    public var bits: UInt16 = 0

    public init() {}

    public mutating func insert(_ t: TurnDirection) { bits |= 1 << UInt16(t.rawValue) }

    public func contains(_ t: TurnDirection) -> Bool { bits & (1 << UInt16(t.rawValue)) != 0 }

    public var isEmpty: Bool { bits == 0 }

    public var members: [TurnDirection] { TurnDirection.allCases.filter(contains) }
}
