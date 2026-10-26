import Foundation
import Geometry
import TileKit

/// The buildings of a tile marked to become landmarks, each a folder of the
/// tile's own folder, landmarks/<id>/, holding what a detailed model can be
/// made from (by hand, by a tool, by an AI): `landmark.json` (its name, tile,
/// place, and every building and part with its OSM id, all its tags, its
/// heights and its outline in longitude and latitude) and `footprint.geojson`
/// (the same outlines, the tags as properties, for any GIS tool). A
/// candidate changes nothing of the tile's build until a model of it is
/// made and placed.
/// One of a tile's landmarks, as its folder has it: its name, the OSM
/// elements it is made of, and its model when one is there (a GLB in its
/// folder, made from what the folder holds).
struct TileLandmark: Identifiable {
    let id: String
    let name: String
    let folder: URL
    let buildings: [String]
    /// How detailed its model is to be: simple, normal or detailed.
    let detail: String
    var model: URL? {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "glb" }.sorted { $0.path < $1.path }.first
    }

    /// One of its OSM buildings as a box: its outline's polygons (rings in
    /// metres around the landmark's centre, east and north), from its base
    /// to its top.
    struct Box {
        let polygons: [[[Vec2]]]
        let base, top: Double
    }

    /// Its OSM buildings as boxes, as a map of OSM data draws them in 3D:
    /// its parts when it has any (the outline they stand in left out), else
    /// its outlines, each from its min_height to its height (10 m a part or
    /// 12 m a building that says none).
    var boxes: [Box] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("landmark.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let centre = json["centre"] as? [Double], centre.count == 2 else { return [] }
        let all = json["buildings"] as? [[String: Any]] ?? []
        let parts = all.filter { $0["part"] as? Bool == true }
        let k = cos(centre[1] * .pi / 180) * 111_320.0
        func metres(_ p: [Double]) -> Vec2 { Vec2((p[0] - centre[0]) * k, (p[1] - centre[1]) * 110_574) }
        return (parts.isEmpty ? all : parts).map { b in
            let outline = b["outline"] as? [[[[Double]]]] ?? []
            let polygons = outline.map { $0.map { ring in Array(ring.dropLast()).filter { $0.count >= 2 }.map(metres) } }
            let base = (b["min_height_m"] as? NSNumber)?.doubleValue ?? 0
            let top = (b["height_m"] as? NSNumber)?.doubleValue ?? (b["part"] as? Bool == true ? 10 : 12)
            return Box(polygons: polygons, base: base, top: max(top, base + 0.5))
        }
    }
}

enum LandmarkCandidates {
    static func folder(_ paths: WorkspacePaths, _ tile: TileKey) -> URL { paths.tileLandmarks(z: tile.z, x: tile.x, y: tile.y) }

    /// The tile's landmarks, by their folders.
    static func list(_ paths: WorkspacePaths, tile: TileKey) -> [TileLandmark] {
        let root = folder(paths, tile)
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted().compactMap { id in
            let f = root.appendingPathComponent(id)
            guard let data = try? Data(contentsOf: f.appendingPathComponent("landmark.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let osm = (json["buildings"] as? [[String: Any]] ?? []).compactMap { $0["osm"] as? String }
            return TileLandmark(id: id, name: json["name"] as? String ?? id, folder: f, buildings: osm,
                                detail: json["detail"] as? String ?? "normal")
        }
    }

    /// Sets how detailed a landmark's model is to be, in its landmark.json.
    static func setDetail(_ folder: URL, _ detail: String) {
        let url = folder.appendingPathComponent("landmark.json")
        guard let data = try? Data(contentsOf: url), var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        json["detail"] = detail
        try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    /// Writes a candidate of `buildings` named `name`, in `tile` projected by
    /// `projection`. Returns its folder.
    static func make(name: String, buildings: [OsmBuilding], tile: TileKey, projection: Projecting,
                     paths: WorkspacePaths) throws -> URL {
        let id = slug(name, taken: Set(list(paths, tile: tile).map(\.id)))
        let out = folder(paths, tile).appendingPathComponent(id)
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

    /// A folder name from a name, in Latin letters: lowercase a to z and
    /// digits joined by dashes (Большой театр: bolsoj-teatr), numbered when
    /// taken.
    static func slug(_ name: String, taken: Set<String>) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let kept = latin.lowercased().unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == " " || $0 == "-" }
        let words = String(String.UnicodeScalarView(kept)).split { $0 == " " || $0 == "-" }.map(String.init)
        let base = words.isEmpty ? "landmark" : words.joined(separator: "-")
        var id = base, n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }
}
