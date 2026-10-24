import Foundation
import Geometry
import GLTF

/// The landmark models' recipes (landmarks/models.json) and where the
/// models are (their placement.json, in Modeling and in landmarks/models/).
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

    /// The placements of the models near `work`.
    static func placements(_ tile: Tile, _ work: Geometry, _ paths: WorkspacePaths) -> [Placement] {
        let (x0, y0, x1, y1) = work.buffer(modelReach).bounds
        let fm = FileManager.default
        var files: [String] = []
        let base = paths.modeling.appendingPathComponent("14")
        if let walk = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in walk where url.lastPathComponent == "placement.json" {
                // 14/*/*/**/placement.json: two folders at least below 14.
                if url.pathComponents.count - base.pathComponents.count >= 3 { files.append(url.path) }
            }
        }
        files.sort()
        let own = paths.landmarks.appendingPathComponent("models")
        files += ((try? fm.contentsOfDirectory(atPath: own.path)) ?? []).sorted().compactMap { name in
            let p = own.appendingPathComponent(name).appendingPathComponent("placement.json").path
            return fm.fileExists(atPath: p) ? p : nil
        }
        var found: [Placement] = []
        for path in files where !path.contains("_revisions") && !path.contains("/sources/") {
            guard let data = fm.contents(atPath: path),
                  let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let o = p["origin"] as? [String: Any], let lat = (o["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (o["longitude"] as? NSNumber)?.doubleValue, let model = p["model"] as? String, !model.isEmpty
            else { continue }
            let xy = tile.metres(lat: lat, lon: lon)
            let glb = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(model)
            guard x0 <= xy.x, xy.x <= x1, y0 <= xy.y, xy.y <= y1, fm.fileExists(atPath: glb.path) else { continue }
            var ids = Set<String>()
            if let r = p["replaces"] as? [String: [Any]] {
                for v in r.values { for i in v { ids.insert("\(i)") } }
            } else if let r = p["replaces"] as? [Any] {
                for i in r { ids.insert("\(i)") }
            }
            found.append(Placement(id: p["id"] as? String ?? "", glb: glb, origin: xy, latitude: lat,
                                   altitude: (p["altitude_m"] as? NSNumber)?.doubleValue ?? 0, replaces: ids))
        }
        return found
    }
}
