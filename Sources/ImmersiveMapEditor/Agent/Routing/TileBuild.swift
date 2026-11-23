import Foundation
import TileKit

/// Tiles built by the agent's servers (`TileMCP`'s and `AreaMCP`'s
/// build_tile, the area's update_archive), as the editor builds them: the
/// pipeline's `build --changed` with the parts of the build sheet, run as
/// the editor's own binary (the user, 2026-11-22: a tile built once its
/// landmarks' models are made, by the session that made them).
enum TileBuild {
    /// The build sheet's parts as the editor keeps them (`Session.buildParts`).
    static let partsKey = "build.parts"

    /// The parts the build sheet has now: what a tile session builds with.
    static var sheetParts: [String] {
        UserDefaults.standard.stringArray(forKey: partsKey) ?? Array(Build.allParts).sorted()
    }

    /// Builds the tiles of one zoom whose inputs changed since their last
    /// build, with `parts`; its summary ("1 tiles ok, 0 failed"), or a
    /// failure with the pipeline's last word.
    static func run(root: URL, z: Int, tiles: [TileKey], parts: [String]) throws -> String {
        guard !tiles.isEmpty else { return "No tile to build." }
        let kept = Set(parts).subtracting(Features.roads ? [] : ["roads"]).sorted().joined(separator: ",")
        let (status, output) = pipeline(root, ["build", "\(z)", "--changed", "--parts", kept] + (Features.roads ? [] : ["--no-roads"])
                                        + ["--tiles"] + tiles.map { "\($0.x)/\($0.y)" })
        let summary = output.split(separator: "\n").last { $0.contains("tiles") && ($0.contains("ok") || $0.contains("failed")) }
        guard status == 0 else { throw MCPChannel.Failure("the build of " + tiles.map(\.name).joined(separator: ", ") + " failed: " + lastWord(output)) }
        return String(summary ?? "built")
    }

    /// The finished landmarks of a tile tidied once it is built, their
    /// working files gone (`LandmarkTidy`; the user, 2026-11-22: the disk
    /// filled with what no one cleared), and what that freed, said.
    static func tidied(_ landmarks: URL) -> String {
        let (count, freed) = LandmarkTidy.tidyTile(landmarks)
        return count == 0 ? "No landmark to tidy." : "\(count) finished landmarks tidied, \(LandmarkTidy.text(freed)) freed (their candidates and old rounds; the models, recipes and references stay)."
    }

    /// One of the pipeline's commands on the data folder at `root`, the
    /// editor run as it runs them; its status and output.
    static func pipeline(_ root: URL, _ arguments: [String]) -> (Int32, String) {
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return LandmarkMCP.Server.run(exe, ["pipeline", "--root", root.path] + arguments)
    }

    /// The pipeline's last word on a failure: its error line, else its last line.
    static func lastWord(_ output: String) -> String {
        let lines = output.split(separator: "\n").filter { !$0.hasPrefix("@progress") }
        return String(lines.last { $0.hasPrefix("pipeline: ") }?.dropFirst(10) ?? lines.last ?? "no output")
    }

    /// The tile a tile's `landmarks/` folder belongs to and the data folder
    /// it is in: tiles/z/x/y/landmarks.
    static func tile(ofLandmarks folder: URL) -> (root: URL, tile: TileKey)? {
        let tileFolder = folder.standardizedFileURL.deletingLastPathComponent()
        let parts = tileFolder.pathComponents.suffix(3).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let root = (0..<4).reduce(tileFolder) { url, _ in url.deletingLastPathComponent() }
        return (root, TileKey(z: parts[0], x: parts[1], y: parts[2]))
    }
}
