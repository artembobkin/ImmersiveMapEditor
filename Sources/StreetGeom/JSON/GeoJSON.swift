/// GeoJSON as the geojson crate (0.24) writes it: a geometry is `type` then
/// `coordinates`, a feature `type`, `geometry`, `properties`, a collection
/// `type`, `features`, then any foreign members.

public enum GeoJSONGeometry: Sendable {
    case point([Double])
    case lineString([[Double]])
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    public var json: JSONValue {
        func pos(_ p: [Double]) -> JSONValue { .array(p.map { .double($0) }) }
        func ring(_ r: [[Double]]) -> JSONValue { .array(r.map(pos)) }
        func poly(_ p: [[[Double]]]) -> JSONValue { .array(p.map(ring)) }
        switch self {
        case .point(let p): return .orderedObject([("type", .string("Point")), ("coordinates", pos(p))])
        case .lineString(let l): return .orderedObject([("type", .string("LineString")), ("coordinates", ring(l))])
        case .polygon(let p): return .orderedObject([("type", .string("Polygon")), ("coordinates", poly(p))])
        case .multiPolygon(let m):
            return .orderedObject([("type", .string("MultiPolygon")), ("coordinates", .array(m.map(poly)))])
        }
    }
}

/// A feature with its properties (written sorted by key).
public struct GeoJSONFeature: Sendable {
    public var geometry: GeoJSONGeometry
    public var properties: [String: JSONValue] = [:]

    public init(_ geometry: GeoJSONGeometry) { self.geometry = geometry }

    public mutating func setProperty(_ key: String, _ value: JSONValue) { properties[key] = value }

    public var json: JSONValue {
        .orderedObject([("type", .string("Feature")), ("geometry", geometry.json), ("properties", .object(properties))])
    }
}

/// A feature collection, pretty printed as serde_json does.
public func featureCollectionString(_ features: [GeoJSONFeature], foreignMembers: [String: JSONValue] = [:]) -> String {
    var pairs: [(String, JSONValue)] = [("type", .string("FeatureCollection")), ("features", .array(features.map(\.json)))]
    for k in foreignMembers.keys.sorted(by: rustStringLess) { pairs.append((k, foreignMembers[k]!)) }
    return JSONValue.orderedObject(pairs).prettyString()
}
