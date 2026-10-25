import Foundation
import Geometry
import TileKit

/// The buildings marked to become landmarks, each a folder of the data
/// folder's landmarks/candidates/<id>/ holding what a detailed model can be
/// made from (by hand, by a tool, by an AI): `landmark.json` (its name, tile,
/// place, and every building and part with its OSM id, all its tags, its
/// heights and its outline in longitude and latitude) and `footprint.geojson`
/// (the same outlines, the tags as properties, for any GIS tool). A
/// candidate changes nothing of the tile's build until a model of it is
/// made and placed.
enum LandmarkCandidates {
    static func folder(_ paths: WorkspacePaths) -> URL { paths.landmarks.appendingPathComponent("candidates") }

    /// The candidates there are: their ids and names, with the tile each
    /// stands in.
    static func list(_ paths: WorkspacePaths) -> [(id: String, name: String, tile: String, folder: URL)] {
        let root = folder(paths)
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted().compactMap { id in
            let f = root.appendingPathComponent(id)
            guard let data = try? Data(contentsOf: f.appendingPathComponent("landmark.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return (id, json["name"] as? String ?? id, json["tile"] as? String ?? "", f)
        }
    }

    /// The OSM elements the candidates of a tile are made of.
    static func osmIDs(_ paths: WorkspacePaths, tile: TileKey) -> [String] {
        list(paths).filter { $0.tile == tile.name }.flatMap { c -> [String] in
            guard let data = try? Data(contentsOf: c.folder.appendingPathComponent("landmark.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            return (json["buildings"] as? [[String: Any]] ?? []).compactMap { $0["osm"] as? String }
        }
    }

    /// Writes a candidate of `buildings` named `name`, in `tile` projected by
    /// `projection`. Returns its folder.
    static func make(name: String, buildings: [OsmBuilding], tile: TileKey, projection: Projecting,
                     paths: WorkspacePaths) throws -> URL {
        let id = slug(name, taken: Set(list(paths).map(\.id)))
        let out = folder(paths).appendingPathComponent(id)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func ll(_ p: Vec2) -> [Double] {
            let (lon, lat) = projection.lonLat(P2(p.x, p.y))
            return [(lon * 1e8).rounded() / 1e8, (lat * 1e8).rounded() / 1e8]
        }
        func rings(_ b: OsmBuilding) -> [[[[Double]]]] {
            b.polygons.map { $0.map { ring in (ring + [ring[0]]).map(ll) } }
        }
        let all = buildings.flatMap { $0.polygons.flatMap { $0[0] } }
        let centre = all.reduce(Vec2.zero, +) / Double(max(1, all.count))
        let landmark: [String: Any] = [
            "id": id, "name": name, "tile": tile.name, "created": ISO8601DateFormatter().string(from: Date()),
            "centre": ll(centre),
            "attribution": "© OpenStreetMap contributors, ODbL",
            "buildings": buildings.map { b in
                var e: [String: Any] = ["osm": b.id, "part": b.isPart, "tags": b.tags, "min_height_m": b.minHeight,
                                        "outline": rings(b)]
                if let h = b.height { e["height_m"] = h }
                return e
            },
        ]
        let geojson: [String: Any] = [
            "type": "FeatureCollection",
            "features": buildings.map { b in
                ["type": "Feature", "id": b.id,
                 "properties": b.tags.merging(["osm": b.id, "part": b.isPart ? "yes" : "no"]) { a, _ in a },
                 "geometry": ["type": "MultiPolygon", "coordinates": rings(b)]] as [String: Any]
            },
        ]
        for (value, file) in [(landmark, "landmark.json"), (geojson, "footprint.geojson")] {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                .write(to: out.appendingPathComponent(file))
        }
        return out
    }

    /// A folder name from a name: lowercase letters and digits joined by
    /// dashes, numbered when taken.
    static func slug(_ name: String, taken: Set<String>) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let words = latin.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let base = words.isEmpty ? "landmark" : words.joined(separator: "-")
        var id = base, n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }
}
