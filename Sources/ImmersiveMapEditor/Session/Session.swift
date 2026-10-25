import Foundation
import TileKit
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
    let landmarks = LandmarkCatalog()
    private(set) var landmarkView: LandmarkView?
    /// When and how sharp the imagery over the working tile was taken, by its
    /// source's metadata (Esri says it, Mapbox does not).
    var imageryCapture: String?
    /// What the Landmarks view shows: the model's size, or what went wrong.
    var landmarkStatus = ""
    private(set) var tiles: TileView?
    private(set) var model: RoadEditor?
    private(set) var roads: RoadsView?
    /// What went wrong last, shown as an alert.
    var problem: String?
    /// Whether seeding the roads again over the document's hand edits waits
    /// for the user's yes.
    var reseedAsked = false
    /// What the open dialog is asked for, if it is.
    var importing: Importing?

    enum Importing { case workspace, roads }

    init(root: URL) {
        workspace = Workspace(root: root)
        tiles = TileView(model: workspace)
        camera.frame(workspace)
        UserDefaults.standard.set(root.path, forKey: "workspace")
        scanLandmarks()
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
        scanLandmarks()
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

    /// The landmark models read again from Modeling and the workspace.
    func scanLandmarks() {
        landmarks.scan(WorkspacePaths(root: workspace.root))
    }

    /// The Landmarks view, made when first shown, showing the model picked.
    func showLandmark() {
        if landmarkView == nil {
            landmarkView = LandmarkView.make()
            landmarkView?.status = { [weak self] in self?.landmarkStatus = $0 }
        }
        landmarkView?.show(landmarks.selected?.glb)
    }

    /// The tile picked on the map is what every other view works on, alone:
    /// entering the Roads view opens the road document holding it and frames
    /// it, or closes the document open when none holds it.
    func follow(_ mode: ViewMode) {
        guard mode == .roads, let tile = workspace.tile else { return }
        guard let url = workspace.document(holding: tile) else {
            closeRoads()
            return
        }
        if model?.url != url { open(roads: url) }
        roads?.focus = tile
        Task { @MainActor in self.roads?.frame(tiles: [tile]) }
    }

    /// The road document open saved and closed.
    func closeRoads() {
        model?.saveIfNeeded()
        model = nil
        roads = nil
    }

    /// Reads the date of the imagery over the working tile from its source.
    func readImageryCapture(_ source: ImagerySource) async {
        imageryCapture = nil
        guard let t = workspace.tile else { return }
        let n = pow(2, Double(t.z))
        let lon = (Double(t.x) + 0.5) / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * (Double(t.y) + 0.5) / n))) * 180 / .pi
        imageryCapture = await source.capture(latitude: lat, longitude: lon)
    }

    // MARK: Building the working tile

    /// Whether `action` can run on the working tile now.
    func can(_ action: TileAction) -> Bool {
        guard let tile = workspace.tile, !build.running else { return false }
        switch action {
        case .everything, .roads: return true
        case .tile: return workspace.fetched.contains(tile)
        case .light: return workspace.built.contains(tile)
        }
    }

    /// Runs a view's action on the working tile. Seeding over a road document
    /// asks first (`reseedAsked`): it holds hand edits.
    func perform(_ action: TileAction) {
        guard let tile = workspace.tile, can(action) else { return }
        switch action {
        case .everything, .tile:
            run([buildStep(tile)])
        case .light:
            // A tile built before builds kept what a bake needs builds once first.
            let ready = FileManager.default.fileExists(atPath: TileModel.folder(root: workspace.root, z: tile.z, x: tile.x, y: tile.y)
                .appendingPathComponent("bake/scene.bin").path)
            let s = lightSettings
            run((ready ? [] : [buildStep(tile)])
                + [["bake", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)",
                    "--size", "\(s.size)", "--samples", "\(s.samples)", "--bounces", "\(s.bounces)"]])
        case .roads:
            if workspace.document(holding: tile) != nil { reseedAsked = true } else { seedRoads(force: false) }
        }
    }

    /// Seeds the road document holding the working tile (its range), or a new
    /// one of the tile alone, fetching the OSM it needs first. `force` writes
    /// over the hand edits of the one there.
    func seedRoads(force: Bool) {
        guard let tile = workspace.tile else { return }
        let range = workspace.document(holding: tile).flatMap { url in workspace.documents.first { $0.url == url }?.tiles }
            ?? RoadPlan.Tiles(z: tile.z, x0: tile.x, y0: tile.y, x1: tile.x, y1: tile.y)
        let missing = (range.y0...range.y1).flatMap { y in (range.x0...range.x1).map { TileKey(z: range.z, x: $0, y: y) } }
            .filter { !workspace.fetched.contains($0) }
        // The document open is closed first, so the seed is what it shows next.
        closeRoads()
        run(missing.map { ["fetch", "\($0.z)", "\($0.x)", "\($0.y)"] }
            + [["seed", "\(range.z)", "\(range.x0)", "\(range.y0)", "\(range.x1)", "\(range.y1)"] + (force ? ["--force"] : [])]) { _ in
            self.follow(self.workspace.viewMode)
        }
    }

    /// The pipeline's command building one tile: fetching what is missing,
    /// seeding its roads when no document holds it.
    private func buildStep(_ tile: TileKey) -> [String] {
        ["build", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)"]
    }

    /// Runs pipeline commands on the workspace, the road document open saved
    /// first, then reads the workspace again so every view shows the result.
    private func run(_ steps: [[String]], then: @escaping @MainActor (Bool) -> Void = { _ in }) {
        model?.saveIfNeeded()
        let workspace = self.workspace
        workspace.building = true
        build.run(root: workspace.root, steps: steps) { ok in
            workspace.building = false
            workspace.scan()
            workspace.tilesRevision += 1
            then(ok)
        }
    }
}
