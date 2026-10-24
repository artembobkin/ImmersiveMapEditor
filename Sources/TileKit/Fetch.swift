import Foundation
import Geometry

/// Downloads the source data of one map tile into data/<z>_<x>_<y>/:
///
///   osm.json   every OSM element in the tile plus a margin, from Overpass,
///              with the full geometry of the multipolygons that reach in
///   tile.json  the tile's bounds, its Mercator centre and scale, and where
///              and when everything was fetched
///
/// An osm.json on disk is kept unless asked to fetch again, so the sources
/// stay fixed while the style is worked out.
public enum Fetch {
    static let overpass = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
    static let userAgent = "TilePipeline/0.1 (experimental 3D map tiles; github.com/artembobkin/ImmersiveMapEditor)"

    public static func folder(z: Int, x: Int, y: Int) -> URL {
        pipelineRoot.appendingPathComponent("data/\(z)_\(x)_\(y)")
    }

    static func longitudeOfColumn(_ c: Double, _ z: Int) -> Double { c / pow(2, Double(z)) * 360 - 180 }

    /// The tile's edges, its Mercator centre, the tile units a metre takes
    /// there (as the engine's baker computes them) and the box fetched around it.
    static func describe(z: Int, x: Int, y: Int, margin: Double) -> [String: Any] {
        let south = latitudeOfRow(Double(y + 1), z), north = latitudeOfRow(Double(y), z)
        let west = longitudeOfColumn(Double(x), z), east = longitudeOfColumn(Double(x + 1), z)
        let lat = latitudeOfRow(Double(y) + 0.5, z), lon = longitudeOfColumn(Double(x) + 0.5, z)
        let upm = pow(2, Double(z)) * tileExtent / (earthCircumference * cos(lat * .pi / 180))
        // The margin in degrees at the centre's scale.
        let dlat = margin / 111320, dlon = margin / (111320 * cos(lat * .pi / 180))
        return [
            "tile": ["z": z, "x": x, "y": y],
            "bounds": ["south": south, "west": west, "north": north, "east": east],
            "centre": ["latitude": lat, "longitude": lon],
            "units_per_metre": upm,
            "size_m": tileExtent / upm,
            "margin_m": margin,
            "fetch_bounds": ["south": south - dlat, "west": west - dlon, "north": north + dlat, "east": east + dlon],
        ]
    }

    /// Every node and way in the box, and the multipolygon and building
    /// relations with a member in it. Recursing down brings the whole of
    /// each relation, members outside the box included, so an outline is
    /// never open. Routes, boundaries and other large relations are left
    /// out: they would pull in half the city.
    static func query(_ b: [String: Double]) -> String {
        let box = String(format: "%.7f,%.7f,%.7f,%.7f", b["south"]!, b["west"]!, b["north"]!, b["east"]!)
        return "[out:json][timeout:300][maxsize:536870912];\n"
            + "(node(\(box)); way(\(box)); rel(\(box))[type~\"^(multipolygon|building)$\"];)->.a;\n"
            + "(.a; .a >;);\nout meta;\n"
    }

    static func download(_ query: String) throws -> (String, Data) {
        var last = "no server answered"
        for server in overpass {
            print("[osm] \(server)")
            var request = URLRequest(url: URL(string: server)!, timeoutInterval: 400)
            request.httpMethod = "POST"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            request.httpBody = Data(("data=" + query.addingPercentEncoding(withAllowedCharacters: allowed)!).utf8)
            let done = DispatchSemaphore(value: 0)
            var result: (Data?, URLResponse?, Error?)
            URLSession.shared.dataTask(with: request) { result = ($0, $1, $2); done.signal() }.resume()
            done.wait()
            if let data = result.0, (result.1 as? HTTPURLResponse)?.statusCode == 200,
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return (server, data)
            }
            last = result.2?.localizedDescription ?? "HTTP \((result.1 as? HTTPURLResponse)?.statusCode ?? 0)"
            print("[osm] failed: \(last)")
        }
        throw PipelineError("Overpass failed: \(last)")
    }

    static func summary(_ elements: [[String: Any]]) -> [String: Any] {
        var kinds: [String: Int] = [:]
        for e in elements { kinds[e["type"] as? String ?? "?", default: 0] += 1 }
        let tagged = elements.compactMap { $0["tags"] as? [String: String] }
        func count(_ f: ([String: String]) -> Bool) -> Int { tagged.filter(f).count }
        return [
            "elements": kinds,
            "buildings": count { $0["building"] != nil },
            "building_parts": count { $0["building:part"] != nil },
            "with_height": count { $0["height"] != nil && ($0["building"] != nil || $0["building:part"] != nil) },
            "with_levels": count { $0["building:levels"] != nil },
            "with_roof_shape": count { $0["roof:shape"] != nil },
            "highways": count { $0["highway"] != nil },
            "trees": count { $0["natural"] == "tree" },
            "water": count { $0["natural"] == "water" || $0["waterway"] != nil },
        ]
    }

    /// Fetches one tile's OSM unless it is on disk (or `force`), and writes
    /// its tile.json.
    public static func tile(z: Int, x: Int, y: Int, margin: Double = 100, force: Bool = false) throws {
        let folder = folder(z: z, x: x, y: y)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var info = describe(z: z, x: x, y: y, margin: margin)
        print(String(format: "[tile] %d/%d/%d: %.1f m across", z, x, y, info["size_m"] as! Double))
        let osmURL = folder.appendingPathComponent("osm.json"), infoURL = folder.appendingPathComponent("tile.json")
        let q = query(info["fetch_bounds"] as! [String: Double])
        var source: String?
        let data: Data
        if FileManager.default.fileExists(atPath: osmURL.path) && !force {
            print("[osm] on disk, kept")
            data = try Data(contentsOf: osmURL)
        } else {
            (source, data) = try download(q)
            try data.write(to: osmURL)
        }
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let previous = (try? JSONSerialization.jsonObject(with: Data(contentsOf: infoURL)) as? [String: Any])??["osm"]
            as? [String: Any] ?? [:]
        let now = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "Z", with: "+00:00")
        let summary = summary(parsed["elements"] as? [[String: Any]] ?? [])
        info["osm"] = [
            "source": source ?? previous["source"] ?? NSNull(),
            "fetched": source != nil ? now : (previous["fetched"] ?? NSNull()),
            "timestamp": (parsed["osm3s"] as? [String: Any])?["timestamp_osm_base"] ?? NSNull(),
            "query": q,
            "summary": summary,
            "attribution": "© OpenStreetMap contributors, ODbL",
        ]
        try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: infoURL)
        print("[osm] \(summary["elements"] ?? [:])")
    }
}
