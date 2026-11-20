import Foundation

/// What a tile's build is made from, written beside the build as
/// `build/inputs.txt` when it succeeds, so a build of many tiles can leave
/// out those whose inputs have not changed since (the user, 2026-11-20:
/// with many models, building every tile again each time takes too long).
///
/// The inputs, one a line, readable: this build's version, the parts
/// asked for, the tile's OSM, the road document when the roads are built,
/// the data folder's model recipes (landmarks/models.json), the palette
/// the tile is built with (by content), and the top-level files of every
/// landmark folder of the tile and its eight neighbours (their models, landmark.json and recipe:
/// a neighbour's model standing near the edge takes its buildings out of
/// this tile's build). A file is its size and modification time; a small
/// one that a person edits by hand, its whole content.
public enum BuildInputs {
    /// Raised whenever a change of the pipeline changes what a build makes
    /// from the same inputs, so every tile is built again once.
    public static let version = 1

    static let fileName = "inputs.txt"

    /// The inputs of the tile's build with `parts`, as written.
    public static func fingerprint(_ paths: WorkspacePaths, z: Int, x: Int, y: Int, parts: Set<String>) -> String {
        var lines = ["version \(version)", "parts " + parts.sorted().joined(separator: ",")]
        let osm = paths.tileData(z: z, x: x, y: y)
        for name in ["osm.bin", "osm.json"] { lines.append(stamp(osm.appendingPathComponent(name))) }
        if parts.contains("roads"), let document = RoadDocument.find(z: z, x: x, y: y, in: paths) {
            lines.append(stamp(document))
        }
        lines.append(content(paths.landmarks.appendingPathComponent("models.json")))
        // The palette the tile is built with, as `Palette.load` finds it.
        let named = Palette.tileName(paths, z: z, x: x, y: y).map { Palette.palettesFolder(paths).appendingPathComponent($0 + ".json") }
        if let named, FileManager.default.fileExists(atPath: named.path) {
            lines.append(content(named))
        } else {
            lines.append(content(Palette.file(paths)))
        }
        for dx in -1...1 {
            for dy in -1...1 {
                for folder in files(in: paths.tileLandmarks(z: z, x: x + dx, y: y + dy)) {
                    for file in files(in: folder) where ["glb", "json", "geojson"].contains(file.pathExtension.lowercased())
                        && file.lastPathComponent != "agent.json" {
                        lines.append(stamp(file))
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Whether the tile's last build was made from what its inputs are now.
    public static func isCurrent(_ paths: WorkspacePaths, z: Int, x: Int, y: Int, parts: Set<String>) -> Bool {
        guard let written = try? String(contentsOf: file(paths, z: z, x: x, y: y), encoding: .utf8) else { return false }
        return written == fingerprint(paths, z: z, x: x, y: y, parts: parts)
    }

    /// The inputs a build was made from, written once it succeeded.
    public static func record(_ fingerprint: String, _ paths: WorkspacePaths, z: Int, x: Int, y: Int) throws {
        try fingerprint.write(to: file(paths, z: z, x: x, y: y), atomically: true, encoding: .utf8)
    }

    static func file(_ paths: WorkspacePaths, z: Int, x: Int, y: Int) -> URL {
        paths.tileOut(z: z, x: x, y: y).appendingPathComponent(fileName)
    }

    /// The path below the data folder, its size and modification time;
    /// "missing" when there is no such file.
    private static func stamp(_ url: URL) -> String {
        let name = url.path
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let date = values.contentModificationDate else { return "\(name) missing" }
        return "\(name) \(size) \(String(format: "%.3f", date.timeIntervalSince1970))"
    }

    /// The path and its content in one line, or "missing".
    private static func content(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "\(url.path) missing" }
        return "\(url.path) " + String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined()
    }

    /// The entries of a folder in a stable order, none when it is missing.
    private static func files(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
