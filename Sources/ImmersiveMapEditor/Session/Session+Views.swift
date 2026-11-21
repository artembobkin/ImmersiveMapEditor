import Foundation
import ImmersiveMap
import TileKit

/// The views over the tile open: the Preview's landmarks under its
/// light, a landmark's own view, each view followed as it is shown, the
/// road document closed, the imagery's date.
extension Session {
    /// The Preview's landmark, or all of them, under the preview's light.
    func showPreview() {
        guard workspace.previewSubject != "tile" else { return }
        if previewView == nil {
            previewView = LandmarkView.make()
            previewView?.status = { [weak self] in self?.previewStatus = $0 }
            previewView?.camera = { [weak self] in self?.previewCamera = $0 }
            previewView?.labels = { [weak self] in self?.previewLabels = $0 }
        }
        previewView?.lens = preview.lens
        if workspace.previewSubject == "landmarks" {
            previewView?.show(.models(placedModels))
            return
        }
        guard let landmark = candidates.first(where: { $0.id == workspace.previewSubject }), let glb = landmark.model else {
            previewView?.show(nil)
            return
        }
        previewView?.show(.lit(glb))
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

    func showLandmark(again: Bool = false) {
        if landmarkView == nil {
            landmarkView = LandmarkView.make()
            landmarkView?.wireframe = landmarkWireframe
            landmarkView?.camera = { [weak self] in self?.landmarkCamera = $0 }
            landmarkView?.status = { [weak self] in self?.landmarkStatus = $0 }
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
}
