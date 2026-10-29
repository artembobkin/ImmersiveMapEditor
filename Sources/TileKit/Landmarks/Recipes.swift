import Foundation
import Geometry
import GLTF

/// The landmark models' recipes (landmarks/models.json of the data folder)
/// and where the models are: the tile's own landmarks/ folders.
extension Imported {
    static func recipes(_ paths: WorkspacePaths) -> [String: [String: Any]] {
        let url = paths.landmarks.appendingPathComponent("models.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json["models"] as? [String: [String: Any]] ?? [:]
    }

    /// A model's recipe: its own entry, else the longest matching prefix
    /// entry ("kremlin-*"), over the defaults.
    static func recipe(_ ident: String, _ book: [String: [String: Any]]) -> [String: Any] {
        var out = book["default"] ?? [:]
        var colours = out["colours"] as? [String: String] ?? [:]
        let prefixes = book.keys.filter { $0.hasSuffix("*") && ident.hasPrefix(String($0.dropLast())) }
            .sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
        for k in prefixes + (book[ident] != nil ? [ident] : []) {
            let entry = book[k]!
            for (key, value) in entry where key != "colours" { out[key] = value }
            for (key, value) in entry["colours"] as? [String: String] ?? [:] { colours[key] = value }
        }
        out["colours"] = colours
        return out
    }

    /// The placements of the tile's own landmarks: each folder of its
    /// landmarks/ (made in the editor's Buildings view) with a model in it.
    /// Its landmark.json says where it stands (`centre`, longitude and
    /// latitude: the model's origin) and what of OSM it stands for (its
    /// `buildings`' `osm` ids, left out of the build); its model is the
    /// first GLB of the folder, in metres around that origin, +Y up. A
    /// landmark with no model yet is left alone: its buildings are built as
    /// any other.
    static func placements(_ tile: Tile, _ work: Geometry, _ paths: WorkspacePaths) -> [Placement] {
        let fm = FileManager.default
        let root = paths.tileLandmarks(z: tile.z, x: tile.x, y: tile.y)
        var found: [Placement] = []
        for name in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() {
            let folder = root.appendingPathComponent(name)
            guard let data = fm.contents(atPath: folder.appendingPathComponent("landmark.json").path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let centre = json["centre"] as? [Double], centre.count == 2,
                  let glb = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    .filter({ $0.pathExtension.lowercased() == "glb" }).sorted(by: { $0.path < $1.path }).first
            else { continue }
            let (lon, lat) = (centre[0], centre[1])
            let replaces = Set((json["buildings"] as? [[String: Any]] ?? []).compactMap { $0["osm"] as? String })
            found.append(Placement(id: name, glb: glb, origin: tile.metres(lat: lat, lon: lon), latitude: lat,
                                   altitude: (json["altitude_m"] as? NSNumber)?.doubleValue ?? 0, replaces: replaces))
        }
        // The neighbours' landmarks standing within the margin, from the
        // registry: in the scene for the light, and their buildings left
        // out of this tile's ordinary build (the user, 2026-10-29).
        if let registry = try? Registry(paths) {
            let (x0, y0, x1, y1) = work.bounds
            for l in registry.landmarks(z: tile.z) where l.hasModel && !(l.x == tile.x && l.y == tile.y) {
                let origin = tile.metres(lat: l.latitude, lon: l.longitude)
                guard origin.x >= x0, origin.x <= x1, origin.y >= y0, origin.y <= y1 else { continue }
                let folder = paths.root.appendingPathComponent(l.folder)
                guard let glb = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                        .filter({ $0.pathExtension.lowercased() == "glb" }).sorted(by: { $0.path < $1.path }).first else { continue }
                found.append(Placement(id: "\(l.x)-\(l.y)-\(l.id)", glb: glb, origin: origin, latitude: l.latitude, altitude: 0,
                                       replaces: Set(l.buildings)))
            }
        }
        return found
    }
}
