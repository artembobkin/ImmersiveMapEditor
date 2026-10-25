/// muv-osm's one-way reading (`lanes/highway/oneway.rs`): `oneway=*` per
/// mode and condition, what it implies (motorways, roundabouts), and how
/// it masks a direction's access. Also `Placement` (`placement.rs`), where
/// the OSM line runs across the lanes.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

enum OnewayDirection: Equatable {
    case forward, backward, both, bothWays, alternating, reversible

    private static let names = OsmNames(
        [(OnewayDirection.forward, "Forward"), (.backward, "Backward"), (.both, "Both"), (.bothWays, "BothWays"),
         (.alternating, "Alternating"), (.reversible, "Reversible")],
        aliases: [.forward: ["yes", "true", "1"], .backward: ["reverse", "-1"], .both: ["no", "false", "0"],
                  .bothWays: []])

    static func fromOsmStr(_ s: String) -> OnewayDirection? { names.parse(s) }

    func inDirection(_ forward: Bool) -> Bool {
        switch self {
        case .forward: return forward
        case .backward: return !forward
        case .both, .bothWays, .alternating: return true
        case .reversible: return false
        }
    }

    func inDirectionEver(_ forward: Bool) -> Bool {
        switch self {
        case .forward: return forward
        case .backward: return !forward
        case .both, .bothWays, .alternating, .reversible: return true
        }
    }

    func flip() -> OnewayDirection {
        switch self {
        case .forward: return .backward
        case .backward: return .forward
        default: return self
        }
    }
}

typealias Oneway = TModes<Conditional<OnewayDirection>>

/// `forward_on`: whether forward traffic is on `side`.
func forwardOn(_ oneway: OnewayDirection?, _ drivingSide: Side, _ side: Side) -> Bool {
    oneway == .backward ? drivingSide != side : drivingSide == side
}

private func impliesOneway<T: Taglike>(_ cls: HighwayClassification?, _ tags: T) -> Bool {
    cls == .motorway(false) || ["circular", "roundabout"].contains(tags.getValue("junction") ?? "")
}

/// `parse_oneway`: per mode (the vehicle's from `oneway` itself), and the
/// vehicle's unconditional direction.
func parseOneway<T: Taglike>(_ cls: HighwayClassification?, _ tags: T, _ onewayTags: T?,
                             _ onewayDefault: OnewayDirection) -> (Oneway, OnewayDirection?) {
    let onewayVehicle: Conditional<OnewayDirection>
    let vehicleDefault: OnewayDirection?
    if let ot = onewayTags, let v = Conditional<OnewayDirection>.fromOsm(ot, OnewayDirection.fromOsmStr) {
        onewayVehicle = v
        vehicleDefault = v.first.flatMap { $0.conditions.isEmpty ? $0.value : nil }
    } else {
        let d = impliesOneway(cls, tags) ? OnewayDirection.forward : onewayDefault
        onewayVehicle = Conditional(d)
        vehicleDefault = d
    }
    var oneway = Oneway([(.vehicle, onewayVehicle)])
    if let ot = onewayTags {
        for (mode, t) in TMode.iterTags(ot) {
            if let c = Conditional<OnewayDirection>.fromOsm(t, OnewayDirection.fromOsmStr) { oneway.set(mode, c) }
        }
    }
    return (oneway, vehicleDefault)
}

private func applyOnewayMask(_ access: Conditional<AccessLevel>, _ oneway: Conditional<OnewayDirection>,
                             _ forward: Bool) -> Conditional<AccessLevel> {
    access.merge(oneway) { a, o in o.inDirection(forward) ? a : .no }
}

/// `add_oneway_direction`: one direction's access masked by the one-way rules.
func addOnewayDirection(_ oneway: Oneway, _ lanes: inout ParseDirectionLanes, _ forward: Bool) {
    // `oneway=no` alone changes nothing.
    if oneway.count == 1, let vehicle = oneway.getRaw(.vehicle), vehicle.count == 1,
       vehicle.restrictions[0].conditions.isEmpty, vehicle.restrictions[0].value == .both {
        return
    }
    lanes.mutEach { lane in
        var t = lane.travelLane
        func mask(_ d: inout TravelLaneDirection) {
            d.access = d.access.zip(oneway) { access, o in
                if let o { return access.map { applyOnewayMask($0, o, forward) } }
                return access
            }
        }
        if forward { mask(&t.forward) } else { mask(&t.backward) }
        lane.travelLane = t
    }
}

/// `ever_allowed_oneway`: whether any one-way rule ever lets traffic go forward, and backward.
func everAllowedOneway(_ oneway: Oneway) -> (Bool, Bool) {
    var forward = false, backward = false
    for (_, c) in oneway.entries {
        for r in c.restrictions {
            forward = forward || r.value.inDirection(true)
            backward = backward || r.value.inDirection(false)
        }
    }
    return (forward, backward)
}

/// `Placement`.
enum Placement {
    case transition
    case middleOf(UInt8), rightOf(UInt8), leftOf(UInt8)

    static func fromOsmStr(_ s: String) -> Placement? {
        if s == "transition" { return .transition }
        guard let (relative, laneStr) = s.rustSplitOnce(":"), let lane = rustParseU8(laneStr), lane != 0 else { return nil }
        switch relative {
        case "middle_of": return .middleOf(lane)
        case "right_of": return .rightOf(lane)
        case "left_of": return .leftOf(lane)
        default: return nil
        }
    }

    /// `to_center_index`: lanes count from 1 here (wrapping, as Rust's release builds do).
    var centerIndex: UInt8? {
        switch self {
        case .transition: return nil
        case .middleOf(let l): return l &* 2 &- 1
        case .rightOf(let l): return l &* 2
        case .leftOf(let l): return l &* 2 &- 2
        }
    }
}
