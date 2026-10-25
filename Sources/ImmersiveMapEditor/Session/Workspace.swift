import Foundation
import TileKit
import Observation

/// A z15 tile.
struct TileKey: Hashable, Codable, Comparable {
    let z, x, y: Int
    var name: String { "\(z)/\(x)/\(y)" }
    static func < (a: TileKey, b: TileKey) -> Bool { (a.y, a.x) < (b.y, b.x) }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case map = "Map"
    case roads = "Roads"
    case tiles = "Tiles 3D"
    case light = "Light"
    case landmarks = "Landmarks"
    var id: String { rawValue }
}

/// What TilePipeline (the folder `root`) has of every tile: fetched OSM
/// (data/<z>_<x>_<y>/osm.json), a built model (out/tiles/<z>/<x>/<y>/), the
/// road document holding it (roads/). And the tiles picked on the map,
/// which every view works on.
@Observable
final class Workspace {
    static let zoom = 15

    let root: URL
    var viewMode: ViewMode = .map
    private(set) var fetched: Set<TileKey> = []
    private(set) var built: Set<TileKey> = []
    private(set) var documents: [(url: URL, tiles: RoadPlan.Tiles)] = []
    /// The tiles picked on the map: what every view works on.
    var selection: Set<TileKey> = [] {
        didSet {
            remember()
            follow()
        }
    }
    /// The tiles the 3D view shows together: those picked that are built.
    private(set) var shown: [TileKey] = [] {
        didSet { tilesRevision += 1 }
    }
    var flying = false
    var showLightMap = true
    var tileStatus = ""
    /// Bumped when the tiles shown or their builds change, so the 3D view
    /// reloads them.
    var tilesRevision = 0
    var building = false

    /// Whether the tiles picked are kept for the next run: not for a run
    /// without a window.
    private let remembers: Bool

    init(root: URL, remembers: Bool = true) {
        self.root = root
        self.remembers = remembers
        let d = UserDefaults.standard
        if remembers, let data = d.data(forKey: "selection"), let s = try? JSONDecoder().decode(Set<TileKey>.self, from: data) {
            selection = s
        }
        scan()
    }

    private func remember() {
        guard remembers else { return }
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(selection), forKey: "selection")
    }

    /// The tiles shown, from the tiles picked and those built.
    private func follow() {
        let next = selection.filter { built.contains($0) }.sorted()
        if next != shown { shown = next }
    }

    /// Reads again what is on disk.
    func scan() {
        let fm = FileManager.default
        var f = Set<TileKey>(), b = Set<TileKey>()
        let data = root.appendingPathComponent("data")
        for name in (try? fm.contentsOfDirectory(atPath: data.path)) ?? [] {
            let p = name.split(separator: "_").compactMap { Int($0) }
            if p.count == 3, fm.fileExists(atPath: data.appendingPathComponent("\(name)/osm.json").path) {
                f.insert(TileKey(z: p[0], x: p[1], y: p[2]))
            }
        }
        let z = Workspace.zoom
        let out = root.appendingPathComponent("out/tiles/\(z)")
        for x in (try? fm.contentsOfDirectory(atPath: out.path)) ?? [] {
            for y in (try? fm.contentsOfDirectory(atPath: out.appendingPathComponent(x).path)) ?? [] {
                if let xi = Int(x), let yi = Int(y),
                   fm.fileExists(atPath: out.appendingPathComponent("\(x)/\(y)/placement.json").path) {
                    b.insert(TileKey(z: z, x: xi, y: yi))
                }
            }
        }
        var docs: [(URL, RoadPlan.Tiles)] = []
        let roads = root.appendingPathComponent("roads")
        for name in ((try? fm.contentsOfDirectory(atPath: roads.path)) ?? []).sorted() where name.hasSuffix(".json") {
            let url = roads.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let t = json["tiles"] as? [String: Int], let tz = t["z"], let x0 = t["x0"], let y0 = t["y0"],
               let x1 = t["x1"], let y1 = t["y1"] {
                docs.append((url, RoadPlan.Tiles(z: tz, x0: x0, y0: y0, x1: x1, y1: y1)))
            }
        }
        fetched = f
        built = b
        documents = docs
        follow()
    }

    /// The road document holding a tile.
    func document(holding t: TileKey) -> URL? {
        documents.first { d in
            d.tiles.z == t.z && (d.tiles.x0...d.tiles.x1).contains(t.x) && (d.tiles.y0...d.tiles.y1).contains(t.y)
        }?.url
    }

    /// The projection the 3D view places the tiles shown in: their range's.
    var shownProjection: Region? {
        guard let first = shown.first else { return nil }
        let xs = shown.map(\.x), ys = shown.map(\.y)
        return Region(z: first.z, x0: xs.min()!, y0: ys.min()!, x1: xs.max()!, y1: ys.max()!)
    }
}
