/// muv-osm's `parse_direction` (`lanes/highway/direction.rs`): the lanes of
/// one direction (forward, backward or both ways) from the keys that apply
/// to it (`direction` picks `maxspeed:forward` out of `maxspeed`), first as
/// one lane for the whole direction, then per lane. Also how overtaking is
/// read, from `overtaking=*` and the German no-overtaking sign.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `parse_direction`.
func parseDirection<T: Taglike>(_ laneIn: Lane, _ laneCount: UInt8, _ tags: T, _ lanesReversed: Bool,
                                _ platform: Bool, _ direction: @escaping (T) -> T?,
                                _ maxspeedDefault: () -> TModes<Conditional<Quantity<WalkSpeed>>>?) -> ParseDirectionLanes {
    var lane = laneIn
    let trafficSign = tags.get("traffic_sign")
    let access = tags.get("access")
    let turn = tags.get("turn")
    let change = tags.get("change")
    let overtaking = tags.get("overtaking")
    let priorityRoad = tags.get("priority_road")
    let maxspeed = tags.get("maxspeed")
    let minspeed = tags.get("minspeed")
    let maxspeedType = maxspeed?.get("type")
    let sourceMaxspeed = tags.sub("source", "maxspeed")
    let zone = tags.get("zone")
    let zoneMaxspeed = zone?.get("maxspeed")
    let zoneTraffic = zone?.get("traffic")
    let maxspeedSource = maxspeed?.get("source")
    let maxweight = tags.get("maxweight")
    let maxaxleload = tags.get("maxaxleload")
    let maxlength = tags.get("maxlength")
    let maxwidth = tags.get("maxwidth")
    let maxheight = tags.get("maxheight")
    let maxdraught = tags.get("maxdraught")
    let surface = tags.get("surface")
    let smoothness = tags.get("smoothness")
    let width = tags.get("width")

    var travel = lane.travel
    var all = AllParser<T>(direction: direction)

    all.access(access, tags, platform, &travel.access)

    all.withParse(turn, &travel.turn, Turn.fromOsmStr)
    all.withParse(change, &travel.change, Change.fromOsmStr)
    all.withParse(overtaking, &travel.overtaking, parseOvertaking)
    all.withParse(trafficSign, &travel.overtaking, trafficSignOvertaking)

    all.withParse(priorityRoad, &travel.priorityRoad, PriorityRoad.fromOsmStr)

    let speed: (String) -> Quantity<WalkSpeed>? = { Quantity.fromOsmStr($0) }
    all.withParse(zoneMaxspeed, &travel.maxspeed, speed)
    all.withParse(maxspeed, &travel.maxspeed, speed)
    all.withParse(minspeed, &travel.minspeed, speed)
    all.maxspeed(maxspeedType, &travel)
    all.maxspeed(sourceMaxspeed, &travel)
    all.maxspeed(maxspeed, &travel)
    all.maxspeed(zoneTraffic, &travel)
    all.maxspeed(maxspeedSource, &travel)
    if let d = maxspeedDefault() { all.maxspeedWithData(d, &travel) }

    let weight: (String) -> Quantity<Weight>? = { Quantity.fromOsmStr($0) }
    let distance: (String) -> Quantity<Distance>? = { Quantity.fromOsmStr($0) }
    all.withParse(maxweight, &travel.maxweight, weight)
    all.withParse(maxaxleload, &travel.maxaxleload, weight)
    all.withParse(maxlength, &travel.maxlength, distance)
    all.withParse(maxwidth, &travel.maxwidth, distance)
    all.withParse(maxheight, &travel.maxheight, distance)
    // Muv reads the whole direction's maxdraught into maxheight.
    all.withParse(maxdraught, &travel.maxheight, distance)
    lane.travel = travel

    if let s = surface.flatMap({ Surface.fromOsm($0) }) {
        lane.surface = s
        all.dirty = true
    }
    if let s = smoothness?.value.flatMap(Smoothness.fromOsmStr) {
        lane.smoothness = s
        all.dirty = true
    }

    var individual = IndividualParser<T>(lanes: .all(lane, min(laneCount, maxDirectionLanes), all.dirty),
                                         lanesReversed: lanesReversed, direction: direction)

    individual.access(access, tags, platform, \Lane.travel.access)
    individual.maskOuter(tags, .psv, "psv")
    individual.maskOuter(tags, .bus, "bus")

    individual.withParse(turn, \Lane.travel.turn, Turn.fromOsmStr)
    individual.withParse(change, \Lane.travel.change, Change.fromOsmStr)
    individual.withParse(overtaking, \Lane.travel.overtaking, parseOvertaking)
    individual.withParse(trafficSign, \Lane.travel.overtaking, trafficSignOvertaking)

    individual.withParse(priorityRoad, \Lane.travel.priorityRoad, PriorityRoad.fromOsmStr)

    individual.withParse(maxspeed, \Lane.travel.maxspeed, speed)
    individual.withParse(minspeed, \Lane.travel.minspeed, speed)

    individual.withParse(maxweight, \Lane.travel.maxweight, weight)
    individual.withParse(maxaxleload, \Lane.travel.maxaxleload, weight)
    individual.withParse(maxlength, \Lane.travel.maxlength, distance)
    individual.withParse(maxwidth, \Lane.travel.maxwidth, distance)
    individual.withParse(maxheight, \Lane.travel.maxheight, distance)
    individual.withParse(maxdraught, \Lane.travel.maxdraught, distance)

    individual.direction(width, distance) { lane, v in lane.width = v }
    individual.direction(surface, SurfaceKind.fromOsmStr) { lane, v in lane.surface = Surface(kind: v) }
    individual.direction(smoothness, Smoothness.fromOsmStr) { lane, v in lane.smoothness = v }

    return individual.lanes
}

/// `parse_overtaking`: `yes` and `caution` for everyone. Anything else
/// forbids overtaking double-tracked vehicles, but allows a mode it names
/// (`only_motorcycle`).
func parseOvertaking(_ s: String) -> TModes<Conditional<Overtaking>>? {
    let v = Overtaking.fromOsmStr(s)
    if let v, v == .yes || v == .caution { return TModes.all(Conditional(v)) }
    var res = TModes([(.all, Conditional(Overtaking.yes)), (.doubleTrackedMotorVehicle, Conditional(Overtaking.no))])
    if v == nil, let mode = TMode.fromOsmStr(s.rustStripPrefix("only_") ?? s) {
        res.set(mode, Conditional(Overtaking.yes))
    }
    return res
}

/// `traffic_signs::overtaking`: the sign DE:277.1 forbids overtaking.
func trafficSignOvertaking(_ s: String) -> TModes<Conditional<Overtaking>>? {
    for part in s.rustSplit(";") where part == "DE:277.1" { return TModes([(.all, Conditional(Overtaking.no))]) }
    return nil
}
