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
///
/// The session is one class spread over files by responsibility
/// (`Session+Map`, `+Tile`, `+Views`, `+Landmarks`, `+Engine`, `+Archive`,
/// `+Build`, and `SessionAgent`), its stored state all here, as Swift
/// asks. What those files set is internal for that alone: nothing outside
/// them sets the phase, the views or the landmarks.
@Observable
@MainActor
final class Session {
    enum Phase { case choosing, preparing, working }

    private(set) var workspace: Workspace
    var phase = Phase.choosing
    /// The tile picked on the map while choosing: the one opened next. It
    /// starts as the tile open last.
    var candidate: TileKey?
    /// The tiles marked on the map with shift-clicks, to fetch at once
    /// (the user, 2026-11-04: one tile at a time was no way to get data).
    var chosen: Set<TileKey> = []
    let camera = MapCamera()
    /// The places kept to come back to on the map (`Places`).
    let places = Places()

    let raster = RasterTiles()
    /// Every job of the session: the builds of tiles, the landmarks' references gathered.
    let jobs = JobPool()
    /// The camera the views over the open tile share.
    let viewCamera = SharedCamera()
    let panels = PanelLayout()
    let preview = PreviewSettings()
    /// The open tile's buildings of OSM, for the Buildings view.
    let buildings = OsmBuildings()
    /// The palette's colours set over the defaults, in the Style view.
    let palette = PaletteEdits()
    /// A picture of the files sidebar the pointer rests on: shown large
    /// over the main area, so a reference is seen without opening it.
    var hoveredPicture: URL?
    /// The open tile's landmarks (its landmarks/ folder), the one picked in
    /// the Landmarks view, and the OSM elements they are made of.
    var candidates: [TileLandmark] = [] {
        didSet {
            candidateBuildings = Set(candidates.flatMap(\.buildings))
            modelledBuildings = Set(candidates.filter { $0.model != nil }.flatMap(\.buildings))
            skippedBuildings = Set(candidates.filter { $0.skipped != nil }.flatMap(\.buildings))
        }
    }
    var pickedLandmark: String?
    /// The Landmarks view's wireframe over the shading.
    var landmarkWireframe = false { didSet { landmarkView?.wireframe = landmarkWireframe } }
    /// The OSM ids of the open tile's landmarks' buildings, kept as a set:
    /// the Buildings view asks for every building it draws.
    private(set) var candidateBuildings: Set<String> = []
    /// The OSM ids of the buildings of the open tile's landmarks that have
    /// a 3D model, drawn apart from those still waiting for one (the user,
    /// 2026-11-20).
    private(set) var modelledBuildings: Set<String> = []
    /// The OSM ids of the buildings of the landmarks the agent gave up on for
    /// want of references, drawn red: tried, and not modelled (the user,
    /// 2026-11-21).
    private(set) var skippedBuildings: Set<String> = []
    /// The data folder's registry, open once (opening it ran its schema
    /// each time, and the editor opened it for every building it asked
    /// about; the user, 2026-11-03), and the landmark holding each OSM
    /// building, every tile's, in memory from it: `landmark(holding:)` is
    /// a lookup. Refreshed by `syncRegistry`.
    var registry: Registry?
    var holders: [String: Registry.LandmarkRecord] = [:]
    var landmarkView: LandmarkView?
    /// The models of the landmarks shown, by folder, as last seen on disk: the
    /// agent the user runs in a terminal writes them, and the editor shows
    /// each as it lands (`watchModels`).
    @ObservationIgnored var seenModels: [String: ModelStamp] = [:]
    @ObservationIgnored var modelWatch: Task<Void, Never>?
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
    var previewView: LandmarkView?
    var previewStatus = ""
    private(set) var tiles: TileView?
    var model: RoadEditor?
    var roads: RoadsView?
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
        places.load(workspace.paths)
        syncRegistry()
        watchModels()
    }

    /// The editor on its way out: the road document saved, every job
    /// stopped and its process ended (the user, 2026-11-03: the runs went on
    /// after a restart, working for no one).
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

    /// A landmark to open once the tile is, from a list on the map
    /// on the map (the user, 2026-11-04).
    var pendingLandmark: String?
    /// The console shown when nothing is about what the window shows.
    let idle = Console()
    var engineRevision = 0
    /// The engine's camera as it was left, kept while another view shows.
    var engineCamera: ImmersiveMapCameraPosition?
    /// Bumped to put the camera back over the tile.
    var engineJumps = 0
    /// What the window shows while a tile is chosen: the tiles' map, the
    /// engine's map, or the palettes (the user, 2026-11-05: the palettes are
    /// edited here, at the level of every tile, and a tile only picks one).
    enum Choosing: String, CaseIterable, Identifiable {
        case tiles = "Tiles", engine = "Engine", style = "Palettes"
        var id: String { rawValue }
    }
    var choosing: Choosing = .tiles
    /// The parts a build holds (Build.allParts; the user, 2026-10-29: each
    /// chosen apart), kept between runs. A stored property, so the sheet
    /// follows a toggle: Observation does not track a computed one over
    /// UserDefaults (the user, 2026-11-01: the checkboxes would not take).
    static let partsKey = "build.parts"
    var buildParts: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Session.partsKey) ?? Array(Build.allParts)) {
        didSet { UserDefaults.standard.set(buildParts.sorted(), forKey: Self.partsKey) }
    }
    /// Whether the build sheet is up, the parts to choose.
    var buildAsked = false
}
