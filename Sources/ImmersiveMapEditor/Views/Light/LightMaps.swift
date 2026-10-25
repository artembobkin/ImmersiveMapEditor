import Foundation
import ImageIO
import Observation

/// The light maps of built tiles, as the Light view shows them: each cut to
/// its own tile (a light map reaches over the edge by the tile's overhang),
/// with what its bake was. Read again when the tiles' builds change.
@Observable
@MainActor
final class LightMaps {
    struct Map {
        var image: CGImage
        /// The light map's whole size in texels, and how far it reaches over
        /// the tile's edge.
        var px: Int
        var overhang: Double
        /// The bake's settings, when the tile keeps them (`bake/settings.json`).
        var settings: [String: Any]
    }

    private(set) var maps: [TileKey: Map] = [:]
    @ObservationIgnored private var revision = -1

    /// Reads the light maps of `tiles` from the workspace when its builds
    /// changed since the last read (its `tilesRevision`).
    func load(_ tiles: [TileKey], from workspace: Workspace) {
        let wanted = Set(tiles)
        guard revision != workspace.tilesRevision || !wanted.isSubset(of: Set(maps.keys)) else { return }
        revision = workspace.tilesRevision
        var next: [TileKey: Map] = [:]
        for t in tiles where workspace.built.contains(t) {
            if let map = Self.read(workspace.build(t)) { next[t] = map }
        }
        maps = next
    }

    private static func read(_ folder: URL) -> Map? {
        func json(_ name: String) -> [String: Any] {
            (try? Data(contentsOf: folder.appendingPathComponent(name)))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }
        let stats = json("stats.json"), metadata = json("metadata.json")
        guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent("lightmap.png") as CFURL, nil),
              let whole = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let size = metadata["size_m"] as? Double else { return nil }
        let overhang = stats["overhang_m"] as? Double ?? 0
        // The map is a square around the tile's centre, row 0 on the north,
        // half a tile plus the overhang on every side.
        let px = Double(whole.width)
        let side = px * size / (size + 2 * overhang)
        let crop = CGRect(x: (px - side) / 2, y: (px - side) / 2, width: side, height: side).integral
        guard let image = whole.cropping(to: crop) else { return nil }
        return Map(image: image, px: whole.width, overhang: overhang, settings: json("bake/settings.json"))
    }
}

/// The Light view's settings for a bake, kept between runs.
@Observable
@MainActor
final class LightSettings {
    /// Texels of the light map across one tile, as the build's 1024.
    var size = UserDefaults.standard.object(forKey: "light.size") as? Int ?? 1024 {
        didSet { UserDefaults.standard.set(size, forKey: "light.size") }
    }
    var samples = UserDefaults.standard.object(forKey: "light.samples") as? Int ?? 256 {
        didSet { UserDefaults.standard.set(samples, forKey: "light.samples") }
    }
    var bounces = UserDefaults.standard.object(forKey: "light.bounces") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(bounces, forKey: "light.bounces") }
    }
}
