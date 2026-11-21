import Foundation
import TileKit

/// What the area's automation is asked to do (`AreaMCP`), written by the
/// editor into the data folder's `agent/plan.json` when its prompt is
/// copied: the tiles marked on the map in the order to go through them,
/// which of each tile's buildings become landmarks and how many, and the
/// parts a tile is built with. `prepared` the tiles whose landmarks were
/// made already, so a tile is never given more landmarks by a second
/// prepare_tile (with a limit, each would take the next largest).
struct AreaPlan: Codable {
    var tiles: [String]
    var kind: String
    /// How many landmarks a tile at most, the largest first; 0 for all.
    var limit: Int
    var parts: [String]
    var prepared: [String] = []

    static func folder(_ paths: WorkspacePaths) -> URL { paths.root.appendingPathComponent("agent") }
    static func file(in folder: URL) -> URL { folder.appendingPathComponent("plan.json") }

    static func read(_ folder: URL) throws -> AreaPlan {
        try JSONDecoder().decode(AreaPlan.self, from: Data(contentsOf: file(in: folder)))
    }

    func write(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.file(in: folder), options: .atomic)
    }

    var landmarkKind: LandmarkKind { LandmarkKind(rawValue: kind) ?? .known }

    /// A tile's key from "z/x/y".
    static func key(_ name: String) -> TileKey? {
        let n = name.split(separator: "/").compactMap { Int($0) }
        return n.count == 3 ? TileKey(z: n[0], x: n[1], y: n[2]) : nil
    }
}
