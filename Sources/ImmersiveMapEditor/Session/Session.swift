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
    let lights = LightMaps()
    let lightSettings = LightSettings()
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

    /// Bakes the light of built tiles again with the Light view's settings,
    /// their geometry as built, then shows the new light maps.
    func bake(_ tiles: [TileKey]) {
        guard let z = tiles.first?.z else { return }
        let workspace = self.workspace, s = lightSettings
        workspace.building = true
        build.run(root: workspace.root, arguments: ["bake", "\(z)", "--tiles"] + tiles.map { "\($0.x)/\($0.y)" }
                  + ["--size", "\(s.size)", "--samples", "\(s.samples)", "--bounces", "\(s.bounces)"]) {
            workspace.building = false
            workspace.scan()
            workspace.tilesRevision += 1
        }
    }

    /// The tiles picked on the map are what every view works on: entering a
    /// view, the Roads view opens the road document holding them and frames
    /// them, the 3D view shows those built. Nothing picked, a view keeps what
    /// it had.
    func follow(_ mode: ViewMode) {
        let picked = workspace.selection.sorted()
        guard !picked.isEmpty else { return }
        switch mode {
        case .map, .light:
            break
        case .roads:
            guard let url = picked.lazy.compactMap({ self.workspace.document(holding: $0) }).first else { return }
            if model?.url != url { open(roads: url) }
            let inside = picked.filter { workspace.document(holding: $0) == url }
            Task { @MainActor in self.roads?.frame(tiles: inside) }
        case .tiles:
            let built = picked.filter { workspace.built.contains($0) }
            if !built.isEmpty && built != workspace.shown { workspace.shown = built }
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
