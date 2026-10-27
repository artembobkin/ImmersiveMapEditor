import Foundation
import TileKit
import Observation

/// A z15 tile.
struct TileKey: Hashable, Codable, Comparable {
    let z, x, y: Int
    var name: String { "\(z)/\(x)/\(y)" }
    static func < (a: TileKey, b: TileKey) -> Bool { (a.y, a.x) < (b.y, b.x) }
}

/// The views over the open tile, the tabs at the top once a tile is open.
enum ViewMode: String, CaseIterable, Identifiable {
    case roads = "Roads"
    case tiles = "Tiles 3D"
    case preview = "Preview"
    case landmarks = "Landmarks"
    case buildings = "Buildings"
    case style = "Style"
    var id: String { rawValue }
}

/// What the app's data folder (`root`, laid out as TileKit's WorkspacePaths:
/// a folder a tile) has of every tile: its OSM fetched, its road document,
/// its model built. And the tile open, which every view works on.
@Observable
final class Workspace {
    static let zoom = 15

    let root: URL
    /// Where everything of a tile lies, the pipeline's own description.
    let paths: WorkspacePaths
    var viewMode: ViewMode = .roads
    private(set) var fetched: Set<TileKey> = []
    private(set) var built: Set<TileKey> = []
    private(set) var documents: [(url: URL, tiles: RoadPlan.Tiles)] = []
    /// The tile open, the one every view works on (Session opens it).
    var tile: TileKey? {
        didSet {
            remember()
            follow()
        }
    }
    /// What the 3D view shows: the tile picked, once it is built.
    private(set) var shown: [TileKey] = [] {
        didSet { tilesRevision += 1 }
    }
    var flying = false
    /// How the Preview colours the tile: lit, or its light alone.
    var lightShading = TileShading.lit
    /// What the Preview shows lit: the tile ("tile"), or a landmark of it by
    /// its id, alone.
    var previewSubject = "tile"
    var tileStatus = ""
    /// Bumped when the tiles shown or their builds change, so the 3D view
    /// reloads them.
    var tilesRevision = 0
    var building = false

    /// Whether the tile picked is kept for the next run: not for a run
    /// without a window.
    private let remembers: Bool

    init(root: URL, remembers: Bool = true) {
        self.root = root
        paths = WorkspacePaths(root: root)
        self.remembers = remembers
        let d = UserDefaults.standard
        if remembers, let data = d.data(forKey: "tile"), let t = try? JSONDecoder().decode(TileKey.self, from: data) {
            tile = t
        }
        scan()
    }

    private func remember() {
        guard remembers else { return }
        let d = UserDefaults.standard
        d.set(tile.flatMap { try? JSONEncoder().encode($0) }, forKey: "tile")
    }

    /// The tile shown, from the tile picked and those built.
    private func follow() {
        let next = tile.map { built.contains($0) ? [$0] : [] } ?? []
        if next != shown { shown = next }
    }

    /// Reads again what is on disk: tiles/<z>/<x>/<y>/, the zoom's.
    func scan() {
        let fm = FileManager.default
        var f = Set<TileKey>(), b = Set<TileKey>()
        var docs: [(URL, RoadPlan.Tiles)] = []
        let z = Workspace.zoom
        let zoom = paths.tiles.appendingPathComponent("\(z)")
        for x in (try? fm.contentsOfDirectory(atPath: zoom.path)) ?? [] {
            for y in (try? fm.contentsOfDirectory(atPath: zoom.appendingPathComponent(x).path)) ?? [] {
                guard let xi = Int(x), let yi = Int(y) else { continue }
                let t = TileKey(z: z, x: xi, y: yi)
                if fm.fileExists(atPath: paths.tileData(z: z, x: xi, y: yi).appendingPathComponent("osm.json").path) { f.insert(t) }
                if fm.fileExists(atPath: paths.tileOut(z: z, x: xi, y: yi).appendingPathComponent("placement.json").path) { b.insert(t) }
                let doc = paths.roadDocument(z: z, x: xi, y: yi)
                if fm.fileExists(atPath: doc.path) { docs.append((doc, RoadPlan.Tiles(z: z, x0: xi, y0: yi, x1: xi, y1: yi))) }
            }
        }
        fetched = f
        built = b
        documents = docs
        follow()
    }

    /// The road document of a tile, in its folder, if it has one.
    func document(holding t: TileKey) -> URL? {
        documents.first { d in d.tiles.z == t.z && d.tiles.x0 == t.x && d.tiles.y0 == t.y }?.url
    }

    /// A tile's folder: everything of it.
    func folder(_ t: TileKey) -> URL { paths.tile(z: t.z, x: t.x, y: t.y) }

    /// A tile's built model's folder.
    func build(_ t: TileKey) -> URL { paths.tileOut(z: t.z, x: t.x, y: t.y) }

    /// The projection the 3D view places the tiles shown in: their range's.
    var shownProjection: Region? {
        guard let first = shown.first else { return nil }
        let xs = shown.map(\.x), ys = shown.map(\.y)
        return Region(z: first.z, x0: xs.min()!, y0: ys.min()!, x1: xs.max()!, y1: ys.max()!)
    }
}
