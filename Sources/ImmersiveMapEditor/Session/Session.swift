import AppKit
import Foundation
import ImmersiveMap
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
    /// Every job of the session: the builds of tiles, Claude on landmarks.
    let jobs = JobPool()
    /// The camera the views over the open tile share.
    let viewCamera = SharedCamera()
    let panels = PanelLayout()
    let lights = LightMaps()
    let lightSettings = LightSettings()
    /// The open tile's buildings of OSM, for the Buildings view.
    let buildings = OsmBuildings()
    /// Claude modelling landmarks: the pool's runs by landmark.
    let agent: LandmarkAgent
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
        agent = LandmarkAgent(pool: jobs)
        candidate = workspace.tile
        tiles = TileView(model: workspace)
        tiles?.sharedCamera = viewCamera
        camera.frame(workspace)
        palette.load(workspace.paths)
        agent.modelChanged = { [weak self] id in if self?.pickedLandmark == id { self?.showLandmark(again: true) } }
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
        guard !jobs.isActive(.tile(tile)) else { return }
        closeRoads()
        candidate = tile
        if workspace.tile != tile { viewCamera.forget() }
        workspace.tile = tile
        var steps: [[String]] = []
        if !workspace.fetched.contains(tile) { steps.append(["fetch", "\(tile.z)", "\(tile.x)", "\(tile.y)"]) }
        if workspace.document(holding: tile) == nil { steps.append(["seed", "\(tile.z)", "\(tile.x)", "\(tile.y)"]) }
        guard !steps.isEmpty else { return startWork() }
        phase = .preparing
        run(steps, on: .tile(tile), title: "Prepare \(tile.name)") { ok in
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
        guard let tile = workspace.tile, let landmark = candidates.first(where: { $0.id == pickedLandmark }) else { return }
        run([["landmark", landmark.folder.path]], on: .landmark(tile: tile, id: landmark.id), title: "Build \(landmark.name) from its recipe") { [weak self] _ in
            self?.readCandidates()
            self?.showLandmark(again: true)
        }
    }

    /// Whether a job on the landmark, Claude or a build from its recipe, is
    /// queued or going.
    func isBusy(landmark id: String) -> Bool {
        workspace.tile.map { jobs.isActive(.landmark(tile: $0, id: id)) } ?? false
    }

    /// A landmark deleted whole: its folder, with everything in it.
    func deleteLandmark(_ landmark: TileLandmark) {
        guard !agent.isActive(landmark.id) else { return }
        try? FileManager.default.removeItem(at: landmark.folder)
        if let tile = workspace.tile { try? Registry(workspace.paths).remove(landmark: landmark.id, z: tile.z, x: tile.x, y: tile.y) }
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

    /// Claude on the picked landmark: queued in the pool, which runs several
    /// landmarks at once.
    func modelLandmark(request: String? = nil) {
        modelLandmark(id: pickedLandmark, request: request)
    }

    /// Claude on a landmark of the tile by its id.
    func modelLandmark(id: String?, request: String? = nil) {
        guard let tile = workspace.tile, let landmark = candidates.first(where: { $0.id == id }) else { return }
        agent.start(tile: tile, id: landmark.id, folder: landmark.folder, name: landmark.name, request: request)
    }

    /// What the window is about now, for the console at its foot (the user,
    /// 2026-11-02: the job shown is the job of what is shown, no tabs): the
    /// landmark open in Buildings, or shown alone in Preview, then the tile
    /// open, or the one picked while choosing, with the data folder's own
    /// jobs (the archive) while choosing.
    var subjects: [JobSubject] {
        var out: [JobSubject] = []
        if phase == .working, let tile = workspace.tile {
            if workspace.viewMode == .buildings, let id = pickedLandmark { out.append(.landmark(tile: tile, id: id)) }
            if workspace.viewMode == .preview, workspace.previewSubject != "tile" { out.append(.landmark(tile: tile, id: workspace.previewSubject)) }
        }
        if let tile = shownTile { out.append(.tile(tile)) }
        if phase == .choosing || workspace.viewMode == .engine { out.append(.workspace) }
        return out
    }
    /// The job the console shows: the last job of what the window is about.
    var contextJob: (any Job)? { jobs.latest(of: subjects) }
    var console: Console { contextJob?.console ?? idle }
    var consoleTitle: String { contextJob?.title ?? "Console" }
    /// The console shown when nothing is about what the window shows.
    private let idle = Console()
    private var pickedRun: LandmarkRun? { pickedLandmark.flatMap { agent.run(of: $0) } }

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
        if workspace.previewSubject == "landmarks" {
            previewView?.show(.models(placedModels))
            return
        }
        guard let landmark = candidates.first(where: { $0.id == workspace.previewSubject }), let glb = landmark.model else {
            previewView?.show(nil)
            return
        }
        previewView?.show(.lit(glb, lightSettings.settings))
    }

    /// Every model of the tile's landmarks where the build places it: its
    /// origin in the tile's metres from its centre, as `Imported` places it.
    private var placedModels: [LandmarkView.Placed] {
        guard let key = workspace.tile, let tile = try? Tile(folder: workspace.paths.tileData(z: key.z, x: key.x, y: key.y)) else { return [] }
        return candidates.compactMap { landmark in
            guard let model = landmark.model, let centre = landmark.centre else { return nil }
            let p = tile.metres(lat: centre.lat, lon: centre.lon)
            return LandmarkView.Placed(url: model, origin: SIMD3(p.x, p.y, 0))
        }
    }

    /// The landmarks of the tile with a recipe, their models built again
    /// from it, one job of the tile: after a change of the style or of a
    /// recipe by hand (the user, 2026-11-02).
    var landmarksWithRecipes: Int { candidates.filter(\.hasRecipe).count }
    func rebuildLandmarks() {
        guard let tile = workspace.tile else { return }
        let steps = candidates.filter(\.hasRecipe).map { ["landmark", $0.folder.path] }
        guard !steps.isEmpty else { return }
        run(steps, on: .tile(tile), title: "Rebuild \(steps.count) landmarks of \(tile.name) from their recipes") { [weak self] _ in
            self?.readCandidates()
            self?.showLandmark(again: true)
            self?.showPreview()
        }
    }

    /// The tile's light baked again a moment after a modifier changes in
    /// Preview, as a landmark's is (the user, 2026-11-02: the modifiers
    /// seemed dead on the tile, whose light the pipeline bakes only when
    /// asked). A change while a bake runs bakes once more after it.
    private var bakeTask: Task<Void, Never>?
    private var bakeAgain = false
    func lightSettingsChanged() {
        guard phase == .working, workspace.viewMode == .preview, workspace.previewSubject == "tile",
              let tile = workspace.tile, workspace.built.contains(tile) else { return }
        bakeTask?.cancel()
        bakeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            if jobs.isActive(.tile(tile)) { bakeAgain = true } else { perform(.light) }
        }
    }

    func showLandmark(again: Bool = false) {
        if landmarkView == nil {
            landmarkView = LandmarkView.make()
            landmarkView?.wireframe = landmarkWireframe
            landmarkView?.camera = { [weak self] in self?.landmarkCamera = $0 }
            landmarkView?.status = { [weak self] in
                self?.landmarkStatus = $0
                // While Claude works on it, its console says what the view shows.
                if let run = self?.pickedRun, run.state.running { run.console.append("  view: \($0)") }
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
        if phase == .working, mode == .preview { readCandidates() }
        // The engine's map gets its first archive by itself.
        if phase == .working, mode == .engine, engineArchive == nil, can(.engine) { perform(.engine) }
        if phase == .working, mode == .buildings {
            let tile = workspace.tile, paths = workspace.paths
            Task { @MainActor in
                await self.buildings.load(tile, paths: paths)
                self.readCandidates()
            }
        }
        if phase == .working, mode == .preview {
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
        if let registry = try? Registry(workspace.paths) {
            for problem in registry.sync(workspace.paths) { console.append("registry: \(problem)") }
        }
    }

    /// The landmark an OSM building is already part of, in any tile.
    func landmark(holding osm: String) -> Registry.LandmarkRecord? {
        (try? Registry(workspace.paths))?.landmark(holding: osm)
    }

    /// The buildings picked in the Buildings view made a landmark candidate.
    /// Returns the id of the landmark made, nil when none was; the new
    /// landmark opens unless `open` is false.
    @discardableResult
    func makeLandmark(named name: String, leavingHeld: Bool = false, open: Bool = true) -> String? {
        guard let tile = workspace.tile, let projection = buildings.projection, !buildings.selected.isEmpty else { return nil }
        // One landmark a building, in any tile (the user, 2026-10-29): the
        // buildings a landmark holds are left out, or refuse the whole.
        var chosen: [OsmBuilding] = []
        for b in buildings.selected {
            if let holder = landmark(holding: b.id) {
                if leavingHeld { continue }
                problem = "\(b.id) is already part of the landmark \"\(holder.name)\" of tile \(holder.tile)."
                return nil
            }
            chosen.append(b)
        }
        guard !chosen.isEmpty else { return nil }
        do {
            let folder = try LandmarkCandidates.make(name: name, buildings: chosen, tile: tile,
                                                     projection: projection, paths: workspace.paths)
            buildings.picked = []
            readCandidates()
            // The files panel shows it, and the new landmark opens.
            workspace.tilesRevision += 1
            if open { pickedLandmark = folder.lastPathComponent }
            return folder.lastPathComponent
        } catch {
            problem = "Cannot make the landmark \(name): \(error.localizedDescription)"
            return nil
        }
    }

    /// The picked buildings made a landmark and Claude set on it at once,
    /// the view staying on the tile's buildings (the user, 2026-11-01: one
    /// button from the building to the model, without watching the run).
    func makeLandmarkAndModel(named name: String) {
        if let id = makeLandmark(named: name, leavingHeld: true, open: false) { modelLandmark(id: id) }
    }

    // MARK: The engine

    /// The data folder's engine/ folder: the model archives the Engine view
    /// reads, the latest shown. A new export is a new file, so the engine's
    /// disk cache of the old one is never taken for the new, and the older
    /// files go once the new one is written.
    var engineFolder: URL { workspace.paths.root.appendingPathComponent("engine") }
    var engineArchive: URL? {
        _ = engineRevision
        return ((try? FileManager.default.contentsOfDirectory(at: engineFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "pmtiles" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.last
    }
    private(set) var engineRevision = 0
    /// The engine's camera as it was left, kept while another view shows.
    var engineCamera: ImmersiveMapCameraPosition?
    /// Bumped to put the camera back over the tile.
    var engineJumps = 0
    /// Where the engine's camera starts: over the tile open, from the
    /// south, tilted, close enough for the models (the archive's zoom 14);
    /// while a tile is chosen, where the map looks.
    var engineStart: ImmersiveMapCameraPosition? {
        if phase == .choosing {
            let c = camera.lonLat
            return ImmersiveMapCameraPosition(latitudeDegrees: c.lat, longitudeDegrees: c.lon, zoom: camera.zoom, bearing: 0, pitch: 45)
        }
        guard let t = workspace.tile else { return nil }
        let n = pow(2, Double(t.z))
        let lon = (Double(t.x) + 0.5) / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * (Double(t.y) + 0.5) / n))) * 180 / .pi
        return ImmersiveMapCameraPosition(latitudeDegrees: lat, longitudeDegrees: lon, zoom: 16, bearing: 0, pitch: 50)
    }

    /// The engine's camera held to the neighbourhood of the tile open, one
    /// tile around it (the user, 2026-11-02: only this tile is worked on, no
    /// flying off); free while a tile is chosen, the whole archive in view.
    var engineBounds: ImmersiveMapSettings.CameraSettings.Bounds? {
        guard phase == .working, let t = workspace.tile else { return nil }
        let n = pow(2, Double(t.z))
        func lon(_ x: Int) -> Double { Double(x) / n * 360 - 180 }
        func lat(_ y: Int) -> Double { atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180 / .pi }
        return .init(southWest: GeoCoordinate(latitude: lat(t.y + 2), longitude: lon(t.x - 1)),
                     northEast: GeoCoordinate(latitude: lat(t.y - 1), longitude: lon(t.x + 2)),
                     pullZoomRange: 11...13)
    }

    /// Whether the map a tile is chosen on shows the engine's map with the
    /// whole archive instead of the tiles' grid (the user, 2026-11-02: the
    /// map as the engine will show it, every tile built). The camera is
    /// handed over both ways: the engine starts where the map looked, the
    /// map moves to where the engine was left.
    var mapEngine = false
    func showMapEngine(_ on: Bool) {
        guard on != mapEngine else { return }
        if on {
            engineCamera = nil
            // The engine's map gets its first archive by itself.
            if engineArchive == nil, can(.engine) { perform(.engine) }
        } else if let p = engineCamera {
            camera.set(lon: p.longitudeDegrees, lat: p.latitudeDegrees, zoom: p.zoom)
        }
        mapEngine = on
    }

    /// Every built tile into a new archive in engine/, the older ones gone
    /// after it, and the Engine view over it.
    private func updateEngineArchive() {
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)", locale: .init(identifier: "en_US_POSIX"), timeZone: .current, calendar: .init(identifier: .gregorian)))
        let folder = engineFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent("models-\(stamp).pmtiles")
        run([["archive", out.path]], on: .workspace, title: "Update the engine's archive") { [weak self] ok in
            guard let self else { return }
            if ok {
                for old in ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    where old.pathExtension == "pmtiles" && old.lastPathComponent != out.lastPathComponent {
                    try? FileManager.default.removeItem(at: old)
                }
            }
            self.engineRevision += 1
        }
    }

    // MARK: Building the working tile

    /// Whether `action` can run on the working tile now.
    func can(_ action: TileAction) -> Bool {
        // The archive is the data folder's, from the map or the Engine view.
        if action == .engine { return phase != .preparing && !workspace.built.isEmpty && !jobs.isActive(.workspace) }
        guard phase == .working, let tile = workspace.tile, !jobs.isActive(.tile(tile)) else { return false }
        switch action {
        case .roads: return true
        case .tile: return workspace.fetched.contains(tile)
        case .light: return workspace.built.contains(tile)
        case .engine: return false
        }
    }

    /// Runs a view's action on the working tile. Seeding over a road document
    /// asks first (`reseedAsked`): it holds hand edits.
    func perform(_ action: TileAction) {
        if action == .engine {
            if can(.engine) { updateEngineArchive() }
            return
        }
        guard let tile = workspace.tile, can(action) else { return }
        switch action {
        case .tile:
            // The parts are chosen first (the user, 2026-10-30: the choice
            // belongs to the button, in a sheet).
            buildAsked = true
        case .light:
            // A tile built before builds kept what a bake needs builds once first.
            let ready = FileManager.default.fileExists(atPath: workspace.build(tile).appendingPathComponent("bake/scene.bin").path)
            run((ready ? [] : [buildStep(tile)])
                + [["bake", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)"] + lightSettings.arguments], on: .tile(tile), title: "Bake \(tile.name)") { [weak self] _ in
                guard let self, self.bakeAgain else { return }
                self.bakeAgain = false
                self.lightSettingsChanged()
            }
        case .roads:
            if workspace.document(holding: tile) != nil { reseedAsked = true } else { seedRoads(force: false) }
        case .engine:
            break
        }
    }

    /// Seeds the tile open's road document, fetching its OSM first when it
    /// is missing. `force` writes over the hand edits of the one there.
    func seedRoads(force: Bool) {
        guard let tile = workspace.tile else { return }
        // The document open is closed first, so the seed is what it shows next.
        closeRoads()
        run((workspace.fetched.contains(tile) ? [] : [["fetch", "\(tile.z)", "\(tile.x)", "\(tile.y)"]])
            + [["seed", "\(tile.z)", "\(tile.x)", "\(tile.y)"] + (force ? ["--force"] : [])], on: .tile(tile), title: "Seed the roads of \(tile.name)") { _ in
            self.follow(self.workspace.viewMode)
        }
    }

    /// The pipeline's command building one tile, its models all, its light
    /// not baked (the Light view bakes it): fetching what is missing,
    /// seeding its roads when no document holds it.
    /// The parts a build holds (Build.allParts; the user, 2026-10-29: each
    /// chosen apart), kept between runs. A stored property, so the sheet
    /// follows a toggle: Observation does not track a computed one over
    /// UserDefaults (the user, 2026-11-01: the checkboxes would not take).
    static let partsKey = "build.parts"
    var buildParts: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Session.partsKey) ?? Array(Build.allParts)) {
        didSet { UserDefaults.standard.set(buildParts.sorted(), forKey: Self.partsKey) }
    }
    func toggle(part: String, on: Bool) {
        var parts = buildParts
        if on { parts.insert(part) } else { parts.remove(part) }
        buildParts = parts
    }

    /// Whether the build sheet is up, the parts to choose.
    var buildAsked = false

    /// Builds the working tile with the parts chosen, from the sheet.
    func buildTileNow() {
        guard let tile = workspace.tile else { return }
        buildAsked = false
        run([buildStep(tile)], on: .tile(tile), title: "Build \(tile.name)")
    }

    private func buildStep(_ tile: TileKey) -> [String] {
        ["build", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)", "--no-light", "--parts", buildParts.sorted().joined(separator: ",")]
    }

    /// Every built tile into the engine's model archive, where the user
    /// chooses (the user, 2026-10-29).
    func exportArchive() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "models.pmtiles"
        panel.allowedContentTypes = [.data]
        panel.canCreateDirectories = true
        panel.title = "Export the Model Archive"
        panel.message = "Every built tile, in the form the engine reads (a PMTiles archive of model tiles)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run([["archive", url.path]], on: .workspace, title: "Export the archive")
    }

    /// Queues pipeline commands on the workspace as one job of its subject,
    /// the road document open saved first; when it ends, the workspace is
    /// read again so every view shows the result.
    private func run(_ steps: [[String]], on subject: JobSubject, title: String, then: @escaping @MainActor (Bool) -> Void = { _ in }) {
        model?.saveIfNeeded()
        let workspace = self.workspace
        jobs.add(PipelineJob(subject: subject, title: title, root: workspace.root, steps: steps) { ok in
            workspace.scan()
            workspace.tilesRevision += 1
            then(ok)
        })
    }
}
