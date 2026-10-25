/// Where a road's lanes come from. osm2lanes's `get_lane_specs_ltr` reads
/// them from the OSM tags through Muv's `lanes` (the `MuvLanes` target):
/// that is `MuvLaneSpecs`, the default. The reading stays a seam, a
/// `LaneSpecSource` giving the lanes for a way's tags, so that tests can
/// run on made-up lanes. Also the parts of `get_lane_specs_ltr` that are
/// osm2lanes's own (sidewalk inference, the direction of lanes on the
/// centre line).

import StreetGeom

public protocol LaneSpecSource: Sendable {
    /// osm2lanes's `get_lane_specs_ltr(tags, config)`: the lanes from left to right.
    func laneSpecsLTR(_ tags: Tags, _ config: MapConfig) -> [LaneSpec]
}

/// Fills in sidewalks for a road that doesn't tag them, as osm2lanes's
/// `infer_sidewalk_tags` does when the map infers sidewalks.
public func inferSidewalkTags(_ tags: inout Tags, _ cfg: MapConfig) {
    if tags.containsKey("sidewalk") { return }
    if tags.isAny("highway", ["footway", "path", "pedestrian", "steps", "track"]) { return }
    if tags.containsKey("sidewalk:left") || tags.containsKey("sidewalk:right") {
        let right = !tags.is("sidewalk:right", "no")
        let left = !tags.is("sidewalk:left", "no")
        let value: String
        switch (right, left) {
        case (true, true): value = "both"
        case (true, false): value = "right"
        case (false, true): value = "left"
        case (false, false): value = "none"
        }
        tags.insert("sidewalk", value)
    } else if tags.isAny("highway", ["motorway", "motorway_link"])
        || tags.isAny("junction", ["intersection", "roundabout"])
        || tags.is("foot", "no")
        || tags.is("highway", "service")
        || tags.isAny("highway", ["cycleway", "pedestrian", "track"]) {
        tags.insert("sidewalk", "none")
    } else if tags.is("oneway", "yes") {
        tags.insert("sidewalk", cfg.drivingSide == .right ? "right" : "left")
        if tags.isAny("highway", ["residential", "living_street"]) && !tags.is("dual_carriageway", "yes") {
            tags.insert("sidewalk", "both")
        }
    } else {
        tags.insert("sidewalk", "both")
    }
}

/// osm2lanes's `traffic_direction`: the direction of a lane that serves
/// both directions (a sidewalk), from its side of the centre line. Muv's
/// `LaneIndex` is twice the lane's index.
public func trafficDirection(_ position: Int, _ centreLine: Int, _ drivingSide: DrivingSide) -> Direction {
    if position + 1 == centreLine { return .forward }
    let leftOfCentreLine = position < centreLine
    let drivingLeft = drivingSide == .left
    return leftOfCentreLine == drivingLeft ? .forward : .backward
}
