import Foundation
import ImmersiveMap
import TileKit

/// The map a tile is chosen on: going to a place or a tile, the places
/// kept, picking and marking tiles, and the marked tiles' OSM fetched.
extension Session {
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

    /// The OSM of every marked tile cut from the data folder's extracts,
    /// one command a zoom, each extract read once for all of them.
    func fetchChosen() {
        let tiles = chosenToFetch
        guard !tiles.isEmpty, !jobs.isActive(.workspace) else { return }
        // The tiles no extract holds are named at the end, the rest taken.
        let zooms = Set(tiles.map(\.z)).sorted()
        run(zooms.map { z in ["fetch", "\(z)", "--tiles"] + tiles.filter { $0.z == z }.map { "\($0.x)/\($0.y)" } }, on: .workspace,
            title: "Fetch OSM for \(tiles.count) tile" + (tiles.count == 1 ? "" : "s"), goOn: true)
    }
}
