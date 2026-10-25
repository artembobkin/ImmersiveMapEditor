/// osm2lanes's `LaneSpec` (one lane: its type, direction, width and turns)
/// with the typical widths, and the map configuration.

import struct MuvLanes.Lane
import StreetGeom

public let normalLaneThickness = Distance(constMeters: 3.0)
let serviceRoadLaneThickness = Distance(constMeters: 2.0)
public let sidewalkThickness = Distance(constMeters: 1.5)
let shoulderThickness = Distance(constMeters: 0.5)

/// One lane of a road. `lane` is the Muv lane osm2lanes keeps beside its
/// own fields (none for a kerb it adds): the lane polygons write it as serde
/// does, and lanes compare with its `PartialEq`, as in the Rust.
public struct LaneSpec: Equatable, Sendable {
    public var lt: LaneType
    public var dir: Direction
    public var width: Distance
    /// No restriction indicated when empty.
    public var allowedTurns: TurnDirections
    public var lane: MuvLanes.Lane?

    public init(lt: LaneType, dir: Direction, width: Distance, allowedTurns: TurnDirections = TurnDirections(),
                lane: MuvLanes.Lane? = nil) {
        self.lt = lt
        self.dir = dir
        self.width = width
        self.allowedTurns = allowedTurns
        self.lane = lane
    }

    /// Likely widths for a lane type, the first the default.
    public static func typicalLaneWidths(_ lt: LaneType, _ highwayType: String) -> [(Distance, String)] {
        switch lt {
        case .driving:
            var choices = [(normalLaneThickness, "typical"), (serviceRoadLaneThickness, "alley"),
                           (Distance.feet(8.0), "narrow"), (Distance.feet(12.0), "highway")]
            if highwayType == "service" { choices.swapAt(1, 0) }
            return choices
        case .biking: return [(.meters(1.5), "absolute minimum"), (.meters(2.0), "standard")]
        case .bus: return [(.feet(10.0), "minimum"), (.feet(12.0), "normal")]
        case .parking:
            var choices = [(normalLaneThickness, "full lane"), (serviceRoadLaneThickness, "alley"),
                           (Distance.feet(7.0), "narrow"), (Distance.feet(15.0), "loading zone")]
            if highwayType == "service" { choices.swapAt(1, 0) }
            return choices
        case .sharedLeftTurn, .construction, .lightRail: return [(normalLaneThickness, "default")]
        case .sidewalk: return [(sidewalkThickness, "default"), (.feet(6.0), "wide")]
        case .shoulder: return [(shoulderThickness, "default")]
        case .buffer(.stripes): return [(.meters(1.5), "default")]
        case .buffer(.flexPosts): return [(.meters(0.5), "default")]
        case .buffer(.planters): return [(.meters(2.0), "default")]
        case .buffer(.jerseyBarrier): return [(.meters(1.5), "default")]
        case .buffer(.curb): return [(.meters(0.1), "default")]
        case .buffer(.verge): return [(.meters(2.0), "default")]
        case .footway: return [(.meters(2.0), "default")]
        case .sharedUse: return [(.meters(3.0), "default")]
        }
    }

    public static func typicalLaneWidth(_ lt: LaneType) -> Distance { typicalLaneWidths(lt, "road")[0].0 }

    /// Nil if bidirectional or not driveable, else the one direction of driving.
    public static func onewayForDriving(_ lanes: [LaneSpec]) -> Direction? {
        var fwd = false
        var back = false
        for x in lanes where x.lt == .driving {
            if x.dir == .forward { fwd = true } else { back = true }
        }
        if fwd && back { return nil }
        if fwd { return .forward }
        if back { return .backward }
        return nil
    }
}

public enum DrivingSide: Hashable, Sendable {
    case right, left
    public var rustDebug: String { self == .right ? "Right" : "Left" }
}

/// osm2lanes's `MapConfig`, with its defaults.
public struct MapConfig: Sendable {
    /// Calculated by streets_reader. The value passed in is ignored.
    public var drivingSide: DrivingSide = .right
    public var overrideDrivingSide: DrivingSide?
    /// Calculated by streets_reader. The value passed in is ignored.
    public var countryCode: String = ""
    public var bikesCanUseBusLanes = true
    public var inferredSidewalks = false
    public var parallelStreetParkingSpotLength = Distance.meters(8.0)
    public var vehicleWidthForParkingSpots = Distance.meters(3.0)
    public var turnOnRed = true
    public var includeRailroads = true
    public var inferredKerbs = true

    public init() {}
}
