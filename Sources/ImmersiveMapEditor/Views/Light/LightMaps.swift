import Foundation
import ImageIO
import Observation
import TileKit

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
        /// False while the tile is built with its light left white.
        var baked: Bool
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
        return Map(image: image, px: whole.width, overhang: overhang, baked: stats["light_baked"] as? Bool ?? true,
                   settings: json("bake/settings.json"))
    }
}

/// The Light view's settings for a bake, kept between runs: TileKit's
/// Lighting.Settings as the bake command takes them.
@Observable
@MainActor
final class LightSettings {
    private static func value<T>(_ key: String, _ fallback: T) -> T { UserDefaults.standard.object(forKey: "light." + key) as? T ?? fallback }
    private static func keep(_ key: String, _ v: Any) { UserDefaults.standard.set(v, forKey: "light." + key) }

    /// Texels of the light map across one tile, as the build's 1024.
    var size: Int = value("size", 1024) { didSet { Self.keep("size", size) } }
    var samples: Int = value("samples", 256) { didSet { Self.keep("samples", samples) } }
    var bounces: Int = value("bounces", 3) { didSet { Self.keep("bounces", bounces) } }
    /// What light is gathered: the sky with its bounces, or ambient occlusion.
    var mode: String = value("mode", "sky") { didSet { Self.keep("mode", mode) } }
    var aoRadius: Double = value("aoRadius", 8.0) { didSet { Self.keep("aoRadius", aoRadius) } }
    var skyStrength: Double = value("skyStrength", 1.0) { didSet { Self.keep("skyStrength", skyStrength) } }
    /// A sun baked in, off by default (the engine casts the sun's shadows).
    var sun: Bool = value("sun", false) { didSet { Self.keep("sun", sun) } }
    var sunAzimuth: Double = value("sunAzimuth", 225.0) { didSet { Self.keep("sunAzimuth", sunAzimuth) } }
    var sunElevation: Double = value("sunElevation", 45.0) { didSet { Self.keep("sunElevation", sunElevation) } }
    var sunStrength: Double = value("sunStrength", 1.0) { didSet { Self.keep("sunStrength", sunStrength) } }
    /// The engine's shadow of the sun on a landmark previewed alone: how
    /// dark where a surface is fully in shadow (not baked: the engine's).
    var shadow: Double = value("shadow", 0.45) { didSet { Self.keep("shadow", shadow) } }
    /// The preview camera's lens on a landmark alone: its vertical field of
    /// view in degrees, the engine's 45 by default. Narrow flattens the
    /// building like a telephoto, wide makes what is near loom.
    var lens: Double = value("lens", 45) { didSet { Self.keep("lens", lens) } }
    /// Preview: the walls toned by their side against the palette's sun.
    var sided: Bool = value("sided", true) { didSet { Self.keep("sided", sided) } }
    /// Preview: the engine's sun shown at all (its shadow and the walls'
    /// tones by side); off, only the light map (the user, 2026-10-28: the
    /// engine has its own directed light, the editor is for the baked one).
    var engineSun: Bool = value("engineSun", true) { didSet { Self.keep("engineSun", engineSun) } }
    /// The shadow strength the preview shows: none without the engine's sun.
    var previewShadow: Double { engineSun ? shadow : 0 }
    var previewSided: Bool { engineSun && sided }

    /// These as TileKit's settings, for a bake in the app.
    var settings: Lighting.Settings {
        var s = Lighting.Settings()
        s.size = size
        s.samples = samples
        s.bounces = bounces
        s.mode = mode
        s.aoRadius = aoRadius
        s.skyStrength = skyStrength
        s.sun = sun
        s.sunAzimuth = sunAzimuth
        s.sunElevation = sunElevation
        s.sunStrength = sunStrength
        s.sidedTones = previewSided
        return s
    }

    /// The bake command's options for these settings.
    var arguments: [String] {
        var a = ["--size", "\(size)", "--samples", "\(samples)", "--bounces", "\(bounces)",
                 "--mode", mode, "--ao-radius", "\(aoRadius)", "--sky", "\(skyStrength)"]
        a += sun ? ["--sun", "\(sunAzimuth)", "\(sunElevation)", "\(sunStrength)"] : ["--no-sun"]
        return a
    }

    /// Everything the landmark preview's bake depends on: the arguments,
    /// and the engine's sun direction and the side tones, which the bake
    /// of a tile does not take.
    var previewKey: String { arguments.joined(separator: " ") + " \(sunAzimuth) \(sunElevation) \(previewSided)" }
}
