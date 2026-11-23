import Foundation
import TileKit

/// The palettes of a data folder as files, with no window: read, written
/// and listed, for the editor's Style view (`PaletteEdits`) and the palette
/// agent's tools (`PaletteMCP`) alike, so both keep one rule: a palette is
/// `config/palettes/<name>.json`, and the data folder's one in use is also
/// copied to `config/palette.json`, which the pipeline reads for a tile
/// that remembers none.
struct PaletteStore {
    let paths: WorkspacePaths

    var folder: URL { Palette.palettesFolder(paths) }
    func url(_ name: String) -> URL { folder.appendingPathComponent(name + ".json") }

    /// The palettes kept, by name, sorted.
    var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    /// The data folder's palette in use, for the tiles that remember none.
    var defaultName: String? { Palette.File.read(Palette.file(paths))?.name }

    func read(_ name: String) -> Palette.File? { Palette.File.read(url(name)) }

    /// A palette written to its file, and to palette.json when it is the
    /// data folder's one in use.
    func write(_ palette: Palette.File) throws {
        try palette.write(url(palette.name))
        if palette.name == defaultName { try palette.write(Palette.file(paths)) }
    }

    /// Whether a name can be a palette's: a file name of its own.
    static func isName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":") && name.count <= 60
    }

    /// The tiles that remember each palette, "z/x/y", by its name.
    var tilesByPalette: [String: [String]] {
        var out: [String: [String]] = [:]
        let fm = FileManager.default
        for z in (try? fm.contentsOfDirectory(atPath: paths.tiles.path)) ?? [] {
            for x in (try? fm.contentsOfDirectory(atPath: paths.tiles.appendingPathComponent(z).path)) ?? [] {
                for y in (try? fm.contentsOfDirectory(atPath: paths.tiles.appendingPathComponent(z).appendingPathComponent(x).path)) ?? [] {
                    guard let zi = Int(z), let xi = Int(x), let yi = Int(y),
                          let name = Palette.tileName(paths, z: zi, x: xi, y: yi) else { continue }
                    out[name, default: []].append("\(z)/\(x)/\(y)")
                }
            }
        }
        return out
    }
}
