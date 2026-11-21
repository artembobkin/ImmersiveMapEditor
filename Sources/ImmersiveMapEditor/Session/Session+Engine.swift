import Foundation
import ImmersiveMap
import TileKit

/// The engine's map: its archive in engine/, its camera's start and
/// bounds over the tile open, and the map a tile is chosen on shown as
/// the tiles' grid or the engine's map.
extension Session {
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
}
