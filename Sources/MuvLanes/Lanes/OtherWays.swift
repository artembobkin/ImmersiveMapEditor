/// muv-osm's lanes of what is not a highway (`lanes/railway/railway.rs`,
/// `lanes/waterway.rs`, `lanes/aeroway.rs`): one lane for a railway track,
/// a river with access keys, a runway or taxiway. And `lanes`, the entry
/// point that tries a highway, then those.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `lanes(tags, regions)`: a highway, a railway, a waterway or an aeroway,
/// nil if none. `regions` are ISO 3166 codes, the most important first.
public func lanes(_ tags: Tag, _ regions: [String]) -> Lanes? {
    highwayLanes(tags, regions) ?? railwayLanes(tags) ?? waterwayLanes(tags) ?? aerowayLanes(tags)
}

private enum RailwayClassification: Int, CaseIterable {
    case abandoned, construction, disused, funicular, lightRail, miniature, monorail, narrowGauge, rail, subway, tram

    static let names = OsmNames(
        zip(allCases, ["Abandoned", "Construction", "Disused", "Funicular", "LightRail", "Miniature", "Monorail",
                       "NarrowGauge", "Rail", "Subway", "Tram"]).map { ($0, $1) })

    var transportationMode: TMode? {
        switch self {
        case .rail: return .train
        case .monorail: return .monorail
        case .funicular: return .funicular
        case .lightRail: return .lightRail
        case .subway: return .subway
        case .tram: return .tram
        default: return nil
        }
    }
}

/// `railway_lanes`.
func railwayLanes(_ tags: Tag) -> Lanes? {
    guard let (lifecycle, cls, railway) = Lifecycle.fromOsm(tags, "railway", RailwayClassification.names.parse),
          let mode = cls?.transportationMode else { return nil }

    var access = TModes<Conditional<AccessLevel>>.all(Conditional(AccessLevel.no))
    access.set(mode, Conditional(AccessLevel.yes))
    var travelLane = TravelLaneDirection.withAccess(access)

    if let maxspeed = tags.getValue("maxspeed").flatMap({ Quantity<WalkSpeed>.fromOsmStr($0) }) {
        travelLane.maxspeed.set(.all, Conditional(maxspeed))
    }
    if let gauge = tags.get("loading_gauge") {
        if let h = gauge.getValue("maxheight").flatMap({ Quantity.fromOsmStrWithUnit($0, Distance.millimetre) }) {
            travelLane.maxheight.set(.all, Conditional(h))
        }
        if let w = gauge.getValue("maxwidth").flatMap({ Quantity.fromOsmStrWithUnit($0, Distance.millimetre) }) {
            travelLane.maxwidth.set(.all, Conditional(w))
        }
    }

    var travel = TravelLane.both(travelLane)
    switch railway.getValue("preferred_direction") {
    case "forward": travel.forward.access.set(mode, Conditional(AccessLevel.designated))
    case "backward": travel.backward.access.set(mode, Conditional(AccessLevel.designated))
    default: break
    }
    switch railway.getValue("bidirectional") {
    case "signals": travel.backward.access.set(mode, Conditional(AccessLevel.permit))
    case "possible": travel.backward.access.set(mode, Conditional(AccessLevel.no))
    default: break
    }

    var lane = Lane(travel)
    if let gauge = tags.getValue("gauge") {
        var widths: [Quantity<Distance>] = []
        var all = true
        for s in gauge.rustSplit(";") {
            guard let w = Quantity.fromOsmStrWithUnit(s, Distance.millimetre) else {
                all = false
                break
            }
            widths.append(w)
        }
        if all { lane.trackWidths = widths }
    }
    lane.electrifications = Electrification.fromOsm(tags) ?? []
    return Lanes(single: lane, lifecycle)
}

/// `waterway_lanes`: only a river whose access is tagged.
func waterwayLanes(_ tags: Tag) -> Lanes? {
    guard let (lifecycle, _, _) = Lifecycle.fromOsm(tags, "waterway", { $0 == "river" || asciiLowercased($0) == "river" ? () : nil })
    else { return nil }
    var access = TModes<Conditional<AccessLevel>>()
    for (mode, tag) in TMode.iterTags(tags) {
        if let c = Conditional<AccessLevel>.fromOsm(tag, AccessLevel.fromOsmStr) { access.set(mode, c) }
    }
    if access.isEmpty { return nil }
    access.set(.all, Conditional(AccessLevel.no))
    let lane = Lane(TravelLane.both(.withAccess(access))).addParse(tags)
    return Lanes(single: lane, lifecycle)
}

/// `aeroway_lanes`.
func aerowayLanes(_ tags: Tag) -> Lanes? {
    let names = OsmNames([(AccessLevel.yes, "Runway"), (.yes, "Taxiway"), (.escape, "Stopway")])
    guard let (lifecycle, level, _) = Lifecycle.fromOsm(tags, "aeroway", names.parse) else { return nil }
    guard let level else { return nil }
    let access = TModes([(.all, Conditional(AccessLevel.no)), (.aeroplane, Conditional(level))])
    let lane = Lane(TravelLane.both(.withAccess(access))).addParse(tags)
    return Lanes(single: lane, lifecycle)
}
