import Foundation
import ImmersiveMap
import TileKit

/// The tile open: opening it (its OSM and roads prepared first), going
/// back to the map, the road document opened, and what the window is
/// about for the console at its foot.
extension Session {
    // MARK: The tile open

    /// The tile the files and the map's panel show: the one open, or the one
    /// picked while choosing.
    var shownTile: TileKey? { phase == .choosing ? candidate : workspace.tile }

    /// Opens a tile to work on: its OSM fetched and its roads seeded first
    /// when they are missing, then its views.

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
}
