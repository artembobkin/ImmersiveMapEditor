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
    /// The light's modifiers (Lighting.Modifier), the stack the preview
    /// shows and the bake takes, kept as JSON. A store from before the
    /// stack is read through the older keys once.
    var modifiers: [Lighting.Modifier] = loadModifiers() {
        didSet {
            if let data = try? JSONSerialization.data(withJSONObject: modifiers.map { $0.json() }), let text = String(data: data, encoding: .utf8) {
                Self.keep("modifiers", text)
            }
        }
    }
    /// The engine's shadow of the sun on a landmark previewed alone: how
    /// dark where a surface is fully in shadow (not baked: the engine's).
    var shadow: Double = value("shadow", 0.45) { didSet { Self.keep("shadow", shadow) } }
    /// The preview camera's lens on a landmark alone: its vertical field of
    /// view in degrees, the engine's 45 by default. Narrow flattens the
    /// building like a telephoto, wide makes what is near loom.
    var lens: Double = value("lens", 45) { didSet { Self.keep("lens", lens) } }
    /// Preview: the engine's shadow shown at all; off, only the light baked
    /// (the user, 2026-10-28: the engine has its own directed light).
    var engineSun: Bool = value("engineSun", false) { didSet { Self.keep("engineSun", engineSun) } }
    /// The shadow strength the preview shows: none without the engine's sun.
    var previewShadow: Double { engineSun ? shadow : 0 }
    /// The preview's sun, for the engine's shadow: the sun modifier's
    /// bearing and height, baked or not.
    var sunAzimuth: Double {
        get { settings.sunAzimuth }
        set { var s = settings; s.sunAzimuth = newValue; modifiers = s.modifiers }
    }
    var sunElevation: Double {
        get { settings.sunElevation }
        set { var s = settings; s.sunElevation = newValue; modifiers = s.modifiers }
    }

    private static func loadModifiers() -> [Lighting.Modifier] {
        if let text = value("modifiers", "") as String?, !text.isEmpty, let data = text.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            let read = list.compactMap { Lighting.Modifier(json: $0) }
            if !read.isEmpty { return read }
        }
        // The keys from before the stack, as bake/settings.json had them.
        let d = UserDefaults.standard
        var json: [String: Any] = [:]
        let keys: [(String, String)] = [("bounces", "bounces"), ("gamma", "gamma"), ("depth", "depth"), ("faceRadius", "face_radius"),
                                        ("faceStep", "face_step"), ("creaseRadius", "crease_radius"), ("creaseDepth", "crease_depth"),
                                        ("mode", "mode"), ("aoRadius", "ao_radius"), ("sun", "sun"), ("sunAzimuth", "sun_azimuth"),
                                        ("sunElevation", "sun_elevation"), ("sunStrength", "sun_strength"), ("skyStrength", "sky_strength")]
        for (key, name) in keys { if let v = d.object(forKey: "light." + key) { json[name] = v } }
        guard !json.isEmpty else { return Lighting.Modifier.standard }
        var s = Lighting.Settings(json: json)
        if let sided = d.object(forKey: "light.sided") as? Bool { s.sidedTones = sided }
        // Only what was on stays in the stack; the rest is added by hand.
        return s.modifiers.filter(\.on)
    }

    /// Adds a modifier of a kind to the stack, on.
    func add(_ kind: String) { modifiers.append(.make(kind)) }
    func remove(at i: Int) { if modifiers.indices.contains(i) { modifiers.remove(at: i) } }
    /// Whether a kind may be added: a repeatable one always, another when
    /// the stack has none of it.
    func canAdd(_ kind: String) -> Bool {
        (Lighting.Modifier.kinds.first { $0.kind == kind }?.repeatable ?? false) || !modifiers.contains { $0.kind == kind }
    }

    /// These as TileKit's settings, for a bake in the app.
    var settings: Lighting.Settings {
        var s = Lighting.Settings()
        s.size = size
        s.samples = samples
        s.modifiers = modifiers
        return s
    }

    /// The bake command's options for these settings.
    var arguments: [String] {
        let json = (try? JSONSerialization.data(withJSONObject: modifiers.map { $0.json() })).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return ["--size", "\(size)", "--samples", "\(samples)", "--modifiers", json]
    }

    /// Everything the landmark preview's bake depends on: the arguments
    /// (the stack among them) and the sun's direction for the engine's
    /// shadow.
    var previewKey: String { arguments.joined(separator: " ") }
}
