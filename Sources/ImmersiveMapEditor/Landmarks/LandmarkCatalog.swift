import Foundation
import Observation
import TileKit

/// A landmark model ready to be placed: a hand-made model of Modeling or a
/// downloaded one of the workspace's landmarks/models/, as the pipeline finds
/// them (its `placement.json`, the GLB beside it).
struct Landmark: Identifiable, Hashable {
    enum Source: String { case modeling = "Modeling", downloaded = "Downloaded" }
    let id: String
    /// The model's folder name, made readable.
    let name: String
    let glb: URL
    let folder: URL
    let latitude, longitude: Double
    /// The z15 tile its origin stands in: the tile that owns it.
    let tile: TileKey
    let source: Source
    /// Whether landmarks/models.json has a recipe of its own for it.
    let hasRecipe: Bool
}

/// The landmark models on disk, the one picked in the Landmarks view, and
/// what the list shows.
@Observable
@MainActor
final class LandmarkCatalog {
    private(set) var all: [Landmark] = []
    var picked: Landmark.ID?
    var query = ""
    /// Only the models standing in the tiles picked on the map.
    var onlyPickedTiles = true

    var selected: Landmark? { all.first { $0.id == picked } }

    /// The models listed, by the query and the tiles picked.
    func listed(in tiles: Set<TileKey>) -> [Landmark] {
        all.filter { m in
            (!onlyPickedTiles || tiles.isEmpty || tiles.contains(m.tile))
                && (query.isEmpty || m.name.localizedCaseInsensitiveContains(query) || m.id.localizedCaseInsensitiveContains(query))
        }
    }

    /// Reads the models again: Modeling's 14/*/*/**/placement.json, then the
    /// workspace's landmarks/models/*/placement.json, as Imported finds them.
    func scan(_ paths: WorkspacePaths) {
        let fm = FileManager.default
        var files: [(URL, Landmark.Source)] = []
        let base = paths.modeling.appendingPathComponent("14")
        if let walk = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in walk where url.lastPathComponent == "placement.json"
                && url.pathComponents.count - base.pathComponents.count >= 3 {
                files.append((url, .modeling))
            }
        }
        let own = paths.landmarks.appendingPathComponent("models")
        for name in (try? fm.contentsOfDirectory(atPath: own.path)) ?? [] {
            let url = own.appendingPathComponent(name).appendingPathComponent("placement.json")
            if fm.fileExists(atPath: url.path) { files.append((url, .downloaded)) }
        }
        let recipes = (try? Data(contentsOf: paths.landmarks.appendingPathComponent("models.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["models"] as? [String: Any] ?? [:]
        var out: [Landmark] = []
        for (url, source) in files where !url.path.contains("_revisions") && !url.path.contains("/sources/") {
            guard let data = try? Data(contentsOf: url),
                  let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let o = p["origin"] as? [String: Any], let lat = (o["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (o["longitude"] as? NSNumber)?.doubleValue, let model = p["model"] as? String, !model.isEmpty
            else { continue }
            let folder = url.deletingLastPathComponent()
            let glb = folder.appendingPathComponent(model)
            guard fm.fileExists(atPath: glb.path) else { continue }
            let id = p["id"] as? String ?? folder.lastPathComponent
            let name = folder.lastPathComponent.replacingOccurrences(of: "_512", with: "")
                .replacingOccurrences(of: "_", with: " ")
            out.append(Landmark(id: id, name: name, glb: glb, folder: folder, latitude: lat, longitude: lon,
                                tile: Self.tile(lat: lat, lon: lon), source: source, hasRecipe: recipes[id] != nil))
        }
        all = out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The z15 tile of a point, standard XYZ numbering.
    static func tile(lat: Double, lon: Double) -> TileKey {
        let n = pow(2, Double(Workspace.zoom)), r = lat * .pi / 180
        return TileKey(z: Workspace.zoom, x: Int(((lon + 180) / 360 * n).rounded(.down)),
                       y: Int(((1 - asinh(tan(r)) / .pi) / 2 * n).rounded(.down)))
    }
}
