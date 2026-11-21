import Foundation
import TileKit

/// What a landmark's model, as found in its folder, was when last looked
/// at: its file and when it was written, and when the agent gave the
/// landmark up, if it did.
struct ModelStamp: Equatable {
    var url: URL?
    var written: Date?
    var skipped: Date?

    init(folder: URL) {
        url = TileLandmark.model(in: folder)
        written = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        skipped = LandmarkSkip.date(in: folder)
    }
}

/// The session's side of the landmarks' agent, which the user runs in a
/// terminal (the user, 2026-11-20): the folder set up and the prompt copied
/// (for a landmark, a tile or an area), and the models the agent
/// builds shown as they land.
extension Session {
    /// The landmark of the open tile with `id`.
    private func landmark(_ id: String?) -> TileLandmark? { candidates.first { $0.id == id } }

    /// The landmark's folder set up for the agent (`AgentSetup`) and its
    /// prompt put on the clipboard, at the detail set now.
    func copyPrompt(id: String?) {
        guard let landmark = landmark(id) else { return }
        let fine = AgentSettings.fine
        do {
            try AgentSetup.prepare(landmark.folder, fine: fine)
        } catch {
            problem = "Cannot set up \(landmark.name)'s folder for the agent: \(error.localizedDescription)"
            return
        }
        let monument = (try? LandmarkSource(landmark.folder.appendingPathComponent("landmark.json")))?.isMonument ?? false
        Platform.copy(LandmarkAgent.prompt(landmark.name, monument: monument, fine: fine))
    }

    /// The landmark's folder set up for the agent and the command that goes
    /// into it put on the clipboard.
    func copyChangeDirectory(id: String?) {
        guard let landmark = landmark(id) else { return }
        try? AgentSetup.prepare(landmark.folder, fine: AgentSettings.fine)
        Platform.copy(AgentSetup.changeDirectory(landmark.folder))
    }

    /// The open tile's `landmarks/` folder, where the session modelling all
    /// its landmarks is started.
    var tileLandmarksFolder: URL? {
        workspace.tile.map { LandmarkCandidates.folder(workspace.paths, $0) }
    }

    /// The tile's landmarks folder set up for one Claude Code or Codex session that
    /// models every landmark without a model, a subagent each
    /// (`AgentSetup.prepareTile`), and its prompt put on the clipboard.
    func copyTilePrompt() {
        guard let tile = workspace.tile, let folder = tileLandmarksFolder else { return }
        do {
            try AgentSetup.prepareTile(folder, fine: AgentSettings.fine)
        } catch {
            problem = "Cannot set up the tile's landmarks folder for the agent: \(error.localizedDescription)"
            return
        }
        Platform.copy(LandmarkAgent.tilePrompt(tile.name, count: candidates.filter { $0.model == nil && $0.skipped == nil }.count))
    }

    /// The tile's landmarks folder set up and the command that goes into it
    /// put on the clipboard.
    func copyTileChangeDirectory() {
        guard let folder = tileLandmarksFolder else { return }
        try? AgentSetup.prepareTile(folder, fine: AgentSettings.fine)
        Platform.copy(AgentSetup.changeDirectory(folder))
    }

    /// The tiles marked on the map (with the one picked), in rows from the
    /// north, each from the west: the area's automation goes through them so.
    var markedTiles: [TileKey] {
        chosen.union(candidate.map { [$0] } ?? []).sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    /// The data folder's `agent/` set up for one session that goes through
    /// the marked tiles (`AreaMCP`): its plan written, the tiles, which
    /// buildings become landmarks and how many, the parts of the build sheet
    /// (the tiles prepared before stay so, so none is given more landmarks).
    /// Returns the folder, nil when it could not be written.
    @discardableResult
    func prepareArea(kind: LandmarkKind, limit: Int) -> URL? {
        let folder = AreaPlan.folder(workspace.paths)
        let tiles = markedTiles.map(\.name)
        let before = (try? AreaPlan.read(folder))?.prepared ?? []
        let plan = AreaPlan(tiles: tiles, kind: kind.rawValue, limit: limit, parts: buildParts.sorted(),
                            prepared: before.filter(tiles.contains))
        do {
            try plan.write(folder)
            try AgentSetup.prepareArea(folder, fine: AgentSettings.fine)
            return folder
        } catch {
            problem = "Cannot set up the area's folder for the agent: \(error.localizedDescription)"
            return nil
        }
    }

    /// The area set up and the command that goes into its folder copied.
    func copyAreaFolderCommand(kind: LandmarkKind, limit: Int) {
        guard let folder = prepareArea(kind: kind, limit: limit) else { return }
        Platform.copy(AgentSetup.changeDirectory(folder))
    }

    /// The area set up and its prompt copied.
    func copyAreaPrompt(kind: LandmarkKind, limit: Int) {
        guard prepareArea(kind: kind, limit: limit) != nil else { return }
        Platform.copy(LandmarkAgent.areaPrompt(tiles: markedTiles.count))
    }

    /// Watches the models of the open tile's landmarks every two seconds: a
    /// model the agent built (or Forget removed) is shown at once, in the
    /// landmark open, the Preview, and green on the buildings' map. A look at a file's date, nothing
    /// read while nothing changed.
    func watchModels() {
        modelWatch?.cancel()
        modelWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.lookAtModels()
            }
        }
    }

    private func lookAtModels() {
        for landmark in candidates {
            let stamp = ModelStamp(folder: landmark.folder)
            guard let seen = seenModels[landmark.folder.path] else { seenModels[landmark.folder.path] = stamp; continue }
            guard stamp != seen else { continue }
            seenModels[landmark.folder.path] = stamp
            refreshModel(of: landmark.id)
            if landmark.id == pickedLandmark { showLandmark(again: true) }
            if landmark.id == workspace.previewSubject { showPreview() }
            workspace.tilesRevision += 1
        }
    }
}
