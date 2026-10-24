import Foundation

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
    var id: String { rawValue }
}

/// What TilePipeline (the folder `root`) has of every tile: fetched OSM
/// (data/<z>_<x>_<y>/osm.json), a built model (out/tiles/<z>/<x>/<y>/), the
/// road document holding it (roads/). And the tiles picked on the map and
/// shown together in 3D.
final class Workspace: ObservableObject {
    static let zoom = 15

    let root: URL
    @Published var viewMode: ViewMode = .map
    @Published private(set) var fetched: Set<TileKey> = []
    @Published private(set) var built: Set<TileKey> = []
    @Published private(set) var documents: [(url: URL, tiles: RoadDocument.Tiles)] = []
    /// The tiles picked on the map.
    @Published var selection: Set<TileKey> = [] {
        didSet { remember() }
    }
    /// The tiles the 3D view shows, together.
    @Published var shown: [TileKey] = [] {
        didSet { remember(); tilesRevision += 1 }
    }
    @Published var flying = false
    @Published var showLightMap = true
    @Published var tileStatus = ""
    /// Bumped when the tiles shown or their builds change, so the 3D view
    /// reloads them.
    @Published var tilesRevision = 0
    @Published var building = false

    init(root: URL) {
        self.root = root
        let d = UserDefaults.standard
        if let data = d.data(forKey: "selection"), let s = try? JSONDecoder().decode(Set<TileKey>.self, from: data) {
            selection = s
        }
        if let data = d.data(forKey: "shown"), let s = try? JSONDecoder().decode([TileKey].self, from: data) {
            shown = s
        }
        scan()
        if shown.isEmpty, let first = documents.first {
            let t = first.tiles
            shown = (t.y0...t.y1).flatMap { y in (t.x0...t.x1).map { TileKey(z: t.z, x: $0, y: y) } }
        }
    }

    private func remember() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(selection), forKey: "selection")
        d.set(try? JSONEncoder().encode(shown), forKey: "shown")
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
        var docs: [(URL, RoadDocument.Tiles)] = []
        let roads = root.appendingPathComponent("roads")
        for name in ((try? fm.contentsOfDirectory(atPath: roads.path)) ?? []).sorted() where name.hasSuffix(".json") {
            let url = roads.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let t = json["tiles"] as? [String: Int], let tz = t["z"], let x0 = t["x0"], let y0 = t["y0"],
               let x1 = t["x1"], let y1 = t["y1"] {
                docs.append((url, RoadDocument.Tiles(z: tz, x0: x0, y0: y0, x1: x1, y1: y1)))
            }
        }
        fetched = f
        built = b
        documents = docs
    }

    /// The road document holding a tile.
    func document(holding t: TileKey) -> URL? {
        documents.first { d in
            d.tiles.z == t.z && (d.tiles.x0...d.tiles.x1).contains(t.x) && (d.tiles.y0...d.tiles.y1).contains(t.y)
        }?.url
    }

    /// The projection the 3D view places the tiles shown in: their range's.
    var shownProjection: Projection? {
        guard let first = shown.first else { return nil }
        let xs = shown.map(\.x), ys = shown.map(\.y)
        return Projection(z: first.z, x0: xs.min()!, y0: ys.min()!, x1: xs.max()!, y1: ys.max()!)
    }
}
