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
    /// The open tile's buildings of OSM, for the Buildings view.
    let buildings = OsmBuildings()
    /// Claude modelling a landmark.
    let agent = LandmarkAgent()
    /// The palette's colours set over the defaults, in the Style view.
    let palette = PaletteEdits()
    /// A picture of the files sidebar the pointer rests on: shown large
    /// over the main area, so a reference is seen without opening it.
    var hoveredPicture: URL?
    /// The open tile's landmarks (its landmarks/ folder), the one picked in
    /// the Landmarks view, and the OSM elements they are made of.
    private(set) var candidates: [TileLandmark] = []
    var pickedLandmark: String?
    /// The Landmarks view's wireframe over the shading.
    var landmarkWireframe = false { didSet { landmarkView?.wireframe = landmarkWireframe } }
    var candidateBuildings: [String] { candidates.flatMap(\.buildings) }
    private(set) var landmarkView: LandmarkView?
    /// When and how sharp the imagery over the working tile was taken, by its
    /// source's metadata (Esri says it, Mapbox does not).
    var imageryCapture: String?
    /// What the Landmarks view shows: the model's size, or what went wrong.
    var landmarkStatus = ""
    /// The Landmarks and Preview cameras as the headless render takes them.
    var landmarkCamera = ""
    var previewCamera = ""
    /// The Preview's axis labels on the screen.
    var previewLabels: [ViewLabel] = []
    /// The Preview's view of a landmark lit, and what it shows.
    private(set) var previewView: LandmarkView?
    var previewStatus = ""
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
        palette.load(workspace.paths)
        agent.modelChanged = { [weak self] in self?.showLandmark(again: true) }
    }

    /// Another data folder instead of the current one, back to choosing a
    /// tile in it.
    func open(workspace root: URL) {
        model?.saveIfNeeded()
        model = nil
        roads = nil
        workspace = Workspace(root: root)
        palette.load(workspace.paths)
        candidate = workspace.tile
        phase = .choosing
        tiles = TileView(model: workspace)
        tiles?.sharedCamera = viewCamera
        camera.frame(workspace)
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

    /// The Landmarks view, made when first shown, showing the model picked.
    /// The picked landmark's model built from its recipe (a starter recipe
    /// from OSM's tags first when it has none), then shown.
    func buildLandmark() {
        guard let landmark = candidates.first(where: { $0.id == pickedLandmark }) else { return }
        build.run(root: workspace.root, arguments: ["landmark", landmark.folder.path]) { [weak self] _ in
            self?.readCandidates()
            self?.showLandmark(again: true)
        }
    }

    /// A landmark deleted whole: its folder, with everything in it.
    func deleteLandmark(_ landmark: TileLandmark) {
        guard !agent.running else { return }
        try? FileManager.default.removeItem(at: landmark.folder)
        if pickedLandmark == landmark.id { pickedLandmark = nil }
        readCandidates()
        workspace.tilesRevision += 1
        showLandmark(again: true)
    }

    /// The picked landmark's folder changed by hand (its work forgotten):
    /// shown again, the files listed again.
    func landmarkWorkChanged() {
        workspace.tilesRevision += 1
        showLandmark(again: true)
    }

    func modelLandmark(request: String? = nil) {
        guard let landmark = candidates.first(where: { $0.id == pickedLandmark }) else { return }
        agent.start(folder: landmark.folder, name: landmark.name, request: request, console: build)
    }

    /// The Preview's landmark lit: its light baked with the Preview's
    /// settings, off the main thread, the model shown as it was meanwhile.
    func showPreview() {
        guard workspace.previewSubject != "tile" else { return }
        if previewView == nil {
            previewView = LandmarkView.make()
            previewView?.status = { [weak self] in self?.previewStatus = $0 }
            previewView?.camera = { [weak self] in self?.previewCamera = $0 }
            previewView?.labels = { [weak self] in self?.previewLabels = $0 }
        }
        previewView?.shadowStrength = lightSettings.previewShadow
        previewView?.lens = lightSettings.lens
        guard let landmark = candidates.first(where: { $0.id == workspace.previewSubject }), let glb = landmark.model else {
            previewView?.show(nil)
            return
        }
        previewView?.show(.lit(glb, lightSettings.settings))
    }

    func showLandmark(again: Bool = false) {
        if landmarkView == nil {
            landmarkView = LandmarkView.make()
            landmarkView?.wireframe = landmarkWireframe
            landmarkView?.camera = { [weak self] in self?.landmarkCamera = $0 }
            landmarkView?.status = { [weak self] in
                self?.landmarkStatus = $0
                // While the agent works, the console says what the view shows.
                if self?.agent.running == true { self?.build.append("  view: \($0)") }
            }
        }
        // Its model, or its OSM buildings as boxes while it has none.
        guard let landmark = candidates.first(where: { $0.id == pickedLandmark }) else { return landmarkView?.show(nil) ?? () }
        landmarkView?.show(landmark.model.map { .model($0) } ?? .boxes(id: landmark.id, landmark.boxes), again: again)
    }

    /// The tile open is what every view works on, alone: entering the Roads
    /// view opens the road document holding it and frames it, or closes the
    /// document open when none holds it.
    func follow(_ mode: ViewMode) {
        if phase == .working, mode == .landmarks || mode == .preview { readCandidates() }
        if phase == .working, mode == .buildings {
            let tile = workspace.tile, paths = workspace.paths
            Task { @MainActor in
                await self.buildings.load(tile, paths: paths)
                self.readCandidates()
            }
        }
        if phase == .working, mode == .tiles || mode == .preview {
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
        candidates = LandmarkCandidates.list(workspace.paths, tile: tile)
    }

    /// The buildings picked in the Buildings view made a landmark candidate.
    func makeLandmark(named name: String) {
        guard let tile = workspace.tile, let projection = buildings.projection, !buildings.selected.isEmpty else { return }
        do {
            _ = try LandmarkCandidates.make(name: name, buildings: buildings.selected, tile: tile,
                                            projection: projection, paths: workspace.paths)
            buildings.picked = []
            readCandidates()
            // The files panel shows it.
            workspace.tilesRevision += 1
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
