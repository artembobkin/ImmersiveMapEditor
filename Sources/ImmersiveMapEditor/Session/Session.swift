import Foundation
import TileKit
import Observation

/// The app's global state: the workspace, the tile open and where the work
/// on it stands, the views over it, the road document open in the Roads
/// view, the build.
///
/// A session starts by choosing a tile on the map (`choosing`). Opening it
/// fetches its OSM and seeds its roads when they are missing (`preparing`),
/// then the views over it are there (`working`) until another is chosen.
@Observable
@MainActor
final class Session {
    enum Phase { case choosing, preparing, working }

    private(set) var workspace: Workspace
    private(set) var phase = Phase.choosing
    /// The tile picked on the map while choosing: the one opened next. It
    /// starts as the tile open last.
    var candidate: TileKey?
    let camera = MapCamera()
    let raster = RasterTiles()
    let build = BuildRunner()
    /// The camera the views over the open tile share.
    let viewCamera = SharedCamera()
    let panels = PanelLayout()
    let lights = LightMaps()
    let lightSettings = LightSettings()
    let landmarks = LandmarkCatalog()
    /// The open tile's buildings of OSM, for the Buildings view.
    let buildings = OsmBuildings()
    /// The open tile's landmark candidates, and the OSM elements they hold.
    private(set) var candidates: [(id: String, name: String, tile: String, folder: URL)] = []
    private(set) var candidateBuildings: [String] = []
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

    init(root: URL) {
        workspace = Workspace(root: root)
        candidate = workspace.tile
        tiles = TileView(model: workspace)
        tiles?.sharedCamera = viewCamera
        camera.frame(workspace)
        scanLandmarks()
    }

    /// Another data folder instead of the current one, back to choosing a
    /// tile in it.
    func open(workspace root: URL) {
        model?.saveIfNeeded()
        model = nil
        roads = nil
        workspace = Workspace(root: root)
        candidate = workspace.tile
        phase = .choosing
        tiles = TileView(model: workspace)
        tiles?.sharedCamera = viewCamera
        camera.frame(workspace)
        scanLandmarks()
    }

    // MARK: The tile open

    /// The tile the files and the map's panel show: the one open, or the one
    /// picked while choosing.
    var shownTile: TileKey? { phase == .choosing ? candidate : workspace.tile }

    /// Opens a tile to work on: its OSM fetched and its roads seeded first
    /// when they are missing, then its views.
    func open(tile: TileKey) {
        guard !build.running else { return }
        closeRoads()
        candidate = tile
        if workspace.tile != tile { viewCamera.forget() }
        workspace.tile = tile
        var steps: [[String]] = []
        if !workspace.fetched.contains(tile) { steps.append(["fetch", "\(tile.z)", "\(tile.x)", "\(tile.y)"]) }
        if workspace.document(holding: tile) == nil { steps.append(["seed", "\(tile.z)", "\(tile.x)", "\(tile.y)"]) }
        guard !steps.isEmpty else { return startWork() }
        phase = .preparing
        run(steps) { ok in
            if ok {
                self.startWork()
            } else {
                self.phase = .choosing
                self.problem = "\(tile.name) could not be prepared: the console says why."
            }
        }
    }

    /// Back to choosing a tile, the road document open saved.
    func chooseAnotherTile() {
        closeRoads()
        candidate = workspace.tile
        phase = .choosing
    }

    private func startWork() {
        phase = .working
        follow(workspace.viewMode)
    }

