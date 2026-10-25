/// osm2streets's plain GeoJSON (a polygon per road and intersection) and
/// the lane polygons, written as serde_json pretty prints them.

import enum MuvLanes.MuvJSON
import StreetGeom

/// Which roads and intersections to render.
public enum Filter {
    case all
    case filtered(Set<RoadID>, Set<IntersectionID>)

    func roads(_ streets: StreetNetwork) -> [Road] {
        switch self {
        case .all: return streets.roads.values
        case .filtered(let rs, _): return rs.sorted().map { streets.roads[$0]! }
        }
    }

    func intersections(_ streets: StreetNetwork) -> [Intersection] {
        switch self {
        case .all: return streets.intersections.values
        case .filtered(_, let is_): return is_.sorted().map { streets.intersections[$0]! }
        }
    }
}

extension StreetNetwork {
    /// A polygon per road and intersection.
    public func toGeoJSON(_ filter: Filter) -> String {
        var features: [GeoJSONFeature] = []
        for road in filter.roads(self) {
            var f = GeoJSONFeature(road.centerLine.makePolygons(road.totalWidth()).toGeoJSON(gpsBounds))
            f.setProperty("id", .uint(UInt64(road.id.id)))
            f.setProperty("type", .string("road"))
            f.setProperty("osm_way_ids", .array(road.osmIDs.map { .int($0.id) }))
            f.setProperty("src_i", .uint(UInt64(road.srcI.id)))
            f.setProperty("dst_i", .uint(UInt64(road.dstI.id)))
            f.setProperty("layer", .int(Int64(road.layer)))
            features.append(f)
        }
        for intersection in filter.intersections(self) {
            var f = GeoJSONFeature(intersection.polygon.toGeoJSON(gpsBounds))
            f.setProperty("id", .uint(UInt64(intersection.id.id)))
            f.setProperty("type", .string("intersection"))
            f.setProperty("osm_node_ids", .array(intersection.osmIDs.map { .int($0.id) }))
            f.setProperty("intersection_kind", .string(intersection.kind.rustDebug))
            f.setProperty("control", .string(intersection.control.rustDebug))
            f.setProperty("crossing", crossingJSON(intersection.crossing))
            f.setProperty("movements", .array(intersection.movements.map { .string("\($0.0) -> \($0.1)") }))
            features.append(f)
        }
        return featureCollectionString(features, foreignMembers: ["country_code": .string(config.countryCode)])
    }

    /// A polygon per lane, with its type, width, direction and turns.
    public func toLanePolygonsGeoJSON(_ filter: Filter) -> String {
        var features: [GeoJSONFeature] = []
        for road in filter.roads(self) {
            let centers = road.getLaneCenterLines()
            for (idx, (lane, pl)) in zip(road.laneSpecsLTR, centers).enumerated() {
                var f = GeoJSONFeature(pl.makePolygons(lane.width).toGeoJSON(gpsBounds))
                f.setProperty("type", .string(lane.lt.rustDebug))
                f.setProperty("road", .uint(UInt64(road.id.id)))
                f.setProperty("layer", .int(Int64(road.layer)))
                f.setProperty("speed_limit", .string(road.speedLimit.map { "Some(\($0.rustDebug))" } ?? "None"))
                f.setProperty("index", .uint(UInt64(idx)))
                f.setProperty("width", .double(lane.width.innerMeters))
                f.setProperty("direction", .string(lane.dir.rustDebug))
                f.setProperty("allowed_turns", .array(lane.allowedTurns.members.map { .string($0.tagValue()) }))
                f.setProperty("osm_way_ids", .array(road.osmIDs.map { .int($0.id) }))
                if let muv = lane.lane { f.setProperty("muv", JSONValue(muv.muvJSON())) }
                features.append(f)
            }
        }
        return featureCollectionString(features)
    }
}

/// serde's `Option<Crossing>`: null, or the struct's fields in order.
func crossingJSON(_ crossing: Crossing?) -> JSONValue {
    guard let c = crossing else { return .null }
    return .object(["kind": .string(c.kind.rustName), "has_island": .bool(c.hasIsland)])
}

extension JSONValue {
    /// What `serde_json::to_value` makes of a Muv value.
    init(_ muv: MuvJSON) {
        switch muv {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .uint(let u): self = .uint(u)
        case .string(let s): self = .string(s)
        case .array(let a): self = .array(a.map(JSONValue.init))
        case .object(let o): self = .object(o.mapValues(JSONValue.init))
        }
    }
}
