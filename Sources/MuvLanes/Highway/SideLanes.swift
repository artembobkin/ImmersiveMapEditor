/// muv-osm's side lanes (`lanes/highway/side_lanes.rs`): sidewalks,
/// cycleways, bus lanes, bus bays and shoulders tagged on a road
/// (`cycleway:right=track`), each read as a little way of its own on a
/// side, with the buffer between it and the road.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct SideLane {
    let highwayClass: HighwayClassification
    let parentOneway: OnewayDirection?
    let oneway: Bool
    let regions: [String]
    let drivingSide: Side
    let tags: DoubleTag
    let contraflow: Bool
    let segregated: Bool?
    let kerb: Bool

    /// `SideLane::add`: its lanes, on the left (the centre moved past
    /// them) or the right, the buffer on the road's side.
    func add(_ lanes: inout Lanes, _ side: Side) {
        if side == .right { addBuffer(&lanes, tags) }

        let onewayDefault: OnewayDirection
        if oneway {
            var o: OnewayDirection
            if let p = parentOneway, p == .forward || p == .backward {
                o = p
            } else {
                o = drivingSide == side ? .forward : .backward
            }
            if contraflow { o = o.flip() }
            onewayDefault = o
        } else {
            onewayDefault = .bothWays
        }

        let (onewayModes, onewayVehicle) = parseOneway(highwayClass, tags, tags.get("oneway"), onewayDefault)
        let base = BaseLanes(regions: regions, drivingSide: drivingSide, tags: tags, isSidepath: true,
                             returnCenter: false, segregated: segregated, cls: highwayClass, oneway: onewayModes,
                             onewayVehicle: onewayVehicle, platform: false, hasSidewalk: false, buswayForward: 0,
                             buswayBackward: 0)
        let (count, _) = base.add(&lanes.lanes)

        if side == .left {
            lanes.centre &+= count &* 2
            lanes.centreLine &+= count &* 2
            addBuffer(&lanes, tags)
        }
    }
}

/// `add_buffer`: a lane nobody may use, `buffer=*` wide.
private func addBuffer(_ lanes: inout Lanes, _ tags: DoubleTag) {
    guard let buffer = tags.getValue("buffer").flatMap({ Quantity<Distance>.fromOsmStr($0) }) else { return }
    var lane = Lane(TravelLane.both(.withAccess(TModes.all(Conditional(AccessLevel.no)))))
    lane.width = buffer
    lanes.addLaneLeft(lane)
}

/// Whether a side has the lane: (contraflow, kerb).
typealias SideLaneExists = (Bool, Bool)?

/// `parse_side_lanes`.
private func parseSideLanes(_ tags: Tag, _ modeLanesTags: Tag?, _ highwayClass: HighwayClassification,
                            _ parentOneway: OnewayDirection?, _ oneway: Bool, _ regions: [String], _ drivingSide: Side,
                            _ initial: (SideLaneExists, SideLaneExists),
                            _ allowedSide: (String) -> SideLaneExists) -> (SideLane?, SideLane?) {
    var (left, right) = initial
    let bothTags = tags.get("both")
    let leftTags = tags.get("left") ?? bothTags
    let rightTags = tags.get("right") ?? bothTags

    if let v = bothTags?.value {
        let both = allowedSide(v)
        left = both
        right = both
    }
    if let v = leftTags?.value { left = allowedSide(v) }
    if let v = rightTags?.value { right = allowedSide(v) }

    func dropByLanes(_ lanes: Tag) {
        if lanes.value != nil {
            left = nil
            right = nil
        } else {
            if lanes.getValue("forward") != nil {
                if drivingSide == .left { left = nil } else { right = nil }
            }
            if lanes.getValue("backward") != nil {
                if drivingSide == .left { right = nil } else { left = nil }
            }
        }
    }
    if let lanes = tags.get("lanes") { dropByLanes(lanes) }
    if let lanes = modeLanesTags { dropByLanes(lanes) }

    let both = bothTags ?? tags
    func make(_ sideTags: Tag?, _ exists: SideLaneExists) -> SideLane? {
        guard let (contraflow, kerb) = exists else { return nil }
        let t = DoubleTag.newReverse(sideTags, both)
        return SideLane(highwayClass: highwayClass, parentOneway: parentOneway, oneway: oneway, regions: regions,
                        drivingSide: drivingSide, tags: t, contraflow: contraflow,
                        segregated: t.getValue("segregated").flatMap(boolFromOsmStr), kerb: kerb)
    }
    return (make(leftTags, left), make(rightTags, right))
}

