/// muv-osm's `Lanes` and `Lane` (`lanes/lanes.rs`, `lanes/lane.rs`): the
/// lanes of a way from left to right, where its centre and kerbs are (as
/// `LaneIndex`, twice a lane's index at its left edge), and each lane: a
/// travel or a parking lane, with its width, surface and the like. serde
/// writes a `Lane` with its variant flattened in (`travel` or `parking`).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `MAX_DIRECTION_LANES`, `MAX_LANES`.
let maxDirectionLanes: UInt8 = 20
let maxLanes: UInt8 = 120

/// `LaneIndex`: 0 is the left edge of the left-most lane, then half a lane per step.
public typealias LaneIndex = UInt8

public enum Side: Int, SimpleEnum, Sendable {
    case left, right

    public static let rustNames = ["Left", "Right"]
    public static let osmNames = makeOsmNames()

    static prefix func ! (s: Side) -> Side { s == .left ? .right : .left }
}

public struct Lanes: Sendable {
    public var lifecycle: Lifecycle
    /// Left to right.
    public var lanes: [Lane]
    /// Where the OSM centre line is.
    public var centre: LaneIndex
    /// The painted centre line.
    public var centreLine: LaneIndex
    public var kerbLeft: LaneIndex?
    public var kerbRight: LaneIndex?

    /// `Lanes::new_empty`.
    init(empty lifecycle: Lifecycle) {
        self.lifecycle = lifecycle
        lanes = []
        centre = 0
        centreLine = 0
    }

    /// `Lanes::new_single`.
    init(single lane: Lane, _ lifecycle: Lifecycle) {
        self.lifecycle = lifecycle
        lanes = [lane]
        centre = 1
        centreLine = 1
    }

    /// `Lanes::count`.
    var count: UInt8 { UInt8(lanes.count) }

    /// `Lanes::double_len` (wrapping, as Rust's release builds do).
    var doubleLen: UInt8 { count &* 2 }

    /// `Lanes::add_lane_left`: pushed, the centre moved right by a lane.
    mutating func addLaneLeft(_ lane: Lane) {
        lanes.append(lane)
        centre &+= 2
        centreLine &+= 2
    }

    /// `Lanes::add_lane_right`.
    mutating func addLaneRight(_ lane: Lane) { lanes.append(lane) }
}

/// `LaneVariant`.
public enum LaneVariant: Equatable, Sendable {
    case travel(TravelLane)
    case parking(ParkingLane)
}

/// `ElectrificationSystem`.
public enum ElectrificationSystem: Int, SimpleEnum, Sendable {
    case unknown, overheadLine, thirdRail, fourthRail, groundLevelPowerSupply, inductive

    public static let rustNames = ["Unknown", "OverheadLine", "ThirdRail", "FourthRail", "GroundLevelPowerSupply", "Inductive"]
    public static let osmNames = makeOsmNames([.unknown: ["yes"], .overheadLine: ["contact_line"], .thirdRail: ["rail"],
                                        .fourthRail: ["4th_rail"], .groundLevelPowerSupply: ["ground-level_power_supply"]])
}

/// `Electrification`.
public struct Electrification: Equatable, Sendable, MuvSerialize {
    public var system: ElectrificationSystem
    public var voltage: Quantity<Voltage>?
    public var frequency: Quantity<Frequency>?

    /// `FromOsm for Vec<Electrification>`: one system at most.
    static func fromOsm<T: Taglike>(_ tag: T) -> [Electrification]? {
        guard let system = tag.getValue("electrified").flatMap(ElectrificationSystem.fromOsmStr) else { return nil }
        return [Electrification(system: system, voltage: tag.getValue("voltage").flatMap { Quantity.fromOsmStr($0) },
                                frequency: tag.getValue("frequency").flatMap { Quantity.fromOsmStr($0) })]
    }

    public func muvJSON() -> MuvJSON {
        .object(["system": system.muvJSON(), "voltage": voltage.muvJSON(), "frequency": frequency.muvJSON()])
    }
}

public struct Lane: Equatable, Sendable, MuvSerialize {
    public var variant: LaneVariant
    /// Any lane that is not part of the core lanes of the `highway`,
    /// `railway` and such tag: sidewalks, cycleways, separately mapped sidepaths.
    public var isSidepath = false
    public var width: Quantity<Distance>?
    public var surface: Surface?
    public var smoothness: Smoothness?
    public var electrifications: [Electrification] = []
    public var trackWidths: [Quantity<Distance>] = []

    init(_ variant: LaneVariant) { self.variant = variant }

    init(_ travel: TravelLane) { self.init(.travel(travel)) }

    init(_ parking: ParkingLane) { self.init(.parking(parking)) }

    /// `Lane::add_parse`: width, surface and smoothness from the tags, if given.
    func addParse<T: Taglike>(_ tags: T) -> Lane {
        var l = self
        l.width = tags.getValue("width").flatMap { Quantity.fromOsmStr($0) } ?? l.width
        l.surface = tags.get("surface").flatMap { Surface.fromOsm($0) } ?? l.surface
        l.smoothness = tags.getValue("smoothness").flatMap(Smoothness.fromOsmStr) ?? l.smoothness
        return l
    }

    /// `Lane::travel_wrap`: a travel lane forward, nothing backward.
    static func travelWrap(_ lane: TravelLaneDirection) -> Lane {
        Lane(TravelLane(forward: lane, backward: .defaultEmpty()))
    }

    /// `Lane::unwrap_travel`: the forward direction of a travel lane.
    var travel: TravelLaneDirection {
        get {
            guard case .travel(let t) = variant else { fatalError("unreachable") }
            return t.forward
        }
        set {
            guard case .travel(var t) = variant else { fatalError("unreachable") }
            t.forward = newValue
            variant = .travel(t)
        }
    }

    /// The travel lane, both directions.
    var travelLane: TravelLane {
        get {
            guard case .travel(let t) = variant else { fatalError("unreachable") }
            return t
        }
        set { variant = .travel(newValue) }
    }

    /// `Lane::travel_wrap_build`: the directions the lane may be used in.
    mutating func travelWrapBuild(_ forward: Bool, _ backward: Bool) {
        var lane = travelLane
        switch (forward, backward) {
        case (true, true):
            lane.backward = lane.forward
        case (true, false):
            lane.backward.access = TModes.all(Conditional(AccessLevel.no))
        case (false, true):
            swap(&lane.forward, &lane.backward)
            lane.forward.access = TModes.all(Conditional(AccessLevel.no))
        case (false, false):
            lane.backward.access = TModes.all(Conditional(AccessLevel.no))
            lane.forward = lane.backward
        }
        travelLane = lane
    }

    public func muvJSON() -> MuvJSON {
        var map: [String: MuvJSON] = [
            "is_sidepath": .bool(isSidepath),
            "width": width.muvJSON(),
            "surface": surface.muvJSON(),
            "smoothness": smoothness.muvJSON(),
            "electrifications": electrifications.muvJSON(),
            "track_widths": trackWidths.muvJSON(),
        ]
        switch variant {
        case .travel(let t): map["travel"] = t.muvJSON()
        case .parking(let p): map["parking"] = p.muvJSON()
        }
        return .object(map)
    }
}
