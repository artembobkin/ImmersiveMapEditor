/// geom's `LonLat::parse_geojson_polygons`: the exterior ring of each
/// polygon (the first of a multipolygon) in a GeoJSON feature or collection,
/// with the feature's `name` if it has one.

extension LonLat {
    public static func parseGeoJSONPolygons(_ raw: String) throws -> [([LonLat], String?)] {
        let geojson = try JSONValue.parse(raw)
        let features: [JSONValue]
        switch geojson["type"]?.stringValue {
        case "Feature": features = [geojson]
        case "FeatureCollection": features = geojson["features"]?.arrayValue ?? []
        default: throw GeomError.message("Unexpected geojson")
        }
        var polygons: [([LonLat], String?)] = []
        for feature in features {
            let geometry = feature["geometry"]
            let coords = geometry?["coordinates"]?.arrayValue
            let ring: [JSONValue]
            switch geometry?["type"]?.stringValue {
            case "MultiPolygon": ring = coords?.first?.arrayValue?.first?.arrayValue ?? []
            case "Polygon": ring = coords?.first?.arrayValue ?? []
            default: throw GeomError.message("Unexpected feature")
            }
            let pts = ring.map { pt -> LonLat in
                let a = pt.arrayValue!
                return LonLat(a[0].doubleValue!, a[1].doubleValue!)
            }
            polygons.append((pts, feature["properties"]?["name"]?.stringValue))
        }
        return polygons
    }
}
