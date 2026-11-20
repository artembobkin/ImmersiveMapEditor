import Foundation

/// The archive's tiles as last baked, kept in the data folder's
/// `cache/archive/<zoom>/<x>/<y>.tile` with a `.json` beside each saying
/// what it was baked from, so an archive made again bakes only the tiles
/// whose builds changed and takes the rest as they are (the user,
/// 2026-11-20: with many models, baking every tile again each time takes
/// too long). A tile's key is this baker's version, the format's, the
/// ASTC block, and every file of the builds under it (their placement and
/// GLB), each by its path, size and modification time.
struct ArchiveCache {
    /// Raised whenever a change of the baker changes what it makes from the
    /// same builds, so every tile is baked again once.
    static let version = 1

    let folder: URL

    init(_ paths: WorkspacePaths, zoom: Int) {
        folder = paths.root.appendingPathComponent("cache").appendingPathComponent("archive").appendingPathComponent("\(zoom)")
    }

    /// What a tile was baked into, with how many models it holds and its
    /// line for the archive's summary.
    struct Entry: Codable {
        var key: String
        var models: Int
        var line: String
    }

    /// The key of a tile baked from the builds of these placement files.
    static func key(placements: [URL], blockEdge: Int, formatVersion: Int) -> String {
        var lines = ["baker \(version)", "format \(formatVersion)", "astc \(blockEdge)"]
        for placement in placements.sorted(by: { $0.path < $1.path }) {
            let build = placement.deletingLastPathComponent()
            let files = ((try? FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent == "placement.json" || $0.pathExtension.lowercased() == "glb" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                lines.append("\(file.path) \(values?.fileSize ?? -1) \(String(format: "%.3f", values?.contentModificationDate?.timeIntervalSince1970 ?? 0))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The tile's bytes and entry, when it was baked from what `key` says.
    func read(x: Int, y: Int, key: String) -> (data: Data, entry: Entry)? {
        guard let json = try? Data(contentsOf: entryFile(x: x, y: y)),
              let entry = try? JSONDecoder().decode(Entry.self, from: json), entry.key == key,
              let data = try? Data(contentsOf: tileFile(x: x, y: y)) else { return nil }
        return (data, entry)
    }

    /// The tile's bytes kept, the entry after them, so an entry never
    /// stands beside the bytes of another bake.
    func write(x: Int, y: Int, data: Data, entry: Entry) {
        let tile = tileFile(x: x, y: y)
        try? FileManager.default.createDirectory(at: tile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: entryFile(x: x, y: y))
        guard (try? data.write(to: tile, options: .atomic)) != nil,
              let json = try? JSONEncoder().encode(entry) else { return }
        try? json.write(to: entryFile(x: x, y: y), options: .atomic)
    }

    /// Every kept tile not among `kept` removed: its builds are gone.
    func prune(keeping kept: Set<[Int]>) {
        let fm = FileManager.default
        for column in ModelArchive.numberedFolders(in: folder) {
            for file in (try? fm.contentsOfDirectory(at: column.url, includingPropertiesForKeys: nil)) ?? [] {
                guard let y = Int(file.deletingPathExtension().lastPathComponent), !kept.contains([column.number, y]) else { continue }
                try? fm.removeItem(at: file)
            }
        }
    }

    private func tileFile(x: Int, y: Int) -> URL { folder.appendingPathComponent("\(x)").appendingPathComponent("\(y).tile") }
    private func entryFile(x: Int, y: Int) -> URL { folder.appendingPathComponent("\(x)").appendingPathComponent("\(y).json") }
}
