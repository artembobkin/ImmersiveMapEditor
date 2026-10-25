/// muv-osm's `highway_lanes` (`lanes/highway/highway.rs`): the lanes of a
/// highway from left to right. The side lanes of the left (sidewalk,
/// cycle track, kerb-side parking, then parking, bus bay, shoulder, cycle
/// lane, bus lane), the core lanes, then the right side in mirror order,
/// with the kerbs found on the way and the carriageway's width shared out.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `highway_lanes`: nil when the tags are not a highway.
func highwayLanes(_ tags: Tag, _ regions: [String]) -> Lanes? {
    let drivingSide = tags.getValue("driving_side").flatMap(Side.fromOsmStr)
        ?? regions.lazy.compactMap(muvDrivingSide).first ?? .right

    guard let (lifecycle, cls, _) = Lifecycle.fromOsm(tags, "highway", HighwayClassification.fromOsmStr) else { return nil }

    let platform = cls == .platform || tags.getValue("public_transport") == "platform"

    let defaultOneway: OnewayDirection
    switch cls {
    case .cycleway, .footway, .pedestrian, .steps, .path: defaultOneway = .bothWays
    default: defaultOneway = .both
    }
    let (oneway, onewayVehicle) = parseOneway(cls, tags, tags.get("oneway"), defaultOneway)

    var lanes = Lanes(empty: lifecycle)

    var hasSidewalk = false
    var sidewalkLeft: SideLane?, sidewalkRight: SideLane?
    if cls != .footway, let sidewalk = tags.get("sidewalk") {
        (hasSidewalk, sidewalkLeft, sidewalkRight) = parseSidewalkLanes(sidewalk, regions, drivingSide, onewayVehicle)
    }
    hasSidewalk = hasSidewalk || sidewalkLeft != nil || sidewalkRight != nil

    var cyclewayLeft: SideLane?, cyclewayRight: SideLane?
    if cls != .cycleway, let cycleway = tags.get("cycleway") {
        (cyclewayLeft, cyclewayRight) = parseCyclewayLanes(cycleway, tags.sub("bicycle", "lanes"), regions,
                                                           drivingSide, onewayVehicle)
    }

    if let s = sidewalkLeft, let c = cyclewayLeft {
        if c.segregated != nil { sidewalkLeft = nil } else if s.segregated != nil { cyclewayLeft = nil }
    }
    if let s = sidewalkRight, let c = cyclewayRight {
        if c.segregated != nil { sidewalkRight = nil } else if s.segregated != nil { cyclewayRight = nil }
    }

    let segregated = sidewalkLeft == nil && sidewalkRight == nil
        ? tags.getValue("segregated").flatMap(boolFromOsmStr) : nil

    var parkingLeft: (Lane, ParkingPosition)?, parkingRight: (Lane, ParkingPosition)?
    if let parking = tags.get("parking") {
        parkingLeft = parseParkingLane(parking, "left")
        parkingRight = parseParkingLane(parking, "right")
    }
    var busBayLeft: SideLane?, busBayRight: SideLane?
    if let busBay = tags.get("bus_bay") {
        (busBayLeft, busBayRight) = parseBusBayLanes(busBay, regions, drivingSide, onewayVehicle)
    }
    var shoulderLeft: SideLane?, shoulderRight: SideLane?
    if let shoulder = tags.get("shoulder") {
        (shoulderLeft, shoulderRight) = parseShoulderLanes(shoulder, regions, drivingSide, onewayVehicle)
    }

    var buswayLeft: SideLane?, buswayRight: SideLane?
    if let busway = tags.get("busway") {
        (buswayLeft, buswayRight) = parseBuswayLanes(busway, regions, drivingSide, onewayVehicle)
    }
    var (buswayForward, buswayBackward) = drivingSide == .left
        ? (buswayLeft != nil, buswayRight != nil) : (buswayRight != nil, buswayLeft != nil)

    if buswayForward || buswayBackward {
        let busLanes = tags.sub("bus", "lanes")
        let psvLanes = tags.sub("psv", "lanes")
        if busLanes?.value != nil || psvLanes?.value != nil {
            buswayLeft = nil
            buswayRight = nil
        } else if buswayForward && (busLanes?.getValue("forward") != nil || psvLanes?.getValue("forward") != nil) {
            if drivingSide == .left { buswayLeft = nil } else { buswayRight = nil }
            buswayForward = false
        } else if buswayBackward && (busLanes?.getValue("backward") != nil || psvLanes?.getValue("backward") != nil) {
            if drivingSide == .left { buswayRight = nil } else { buswayLeft = nil }
            buswayBackward = false
        }
    }

    sidewalkLeft?.add(&lanes, .left)

    if let left = cyclewayLeft, left.kerb {
        left.add(&lanes, .left)
        cyclewayLeft = nil
    }

    var kerbLeft = lanes.doubleLen
    if let (left, position) = parkingLeft, position.kerb {
        parkingLeft = nil
        lanes.addLaneLeft(left)
        kerbLeft = kerbLeft &+ (2 - (position == .halfOnKerb ? 1 : 0))
    }

    let carriagewayStart = lanes.lanes.count

    if let (left, _) = parkingLeft { lanes.addLaneLeft(left) }
    busBayLeft?.add(&lanes, .left)
    shoulderLeft?.add(&lanes, .left)
    cyclewayLeft?.add(&lanes, .left)
    buswayLeft?.add(&lanes, .left)

    let base = BaseLanes(regions: regions, drivingSide: drivingSide, tags: tags, isSidepath: false, returnCenter: true,
                         segregated: segregated, cls: cls, oneway: oneway, onewayVehicle: onewayVehicle,
                         platform: platform, hasSidewalk: hasSidewalk, buswayForward: buswayForward ? 1 : 0,
                         buswayBackward: buswayBackward ? 1 : 0)
    let (centreLine, centre) = base.add(&lanes.lanes)
    lanes.centre &+= centre
    lanes.centreLine &+= centreLine

    buswayRight?.add(&lanes, .right)
    if let right = cyclewayRight, !right.kerb {
        right.add(&lanes, .right)
        cyclewayRight = nil
    }
    shoulderRight?.add(&lanes, .right)
    busBayRight?.add(&lanes, .right)
    if let (right, position) = parkingRight, !position.kerb {
        parkingRight = nil
        lanes.addLaneRight(right)
    }

    var kerbRight = lanes.doubleLen
    if let width = carriagewayWidth(tags) {
        distributeFullWidth(&lanes.lanes, from: carriagewayStart, width)
    }

    if let (right, position) = parkingRight {
        kerbRight = kerbRight &+ (position == .halfOnKerb ? 1 : 0)
        lanes.addLaneRight(right)
    }
    cyclewayRight?.add(&lanes, .right)
    sidewalkRight?.add(&lanes, .right)

    lanes.kerbLeft = kerbLeft != 0 ? kerbLeft : nil
    lanes.kerbRight = kerbRight != lanes.doubleLen ? kerbRight : nil
    return lanes
}

/// `carriageway_width`: `carriageway` (when there is a `width` node, Muv reads
/// the root key, not `width:carriageway`), else `width`, else `est_width`.
private func carriagewayWidth(_ tags: Tag) -> Quantity<Distance>? {
    if let width = tags.get("width") {
        if let w = tags.getValue("carriageway").flatMap({ Quantity<Distance>.fromOsmStr($0) }) { return w }
        if let w = width.value.flatMap({ Quantity<Distance>.fromOsmStr($0) }) { return w }
    }
    return tags.getValue("est_width").flatMap { Quantity<Distance>.fromOsmStr($0) }
}
