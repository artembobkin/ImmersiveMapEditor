import Foundation
import Observation
import TileKit

/// The palettes of the data folder and the one in use (the user,
/// 2026-11-04: palettes by name, a common one, Moscow's, Indonesia's, to
/// choose from in the toolbar and try): each a file of
/// `config/palettes/`, the colours set over TileKit's defaults by name and
/// the landmark colours added beyond them. The one chosen is copied to
/// `config/palette.json`, which the pipeline and the landmark generator
/// read, so every build, every run of Claude and every preview paints with
/// the palette chosen. The Style view edits the one in use; a change is
/// saved to both files at once.
@Observable
@MainActor
final class PaletteEdits {
    private(set) var paths: WorkspacePaths?
    /// The palettes kept, by name, sorted.
    private(set) var names: [String] = []
    /// The one in use.
    private(set) var active = "Common"
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
        seedIfNone(paths)
        Palette.load(paths)
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
        colours = Palette.overrides
        extras = Palette.extras
        revision += 1
    }

    /// The palette of this name put in use: copied to palette.json and applied.
    func select(_ name: String) {
        guard let paths, let palette = Palette.File.read(Palette.palettesFolder(paths).appendingPathComponent(name + ".json")) else { return }
        try? Palette.save(palette, paths)
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
        if active == name, let other = names.first(where: { $0 != name }) { select(other) } else { take() }
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

    /// The palette in use written to palette.json and to its own file.
    private func save() {
        guard let paths else { return }
        let palette = Palette.File(name: active, colours: colours, extra: extras)
        try? Palette.save(palette, paths)
        try? palette.write(Palette.palettesFolder(paths).appendingPathComponent(active + ".json"))
        take()
    }

    /// A colour of the tables, by name, as it is now.
    static func colour(_ name: String) -> String? {
        (Palette.base + Palette.walls + Palette.props + Palette.landmark).first { $0.0 == name }?.1
    }
}