    /// Opens a road document in the Roads view.
    func open(roads url: URL) {
        model?.saveIfNeeded()
        do {
            let model = try RoadEditor(url: url)
            let view = RoadsView()
            view.model = model
            let camera = viewCamera
            view.cameraMoved = { t in camera.set(centre: t.centre, in: model.doc.projection, metresPerPoint: 1 / t.scale) }
            self.model = model
            roads = view
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

    /// The tile open is what every view works on, alone: entering the Roads
    /// view opens the road document holding it and frames it, or closes the
    /// document open when none holds it.
    func follow(_ mode: ViewMode) {
        if phase == .working, mode == .buildings {
            let tile = workspace.tile, paths = workspace.paths
            Task { @MainActor in
                await self.buildings.load(tile, paths: paths)
                self.readCandidates()
            }
        }
        if phase == .working, mode == .tiles || mode == .light {
            // The 3D view where the others looked, once it is laid out.
            Task { @MainActor in self.tiles?.takeSharedCamera() }
        }
        guard phase == .working, mode == .roads, let tile = workspace.tile else { return }
        guard let url = workspace.document(holding: tile) else {
            closeRoads()
            return
        }
        if model?.url != url { open(roads: url) }
        roads?.focus = tile
        Task { @MainActor in
            // Where the other views looked, else the tile framed.
            if let roads = self.roads, let model = self.model, let c = self.viewCamera.centre(in: model.doc.projection) {
                roads.look(at: c, scale: 1 / self.viewCamera.metresPerPoint)
            } else {
                self.roads?.frame(tiles: [tile])
            }
        }
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

    // MARK: Landmark candidates

    /// The open tile's landmark candidates read again.
    func readCandidates() {
        guard let tile = workspace.tile else { return }
        candidates = LandmarkCandidates.list(workspace.paths).filter { $0.tile == tile.name }
        candidateBuildings = LandmarkCandidates.osmIDs(workspace.paths, tile: tile)
    }

    /// The buildings picked in the Buildings view made a landmark candidate.
    func makeLandmark(named name: String) {
        guard let tile = workspace.tile, let projection = buildings.projection, !buildings.selected.isEmpty else { return }
        do {
            let folder = try LandmarkCandidates.make(name: name, buildings: buildings.selected, tile: tile,
                                                     projection: projection, paths: workspace.paths)
            buildings.picked = []
            readCandidates()
            Platform.open(folder)
        } catch {
            problem = "Cannot make the landmark \(name): \(error.localizedDescription)"
        }
    }

    // MARK: Building the working tile

    /// Whether `action` can run on the working tile now.
    func can(_ action: TileAction) -> Bool {
        guard phase == .working, let tile = workspace.tile, !build.running else { return false }
        switch action {
        case .roads: return true
        case .tile: return workspace.fetched.contains(tile)
        case .light: return workspace.built.contains(tile)
        }
    }

    /// Runs a view's action on the working tile. Seeding over a road document
    /// asks first (`reseedAsked`): it holds hand edits.
    func perform(_ action: TileAction) {
        guard let tile = workspace.tile, can(action) else { return }
        switch action {
        case .tile:
            run([buildStep(tile)])
        case .light:
            // A tile built before builds kept what a bake needs builds once first.
            let ready = FileManager.default.fileExists(atPath: workspace.build(tile).appendingPathComponent("bake/scene.bin").path)
            run((ready ? [] : [buildStep(tile)])
                + [["bake", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)"] + lightSettings.arguments])
        case .roads:
            if workspace.document(holding: tile) != nil { reseedAsked = true } else { seedRoads(force: false) }
        }
    }

    /// Seeds the tile open's road document, fetching its OSM first when it
    /// is missing. `force` writes over the hand edits of the one there.
    func seedRoads(force: Bool) {
        guard let tile = workspace.tile else { return }
        // The document open is closed first, so the seed is what it shows next.
        closeRoads()
        run((workspace.fetched.contains(tile) ? [] : [["fetch", "\(tile.z)", "\(tile.x)", "\(tile.y)"]])
            + [["seed", "\(tile.z)", "\(tile.x)", "\(tile.y)"] + (force ? ["--force"] : [])]) { _ in
            self.follow(self.workspace.viewMode)
        }
    }

    /// The pipeline's command building one tile, its models all, its light
    /// not baked (the Light view bakes it): fetching what is missing,
    /// seeding its roads when no document holds it.
    private func buildStep(_ tile: TileKey) -> [String] {
        ["build", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)", "--no-light"]
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
