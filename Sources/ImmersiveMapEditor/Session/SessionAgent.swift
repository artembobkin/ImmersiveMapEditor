import Foundation
import TileKit

/// What a landmark's model, as found in its folder, was when last looked
/// at: its file and when it was written.
struct ModelStamp: Equatable {
    var url: URL?
    var written: Date?

    init(folder: URL) {
        url = TileLandmark.model(in: folder)
        written = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    }
}

/// The session's side of the landmarks' agent, which the user runs in a
/// terminal (the user, 2026-11-20): the references gathered by the editor,
/// the folder set up and the prompt copied, and the models the agent
/// builds shown as they land.
extension Session {
    /// The landmark of the open tile with `id`.
    private func landmark(_ id: String?) -> TileLandmark? { candidates.first { $0.id == id } }

    /// The landmark's references gathered, a job of the pool.
    func gatherReferences(id: String?) {
        guard let tile = workspace.tile, let landmark = landmark(id) else { return }
        jobs.add(ReferencesJob(tile: tile, id: landmark.id, name: landmark.name, folder: landmark.folder) { [weak self] _ in
            self?.workspace.tilesRevision += 1
        })
    }

    /// The references of the tile's landmarks without a model, or of all of
    /// them, gathered one landmark after another.
    func gatherReferences(onlyWithoutModel: Bool) {
        for landmark in candidates where !isBusy(landmark: landmark.id) && (!onlyWithoutModel || landmark.model == nil) {
            gatherReferences(id: landmark.id)
        }
    }

    /// The picked buildings made a landmark and its references gathered at
    /// once, the view staying on the tile's buildings.
    func makeLandmarkAndGather(named name: String) {
        if let id = makeLandmark(named: name, leavingHeld: true) { gatherReferences(id: id) }
    }

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

    /// Watches the models of the landmarks shown, the one open and the one
    /// the Preview shows alone, every two seconds: a model the agent built
    /// (or Forget removed) is shown at once. A look at a file's date, nothing
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
        let shown = Set([pickedLandmark, workspace.previewSubject].compactMap { $0 })
        for landmark in candidates where shown.contains(landmark.id) {
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
