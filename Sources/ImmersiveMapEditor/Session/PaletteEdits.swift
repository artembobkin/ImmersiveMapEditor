import Foundation
import Observation
import TileKit

/// The palette's colours set over the defaults (TileKit's Palette), as the
/// Style view edits them: kept in the data folder's config/palette.json,
/// which the pipeline and the landmark generator read too, so a build takes
/// the colours as saved.
@Observable
@MainActor
final class PaletteEdits {
    private(set) var paths: WorkspacePaths?
    /// The colours set, by name.
    private(set) var colours: [String: String] = [:]
    /// Bumped whenever the palette changes, for the views to read it again.
    private(set) var revision = 0

    var file: URL? { paths.map(Palette.file) }

    func load(_ paths: WorkspacePaths) {
        self.paths = paths
        Palette.load(paths)
        colours = Palette.overrides
        revision += 1
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

    private func save() {
        guard let paths else { return }
        try? Palette.save(colours, paths)
        colours = Palette.overrides
        revision += 1
    }

    /// A colour of the tables, by name, as it is now.
    static func colour(_ name: String) -> String? {
        (Palette.base + Palette.walls + Palette.props + Palette.landmark).first { $0.0 == name }?.1
    }
}
