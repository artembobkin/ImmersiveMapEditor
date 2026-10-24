import Foundation
import Observation

/// What the window shows: the workspace, the views of its modes, the road
/// document open in the Roads view, the build.
@Observable
@MainActor
final class Session {
    private(set) var workspace: Workspace
    let camera = MapCamera()
    let raster = RasterTiles()
    let build = BuildRunner()
    private(set) var tiles: TileView?
    private(set) var model: RoadEditor?
    private(set) var roads: RoadsView?
    /// What went wrong last, shown as an alert.
    var problem: String?
    /// What the open dialog is asked for, if it is.
    var importing: Importing?

    enum Importing { case workspace, roads }

    init(root: URL) {
        workspace = Workspace(root: root)
        tiles = TileView(model: workspace)
        camera.frame(workspace)
        UserDefaults.standard.set(root.path, forKey: "workspace")
    }

    /// A TilePipeline folder instead of the current one.
    func open(workspace root: URL) {
        model?.saveIfNeeded()
        model = nil
        roads = nil
        workspace = Workspace(root: root)
        tiles = TileView(model: workspace)
        camera.frame(workspace)
        UserDefaults.standard.set(root.path, forKey: "workspace")
    }

    /// Opens a road document in the Roads view.
    func open(roads url: URL) {
        model?.saveIfNeeded()
        do {
            let model = try RoadEditor(url: url)
            let view = RoadsView()
            view.model = model
            self.model = model
            roads = view
            workspace.viewMode = .roads
            Task { @MainActor in view.frameAll() }
        } catch {
            problem = "Cannot open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Fetches what is missing and builds `tiles` (the road document open is
    /// saved first), then shows them.
    func build(_ tiles: [TileKey]) {
        guard let z = tiles.first?.z else { return }
        model?.saveIfNeeded()
        let workspace = self.workspace
        workspace.building = true
        build.run(root: workspace.root, arguments: ["build", "\(z)", "--tiles"] + tiles.map { "\($0.x)/\($0.y)" }) {
            workspace.building = false
            workspace.scan()
            let built = tiles.filter { workspace.built.contains($0) }
            if !built.isEmpty { workspace.shown = built } else { workspace.tilesRevision += 1 }
        }
    }

    /// The tiles picked on the map, or else those of the road document open.
    func buildPickedOrOpen() {
        var tiles = workspace.selection.sorted()
        if workspace.viewMode != .map || tiles.isEmpty, let t = model?.doc.tiles {
            tiles = (t.y0...t.y1).flatMap { y in (t.x0...t.x1).map { TileKey(z: t.z, x: $0, y: y) } }
        }
        build(tiles)
    }
}
