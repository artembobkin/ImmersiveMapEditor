import Foundation
import ImmersiveMap
import TileKit

/// The build of the working tile: what a view can do on it, the parts of
/// the build sheet, a tile built, its road document seeded, and the
/// pipeline's commands queued as a job.
extension Session {
    // MARK: Building the working tile

    /// Whether `action` can run on the working tile now.
    func can(_ action: TileAction) -> Bool {
        // The archive is the data folder's, from the map or the Engine view.
        if action == .engine {
            let openTile = workspace.tile.map { workspace.fetched.contains($0) && !jobs.isActive(.tile($0)) } ?? false
            return phase != .preparing && (!workspace.built.isEmpty || openTile) && !jobs.isActive(.workspace)
        }
        guard phase == .working, let tile = workspace.tile, !jobs.isActive(.tile(tile)) else { return false }
        switch action {
        case .roads: return true
        case .tile: return workspace.fetched.contains(tile)
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

    func toggle(part: String, on: Bool) {
        var parts = buildParts
        if on { parts.insert(part) } else { parts.remove(part) }
        buildParts = parts
    }

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

    /// The pipeline's command building one tile, its models all: fetching
    /// what is missing,
    /// seeding its roads when no document holds it.

    func buildStep(_ tile: TileKey) -> [String] {
        ["build", "\(tile.z)", "--tiles", "\(tile.x)/\(tile.y)", "--parts", buildParts.subtracting(Features.roads ? [] : ["roads"]).sorted().joined(separator: ",")]
            + (Features.roads ? [] : ["--no-roads"])
    }

    /// Queues pipeline commands on the workspace as one job of its subject,
    /// the road document open saved first; when it ends, the workspace is
    /// read again so every view shows the result.
    func run(_ steps: [[String]], on subject: JobSubject, title: String, goOn: Bool = false,
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
