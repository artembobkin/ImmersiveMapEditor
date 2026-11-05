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
    /// The tiles marked on the map with shift-clicks, to fetch at once
    /// (the user, 2026-11-04: one tile at a time was no way to get data).
    var chosen: Set<TileKey> = []
    let camera = MapCamera()
    /// The places kept to come back to on the map (`Places`).
    let places = Places()

    /// The map moved to what was typed, a tile or a point, which is picked;
    /// false when the text means neither.
    @discardableResult
    func goTo(_ text: String) -> Bool {
        guard let destination = Places.destination(text) else { return false }
        switch destination {
        case .tile(let tile):
            let n = pow(2, Double(tile.z))
            let lon = (Double(tile.x) + 0.5) / n * 360 - 180
            let lat = atan(sinh(.pi * (1 - 2 * (Double(tile.y) + 0.5) / n))) * 180 / .pi
            camera.set(lon: lon, lat: lat, zoom: 15.6)
            pick(tile.z == Workspace.zoom ? tile : tileAt(lat: lat, lon: lon), adding: false)
        case .point(let lat, let lon):
            camera.set(lon: lon, lat: lat, zoom: 15.6)
            pick(tileAt(lat: lat, lon: lon), adding: false)
        }
        return true
    }

    /// The map moved to a kept place.
    func jump(to place: Place) {
        camera.set(lon: place.longitude, lat: place.latitude, zoom: place.zoom)
        pick(tileAt(lat: place.latitude, lon: place.longitude), adding: false)
    }

    /// Where the map looks now, kept under a name.
    func savePlace(named name: String) {
        let (lon, lat) = camera.lonLat
        places.add(Place(name: name, latitude: lat, longitude: lon, zoom: camera.zoom))
    }

    /// The z15 tile a point lies in.
    func tileAt(lat: Double, lon: Double) -> TileKey {
        let n = pow(2, Double(Workspace.zoom)), phi = lat * .pi / 180
        let x = Int(((lon + 180) / 360 * n).rounded(.down))
        let y = Int(((1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * n).rounded(.down))
        return TileKey(z: Workspace.zoom, x: x, y: y)
    }

    /// A tile clicked on the map: picked alone, or, with shift, marked with
    /// the others (and unmarked when it was).
    func pick(_ tile: TileKey, adding: Bool) {
        if adding {
            if chosen.contains(tile) { chosen.remove(tile) } else { chosen.insert(tile) }
            if chosen.isEmpty { candidate = nil } else { candidate = tile }
        } else {
            chosen = []
            candidate = tile
        }
    }

    /// The tiles marked (with the one picked) whose OSM is not on disk.
    var chosenToFetch: [TileKey] {
        let all = chosen.union(candidate.map { [$0] } ?? [])
        return all.filter { !workspace.fetched.contains($0) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    /// The OSM of every marked tile fetched, one after another in one job
    /// of the data folder, the console counting them.
    func fetchChosen() {
        let tiles = chosenToFetch
        guard !tiles.isEmpty, !jobs.isActive(.workspace) else { return }
        // On past a tile Overpass refuses, the rest fetched and the failures told at the end.
        run(tiles.map { ["fetch", "\($0.z)", "\($0.x)", "\($0.y)"] }, on: .workspace,
            title: "Fetch OSM for \(tiles.count) tile" + (tiles.count == 1 ? "" : "s"), goOn: true)
    }
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
    private(set) var candidates: [TileLandmark] = [] {
        didSet { candidateBuildings = Set(candidates.flatMap(\.buildings)) }
    }
    var pickedLandmark: String?
    /// The Landmarks view's wireframe over the shading.
    var landmarkWireframe = false { didSet { landmarkView?.wireframe = landmarkWireframe } }
    /// The OSM ids of the open tile's landmarks' buildings, kept as a set:
    /// the Buildings view asks for every building it draws.
    private(set) var candidateBuildings: Set<String> = []
    /// The data folder's registry, open once (opening it ran its schema
    /// each time, and the editor opened it for every building it asked
    /// about; the user, 2026-11-03), and the landmark holding each OSM
    /// building, every tile's, in memory from it: `landmark(holding:)` is
    /// a lookup. Refreshed by `syncRegistry`.
    private var registry: Registry?
    private var holders: [String: Registry.LandmarkRecord] = [:]
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
        places.load(workspace.paths)
        agent.modelChanged = { [weak self] id in
            self?.refreshModel(of: id)
            if self?.pickedLandmark == id { self?.showLandmark(again: true) }
        }
        // What a crashed or force-quit editor left running on this folder.
        LandmarkRun.killOrphans(in: root)
        syncRegistry()
    }

    /// The editor on its way out: the road document saved, every job
    /// stopped and its process ended (the user, 2026-11-03: Claude's runs
    /// went on after a restart, working for no one).
    func quit() {
        model?.saveIfNeeded()
        jobs.quit()
    }

    /// Another data folder instead of the current one, back to choosing a
    /// tile in it.
    func open(workspace root: URL) {
        model?.saveIfNeeded()
        model = nil
        roads = nil
        workspace = Workspace(root: root)
        palette.load(workspace.paths)
        places.load(workspace.paths)
        candidate = workspace.tile
        phase = .choosing
        registry = nil
        holders = [:]
        syncRegistry()
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
    /// A landmark to open once the tile is, from the list of Claude's runs
    /// on the map (the user, 2026-11-04).
    private var pendingLandmark: String?

    func open(tile: TileKey, landmark: String? = nil) {
        guard !jobs.isActive(.tile(tile)) else { return }
        closeRoads()
        candidate = tile
        pendingLandmark = landmark
        if landmark != nil { workspace.viewMode = .buildings }
        if workspace.tile != tile {
            viewCamera.forget()
            // Cleared now, not when its reading starts: the Buildings view
            // comes first and would frame the last tile's buildings.
            buildings.clear()
        }
        workspace.tile = tile
        var steps: [[String]] = []
        if !workspace.fetched.contains(tile) { steps.append(["fetch", "\(tile.z)", "\(tile.x)", "\(tile.y)"]) }
        if Features.roads, workspace.document(holding: tile) == nil { steps.append(["seed", "\(tile.z)", "\(tile.x)", "\(tile.y)"]) }
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
        palette.show(tile: nil)
        candidate = workspace.tile
        phase = .choosing
    }

    private func startWork() {
        phase = .working
        if !ViewMode.shown.contains(workspace.viewMode) { workspace.viewMode = .buildings }
        if let t = workspace.tile { palette.show(tile: (t.z, t.x, t.y)) }
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
        if let tile = workspace.tile { try? registry?.remove(landmark: landmark.id, z: tile.z, x: tile.x, y: tile.y) }
        if pickedLandmark == landmark.id { pickedLandmark = nil }
        readCandidates()
        workspace.tilesRevision += 1
        showLandmark(again: true)
    }

    /// The picked landmark's folder changed by hand (its work forgotten):
    /// shown again, the files listed again.
    func landmarkWorkChanged() {
        workspace.tilesRevision += 1
        if let id = pickedLandmark { refreshModel(of: id) }
        showLandmark(again: true)
    }

    /// A landmark's model found again in its folder: the list keeps where
    /// each model is (`TileLandmark.model`), and Claude's run or Forget
    /// may have written or deleted it since (the user, 2026-11-03: the view
    /// read a model.glb that was gone).
    func refreshModel(of id: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        let found = TileLandmark.model(in: candidates[i].folder)
        if found != candidates[i].model { candidates[i].model = found }
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
                if let id = self.pendingLandmark, self.candidates.contains(where: { $0.id == id }) {
                    self.pendingLandmark = nil
                    self.pickedLandmark = id
                }
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
        syncRegistry()
    }

    /// The registry brought up to date with the landmark folders (only
    /// what changed is written) and the holders' index read from it again.
    func syncRegistry() {
        if registry == nil { registry = try? Registry(workspace.paths) }
        guard let registry else { return }
        for problem in registry.sync(workspace.paths) { console.append("registry: \(problem)") }
        var index: [String: Registry.LandmarkRecord] = [:]
        for l in registry.all() { for osm in l.buildings { index[osm] = l } }
        holders = index
    }

    /// The landmark an OSM building is already part of, in any tile.
    func landmark(holding osm: String) -> Registry.LandmarkRecord? { holders[osm] }

    /// The buildings picked in the Buildings view made a landmark candidate.
    /// Returns the id of the landmark made, nil when none was; the new
    /// landmark opens unless `open` is false.
    @discardableResult
    func makeLandmark(named name: String, leavingHeld: Bool = false) -> String? {
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
            // The files panel and the list show it; the view stays on the
            // tile's buildings, the landmark opened from the list when wanted
            // (the user, 2026-11-04: making one is not opening it).
            workspace.tilesRevision += 1
            return folder.lastPathComponent
        } catch {
            problem = "Cannot make the landmark \(name): \(error.localizedDescription)"
            return nil
        }
    }

    /// The tile's notable buildings (an article, a heritage or historic
    /// tag, a kind people know by name) not yet landmarks, with their
    /// centre inside the tile, the largest first: what Model the Notable
    /// takes (the user, 2026-11-04: one button for the tile's best).
    var notableToModel: [OsmBuilding] {
        guard let (lo, hi) = buildings.square else { return [] }
        return buildings.all.filter { b in
            !b.isPart && b.note == .notable && landmark(holding: b.id) == nil
                && (lo.x...hi.x).contains(b.centroid.x) && (lo.y...hi.y).contains(b.centroid.y)
        }.sorted { $0.area > $1.area }
    }

    /// The name of a landmark made of `building` (and the parts in it): its
    /// name, else its address, else the nearest named street with the
    /// building's number of the tile ("Jalan Veteran 3", the user,
    /// 2026-11-04: in Jakarta few buildings have a name or an address,
    /// and "Landmark 1" told nothing), else "Landmark N".
    func nameFor(_ building: OsmBuilding) -> String {
        if let name = building.name ?? building.address { return name }
        let number = LandmarkCandidates.nextName(among: candidates).dropFirst("Landmark ".count)
        if let street = buildings.nearestStreet(to: building.centroid) { return "\(street) \(number)" }
        return "Landmark \(number)"
    }

    /// Each of the `limit` largest notable buildings made a landmark, whole
    /// with the parts standing in it, named by its name or address, to be
    /// looked over in the list and on the map before any modelling; the
    /// view stays on the tile's buildings. Returns how many were made.
    @discardableResult
    func makeNotableLandmarks(limit: Int) -> Int {
        guard let tile = workspace.tile, let projection = buildings.projection else { return 0 }
        var made = 0
        for b in notableToModel.prefix(limit) {
            let parts = buildings.all.filter { $0.isPart && landmark(holding: $0.id) == nil && b.contains($0.middle) }
            let name = nameFor(b)
            guard (try? LandmarkCandidates.make(name: name, buildings: [b] + parts, tile: tile,
                                               projection: projection, paths: workspace.paths)) != nil else { continue }
            readCandidates()
            made += 1
        }
        workspace.tilesRevision += 1
        return made
    }

    /// The tile's landmarks without a model, or every one of them again,
    /// queued on Claude (the user, 2026-11-04: a choice between the ones
    /// not modelled yet and all of them anew). The ones Claude is on stay
    /// as they are.
    func modelLandmarks(onlyWithoutModel: Bool) {
        for landmark in candidates where !agent.isActive(landmark.id) && (!onlyWithoutModel || landmark.model == nil) {
            modelLandmark(id: landmark.id)
        }
    }

    /// The picked buildings made a landmark and Claude set on it at once,
    /// the view staying on the tile's buildings (the user, 2026-11-01: one
    /// button from the building to the model, without watching the run).
    func makeLandmarkAndModel(named name: String) {
        if let id = makeLandmark(named: name, leavingHeld: true) { modelLandmark(id: id) }
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
    /// What the window shows while a tile is chosen: the tiles' map, the
    /// engine's map, or the palettes (the user, 2026-11-05: the palettes are
    /// edited here, at the level of every tile, and a tile only picks one).
    enum Choosing: String, CaseIterable, Identifiable {
        case tiles = "Tiles", engine = "Engine", style = "Palettes"
        var id: String { rawValue }
    }
    var choosing: Choosing = .tiles
    var mapEngine: Bool { choosing == .engine }
    func show(choosing view: Choosing) {
        guard view != choosing else { return }
        if view == .engine {
            engineCamera = nil
            // The engine's map gets its first archive by itself.
            if engineArchive == nil, can(.engine) { perform(.engine) }
        } else if choosing == .engine, let p = engineCamera {
            camera.set(lon: p.longitudeDegrees, lat: p.latitudeDegrees, zoom: p.zoom)
        }
        choosing = view
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

    /// The tile a build is for: the one open, or the one picked on the map
    /// (the user, 2026-11-04: a tile built from the map too, no need to
    /// open it).
    var buildTarget: TileKey? { phase == .working ? workspace.tile : candidate }

    /// Whether the build sheet can be asked for the target: its OSM there,
    /// no job on it.
    var canBuildTarget: Bool {
        guard phase != .preparing, let tile = buildTarget else { return false }
        return workspace.fetched.contains(tile) && !jobs.isActive(.tile(tile))
    }

    /// Builds the target tile with the parts chosen, from the sheet.
    func buildTileNow() {
        guard let tile = buildTarget else { return }
        buildAsked = false
        run([buildStep(tile)], on: .tile(tile), title: "Build \(tile.name)")
    }

    private func buildStep(_ tile: TileKey) -> [String] {
        ["build", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)", "--no-light", "--parts", buildParts.subtracting(Features.roads ? [] : ["roads"]).sorted().joined(separator: ",")]
            + (Features.roads ? [] : ["--no-roads"])
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
    private func run(_ steps: [[String]], on subject: JobSubject, title: String, goOn: Bool = false,
                     then: @escaping @MainActor (Bool) -> Void = { _ in }) {
        model?.saveIfNeeded()
        let workspace = self.workspace
        jobs.add(PipelineJob(subject: subject, title: title, root: workspace.root, steps: steps, goOn: goOn) { ok in
            workspace.scan()
            workspace.tilesRevision += 1
            then(ok)
        })
    }
}
