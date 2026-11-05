import Foundation
import Observation
import TileKit

/// The palettes of the data folder and the one in use (the user,
/// 2026-11-04: palettes by name, a common one, Moscow's, Indonesia's, to
/// choose from in the toolbar and try): each a file of
/// `config/palettes/`, the colours set over TileKit's defaults by name and
/// the landmark colours added beyond them. The one chosen is copied to
/// `config/palette.json`, which the pipeline and the landmark generator
/// read for a tile that remembers none. A tile remembers its own in its
/// `palette.json` (the user, 2026-11-05: a palette is a city's, and with
/// one for the data folder a Jakarta tile would not build while Moscow's
/// was chosen): the toolbar's menu while a tile is open sets the tile's,
/// while choosing it sets the data folder's. The Style view edits the one
/// shown, saved to its own file (and to palette.json when it is the data
/// folder's).
@Observable
@MainActor
final class PaletteEdits {
    private(set) var paths: WorkspacePaths?
    /// The palettes kept, by name, sorted.
    private(set) var names: [String] = []
    /// The one shown: the tile's, or the data folder's while choosing.
    private(set) var active = "Common"
    /// The tile whose palette is shown, none while choosing.
    private(set) var tile: (z: Int, x: Int, y: Int)?
    /// The data folder's palette in use, for tiles that remember none.
    private(set) var defaultName = "Common"
    /// Whether the tile shown remembers a palette of its own.
    var remembered: Bool { tile.map { Palette.tileName(paths!, z: $0.z, x: $0.x, y: $0.y) != nil } ?? false }
    /// Its colours set over the defaults, by name.
    private(set) var colours: [String: String] = [:]
    /// Its landmark colours added beyond the defaults.
    private(set) var extras: [(String, String)] = []
    /// Bumped whenever the palette changes, for the views to read it again.
    private(set) var revision = 0

    var file: URL? { paths.map(Palette.file) }

    /// The three palettes a data folder starts with: the common one with
    /// every material, Moscow's with the defaults alone (and whatever the
    /// folder's old palette.json had set), Indonesia's with the materials
    /// of its buildings.
    static let universal: [(String, String)] = [
        ("lm_terracotta", "#B5653F"), ("lm_marble", "#F2EFE8"), ("lm_concrete", "#B9B3A8"), ("lm_sand", "#D8C39A"),
        ("lm_wood", "#6E4B32"), ("lm_blue", "#4E7FA8"), ("lm_copper", "#6E9A84"), ("lm_black", "#3A3A40"),
    ]

    func load(_ paths: WorkspacePaths) {
        self.paths = paths
        tile = nil
        seedIfNone(paths)
        Palette.load(paths)
        take()
    }

    /// The palette of this tile shown and applied (nil: the data folder's,
    /// while choosing).
    func show(tile: (z: Int, x: Int, y: Int)?) {
        guard let paths else { return }
        self.tile = tile
        if let tile { Palette.load(paths, z: tile.z, x: tile.x, y: tile.y) } else { Palette.load(paths) }
        take()
    }

    /// The palettes folder made with the first three when the data folder
    /// has none, the old palette.json's colours going to Moscow's.
    private func seedIfNone(_ paths: WorkspacePaths) {
        let folder = Palette.palettesFolder(paths)
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        let old = Palette.File.read(Palette.file(paths))
        let three = [Palette.File(name: "Common", extra: Self.universal),
                     Palette.File(name: "Moscow", colours: old?.colours ?? [:], extra: old?.extra ?? []),
                     Palette.File(name: "Indonesia", colours: ["lm_cream": "#EFE4CC"], extra: Self.universal)]
        for p in three { try? p.write(folder.appendingPathComponent(p.name + ".json")) }
        // The one in use: Moscow's when the old palette had colours set, else the common one.
        let first = (old?.colours.isEmpty ?? true) ? three[0] : three[1]
        try? first.write(Palette.file(paths))
    }

    /// What TileKit holds now, taken into the view's state.
    private func take() {
        guard let paths else { return }
        names = ((try? FileManager.default.contentsOfDirectory(atPath: Palette.palettesFolder(paths).path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
        active = Palette.activeName
        defaultName = Palette.File.read(Palette.file(paths))?.name ?? "Common"
        colours = Palette.overrides
        extras = Palette.extras
        revision += 1
    }

    /// The palette of this name put in use: remembered by the tile shown and
    /// applied, or, while choosing, copied to palette.json as the data
    /// folder's.
    func select(_ name: String) {
        guard let paths, let palette = Palette.File.read(Palette.palettesFolder(paths).appendingPathComponent(name + ".json")) else { return }
        if let tile {
            try? Palette.remember(name, paths, z: tile.z, x: tile.x, y: tile.y)
            Palette.load(paths, z: tile.z, x: tile.x, y: tile.y)
        } else {
            try? Palette.save(palette, paths)
        }
        take()
    }

    /// A new palette, a copy of the one in use under this name, put in use.
    func create(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let paths, !name.isEmpty, !names.contains(name) else { return }
        let palette = Palette.File(name: name, colours: colours, extra: extras)
        try? palette.write(Palette.palettesFolder(paths).appendingPathComponent(name + ".json"))
        select(name)
    }

    /// A palette deleted; the one in use stays in use until another is chosen.
    func delete(_ name: String) {
        guard let paths, names.count > 1 else { return }
        try? FileManager.default.removeItem(at: Palette.palettesFolder(paths).appendingPathComponent(name + ".json"))
        // A tile that remembered it forgets it, and the data folder's falls
        // back to another; the other tiles that remembered it fall back to
        // the data folder's at their next build.
        if let tile, active == name { try? Palette.remember(nil, paths, z: tile.z, x: tile.x, y: tile.y) }
        if defaultName == name, let other = names.first(where: { $0 != name }) {
            if let other = Palette.File.read(Palette.palettesFolder(paths).appendingPathComponent(other + ".json")) { try? other.write(Palette.file(paths)) }
        }
        show(tile: tile)
    }

    func set(_ name: String, _ hex: String) {
        colours[name] = hex.uppercased()
        save()
    }

    func reset(_ name: String) {
        colours[name] = nil
        save()
    }

    func resetAll() {
        colours = [:]
        save()
    }

    /// A landmark colour added to the palette in use, "lm_terracotta".
    func addExtra(_ name: String, _ hex: String) {
        let name = name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
        let full = name.hasPrefix("lm_") ? name : "lm_" + name
        guard !extras.contains(where: { $0.0 == full }), !Palette.defaults.flatMap({ $0.colours.map(\.0) }).contains(full) else { return }
        extras.append((full, hex.uppercased()))
        save()
    }

    func removeExtra(_ name: String) {
        extras.removeAll { $0.0 == name }
        colours[name] = nil
        save()
    }

    /// The palette shown written to its own file, and to palette.json when
    /// it is the data folder's, then applied again.
    private func save() {
        guard let paths else { return }
        let palette = Palette.File(name: active, colours: colours, extra: extras)
        try? palette.write(Palette.palettesFolder(paths).appendingPathComponent(active + ".json"))
        if active == defaultName { try? palette.write(Palette.file(paths)) }
        show(tile: tile)
    }

    /// A colour of the tables, by name, as it is now.
    static func colour(_ name: String) -> String? {
        (Palette.base + Palette.walls + Palette.props + Palette.landmark).first { $0.0 == name }?.1
    }
}