/// `parse_sidewalk_lanes`: whether the sidewalks are mapped apart, and the sides.
func parseSidewalkLanes(_ tags: Tag, _ regions: [String], _ drivingSide: Side,
                        _ parentOneway: OnewayDirection?) -> (Bool, SideLane?, SideLane?) {
    var separate = false
    let initial: (SideLaneExists, SideLaneExists)
    switch tags.value {
    case "yes", "both": initial = ((false, true), (false, true))
    case "left": initial = ((false, true), nil)
    case "right": initial = (nil, (false, true))
    case "separate":
        separate = true
        initial = (nil, nil)
    default: initial = (nil, nil)
    }
    let (l, r) = parseSideLanes(tags, nil, .footway, parentOneway, false, regions, drivingSide, initial) { s in
        switch s {
        case "yes": return (false, true)
        case "separate":
            separate = true
            return nil
        default: return nil
        }
    }
    return (separate, l, r)
}

private func position(_ parentOneway: OnewayDirection?, _ drivingSide: Side, _ kerb: Bool) -> (SideLaneExists, SideLaneExists) {
    let left = parentOneway.map { $0.inDirectionEver(drivingSide == .left) } ?? true
    let right = parentOneway.map { $0.inDirectionEver(drivingSide == .right) } ?? true
    return (left ? (false, kerb) : nil, right ? (false, kerb) : nil)
}

private func positionOpposite(_ parentOneway: OnewayDirection?, _ drivingSide: Side, _ kerb: Bool) -> (SideLaneExists, SideLaneExists) {
    forwardOn(parentOneway, drivingSide, .left) ? (nil, (true, kerb)) : ((true, kerb), nil)
}

/// `parse_cycleway_lanes`.
func parseCyclewayLanes(_ tags: Tag, _ bicycleLanesTags: Tag?, _ regions: [String], _ drivingSide: Side,
                        _ parentOneway: OnewayDirection?) -> (SideLane?, SideLane?) {
    let initial: (SideLaneExists, SideLaneExists)
    switch tags.value {
    case "lane", "share_busway": initial = position(parentOneway, drivingSide, false)
    case "track": initial = position(parentOneway, drivingSide, true)
    case "opposite_lane", "opposite_share_busway": initial = positionOpposite(parentOneway, drivingSide, false)
    case "opposite_track": initial = positionOpposite(parentOneway, drivingSide, true)
    default: initial = (nil, nil)
    }
    return parseSideLanes(tags, bicycleLanesTags, .cycleway, parentOneway, true, regions, drivingSide, initial) { s in
        switch s {
        case "lane": return (false, false)
        case "track": return (false, true)
        case "opposite_lane": return (true, false)
        case "opposite_track": return (true, true)
        default: return nil
        }
    }
}

/// `parse_busway_lanes`.
func parseBuswayLanes(_ tags: Tag, _ regions: [String], _ drivingSide: Side,
                      _ parentOneway: OnewayDirection?) -> (SideLane?, SideLane?) {
    let initial: (SideLaneExists, SideLaneExists)
    switch tags.value {
    case "lane": initial = position(parentOneway, drivingSide, false)
    case "opposite_lane": initial = positionOpposite(parentOneway, drivingSide, false)
    default: initial = (nil, nil)
    }
    return parseSideLanes(tags, nil, .busway, parentOneway, true, regions, drivingSide, initial) {
        $0 == "lane" ? (false, false) : nil
    }
}

/// `parse_bus_bay_lanes`.
func parseBusBayLanes(_ tags: Tag, _ regions: [String], _ drivingSide: Side,
                      _ parentOneway: OnewayDirection?) -> (SideLane?, SideLane?) {
    let initial: (SideLaneExists, SideLaneExists)
    switch tags.value {
    case "yes", "both": initial = ((false, false), (false, false))
    case "left": initial = ((false, false), nil)
    case "right": initial = (nil, (false, false))
    default: initial = (nil, nil)
    }
    return parseSideLanes(tags, nil, .busway, parentOneway, true, regions, drivingSide, initial) {
        $0 == "yes" || $0 == "lane" ? (false, false) : nil
    }
}

/// `parse_shoulder_lanes`.
func parseShoulderLanes(_ tags: Tag, _ regions: [String], _ drivingSide: Side,
                        _ parentOneway: OnewayDirection?) -> (SideLane?, SideLane?) {
    let initial: (SideLaneExists, SideLaneExists)
    switch tags.value {
    case "yes", "both": initial = ((false, false), (false, false))
    case "left": initial = ((false, false), nil)
    case "right": initial = (nil, (false, false))
    default: initial = (nil, nil)
    }
    return parseSideLanes(tags, nil, .shoulder, parentOneway, false, regions, drivingSide, initial) {
        $0 == "yes" ? (false, false) : nil
    }
}
