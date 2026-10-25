/// muv-osm's travel lanes (`lanes/travel.rs`): a lane used for moving, its
/// forward and backward direction each with access, turns, lane changes,
/// overtaking, priority, speeds and the size limits per mode. `Turn`, the
/// arrows on the pavement (a bit set serde writes as the names of its flags).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `Turn`, a `simple_bitflags!` over `u16`.
public struct Turn: Equatable, Hashable, Sendable, MuvSerialize {
    public var bits: UInt16

    public static let sharpLeft = Turn(bits: 1 << 0)
    public static let left = Turn(bits: 1 << 1)
    public static let slightLeft = Turn(bits: 1 << 2)
    public static let mergeToLeft = Turn(bits: 1 << 3)
    public static let through = Turn(bits: 1 << 4)
    public static let mergeToRight = Turn(bits: 1 << 5)
    public static let slightRight = Turn(bits: 1 << 6)
    public static let right = Turn(bits: 1 << 7)
    public static let sharpRight = Turn(bits: 1 << 8)
    public static let reverse = Turn(bits: 1 << 9)

    /// The flags in order, with their Rust names and OSM names. Muv names
    /// `SlightLeft` `sharp_left` in OSM, so `slight_left` is never read.
    private static let flags: [(Turn, String, String)] = [
        (.sharpLeft, "SharpLeft", "sharp_left"), (.left, "Left", "left"), (.slightLeft, "SlightLeft", "sharp_left"),
        (.mergeToLeft, "MergeToLeft", "merge_to_left"), (.through, "Through", "through"),
        (.mergeToRight, "MergeToRight", "merge_to_right"), (.slightRight, "SlightRight", "slight_right"),
        (.right, "Right", "right"), (.sharpRight, "SharpRight", "sharp_right"), (.reverse, "Reverse", "reverse"),
    ]

    public func contains(_ other: Turn) -> Bool { bits & other.bits == other.bits }

    /// `Turn::normal(side)`.
    static func normal(_ side: Side) -> Turn { side == .left ? .left : .right }

    /// `from_osm_str_single`: the first flag of that OSM name.
    static func fromOsmStrSingle(_ s: String) -> Turn? { flags.first { $0.2 == s }?.0 }

    /// `FromOsmStr`: the flags of the values between semicolons, nil if none.
    static func fromOsmStr(_ s: String) -> Turn? {
        var res: Turn?
        for part in s.rustSplit(";") {
            guard let t = fromOsmStrSingle(part) else { continue }
            res = Turn(bits: (res?.bits ?? 0) | t.bits)
        }
        return res
    }

    public func muvJSON() -> MuvJSON {
        .array(Self.flags.filter { contains($0.0) }.map { .string($0.1) })
    }
}

public enum PriorityRoad: Int, SimpleEnum, Sendable {
    case yes, designated, unposted, no

    public static let rustNames = ["Yes", "Designated", "Unposted", "No"]
    public static let osmNames = makeOsmNames([.unposted: ["yes_unposted"], .no: ["no", "end"]])
}

public enum Change: Int, SimpleEnum, Sendable {
    case both, right, left, no

    public static let rustNames = ["Both", "Right", "Left", "No"]
    public static let osmNames = makeOsmNames([.both: ["yes"], .right: ["not_left", "only_right"],
                                        .left: ["not_right", "only_left"]])
}

public enum Overtaking: Int, SimpleEnum, Sendable {
    case yes, caution, no

    public static let rustNames = ["Yes", "Caution", "No"]
    public static let osmNames = makeOsmNames([.yes: ["yes", "both"], .no: ["no", "no_overtaking_of_multitrack_vehicles"]])
}

/// One direction of a travel lane. serde leaves out the empty maps.
public struct TravelLaneDirection: Equatable, Sendable, MuvSerialize {
    public var access = TModes<Conditional<AccessLevel>>()
    public var turn = TModes<Conditional<Turn>>()
    public var change = TModes<Conditional<Change>>()
    /// Who may overtake (outer) whom (inner).
    public var overtaking = TModes<Conditional<TModes<Conditional<Overtaking>>>>()
    public var priorityRoad = TModes<Conditional<PriorityRoad>>()
    public var minspeed = TModes<Conditional<Quantity<WalkSpeed>>>()
    public var maxspeed = TModes<Conditional<Quantity<WalkSpeed>>>()
    public var maxweight = TModes<Conditional<Quantity<Weight>>>()
    public var maxaxleload = TModes<Conditional<Quantity<Weight>>>()
    public var maxlength = TModes<Conditional<Quantity<Distance>>>()
    public var maxwidth = TModes<Conditional<Quantity<Distance>>>()
    public var maxheight = TModes<Conditional<Quantity<Distance>>>()
    public var maxdraught = TModes<Conditional<Quantity<Distance>>>()

    /// `TravelLaneDirection::default_empty`.
    static func defaultEmpty() -> TravelLaneDirection { TravelLaneDirection() }

    /// `TravelLaneDirection::with_access`.
    static func withAccess(_ access: TModes<Conditional<AccessLevel>>) -> TravelLaneDirection {
        var d = TravelLaneDirection()
        d.access = access
        return d
    }

    public func muvJSON() -> MuvJSON {
        var map: [String: MuvJSON] = [:]
        func put<T: MuvSerialize>(_ key: String, _ m: TModes<T>) { if !m.isEmpty { map[key] = m.muvJSON() } }
        put("access", access)
        put("turn", turn)
        put("change", change)
        put("overtaking", overtaking)
        put("priority_road", priorityRoad)
        put("minspeed", minspeed)
        put("maxspeed", maxspeed)
        put("maxweight", maxweight)
        put("maxaxleload", maxaxleload)
        put("maxlength", maxlength)
        put("maxwidth", maxwidth)
        put("maxheight", maxheight)
        put("maxdraught", maxdraught)
        return .object(map)
    }
}

public struct TravelLane: Equatable, Sendable, MuvSerialize {
    public var forward: TravelLaneDirection
    public var backward: TravelLaneDirection

    /// `TravelLane::both`.
    static func both(_ lane: TravelLaneDirection) -> TravelLane { TravelLane(forward: lane, backward: lane) }

    public func muvJSON() -> MuvJSON { .object(["forward": forward.muvJSON(), "backward": backward.muvJSON()]) }
}
