import Foundation
import ImmersiveMap
import TileKit

/// The tile's landmarks: listed and kept in the registry, made of the
/// picked buildings or many at once (`LandmarkMaker`), built from their
/// recipes, deleted, their models looked at again.
extension Session {
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

    /// Whether a job on the landmark, a build from its recipe, is
    /// queued or going.
    func isBusy(landmark id: String) -> Bool {
        workspace.tile.map { jobs.isActive(.landmark(tile: $0, id: id)) } ?? false
    }

    /// A landmark deleted whole: its folder, with everything in it.
    func deleteLandmark(_ landmark: TileLandmark) {
        guard !isBusy(landmark: landmark.id) else { return }
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
    /// each model is (`TileLandmark.model`), and the agent or Forget
    /// may have written or deleted it since (the user, 2026-11-03: the view
    /// read a model.glb that was gone).
    func refreshModel(of id: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        let found = TileLandmark.model(in: candidates[i].folder)
        if found != candidates[i].model { candidates[i].model = found }
        let skipped = found == nil ? LandmarkSkip.reason(in: candidates[i].folder) : nil
        if skipped != candidates[i].skipped { candidates[i].skipped = skipped }
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

    /// The buildings of the tile `kind` takes (`LandmarkKind`) that are no
    /// landmark yet, with their centre inside the tile, the largest first
    /// (the user, 2026-11-04: one button for the tile's notable; 2026-11-21:
    /// more ways to make many landmarks at once than the notable alone).
    func toMake(_ kind: LandmarkKind) -> [OsmBuilding] { maker?.candidates(kind) ?? [] }

    /// The rules of making landmarks of the open tile's buildings, as read.
    private var maker: LandmarkMaker? {
        guard let tile = workspace.tile, let projection = buildings.projection else { return nil }
        let buildings = self.buildings
        return LandmarkMaker(paths: workspace.paths, tile: tile, projection: projection, buildings: buildings.all,
                             held: { [holders] in holders[$0] != nil }, nearestStreet: { buildings.nearestStreet(to: $0) })
    }

    /// The name of a landmark made of `building` (and the parts in it): its
    /// name, else its address, else the nearest named street with the
    /// building's number of the tile ("Jalan Veteran 3", the user,
    /// 2026-11-04: in Jakarta few buildings have a name or an address,
    /// and "Landmark 1" told nothing), else "Landmark N".
    func nameFor(_ building: OsmBuilding) -> String {
        maker?.name(for: building, among: candidates) ?? building.name ?? building.address ?? "Landmark"
    }

    /// Each of the `limit` largest buildings `kind` takes made a landmark,
    /// whole with the parts standing in it, named by its name or address,
    /// to be looked over in the list and on the map before any modelling;
    /// the view stays on the tile's buildings. Returns how many were made.
    @discardableResult
    func makeLandmarks(_ kind: LandmarkKind, limit: Int) -> Int {
        guard let maker else { return 0 }
        let made = maker.make(kind, limit: limit)
        readCandidates()
        workspace.tilesRevision += 1
        return made.count
    }
}
