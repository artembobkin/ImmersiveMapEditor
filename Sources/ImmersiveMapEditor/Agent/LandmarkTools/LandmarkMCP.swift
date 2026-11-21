import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The landmarks' agent's modelling tools: an MCP server on standard input
/// and output (JSON-RPC, a message a line), run by the agent the
/// user starts in the folder (Claude Code or Codex, `AgentSetup`) as
/// `ImmersiveMapEditor landmark-mcp FOLDER` for one landmark's folder. Its
/// tools read the landmark's OSM, write and build its recipe, render the
/// model from around, and keep reference photos with their credits. They
/// touch nothing outside the folder. Downloads go through URLSession
/// (`Download`), which takes the Mac's own proxy settings.
enum LandmarkMCP {
    static func run(folder: URL) -> Never {
        // The tile's palette: tiles/z/x/y/landmarks/<id> is six below the root.
        var root = folder.standardizedFileURL
        for _ in 0..<6 { root = root.deletingLastPathComponent() }
        Palette.load(WorkspacePaths(root: root), in: folder)
        let server = Server(folder: folder.standardizedFileURL)
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let reply = server.handle(message),
               let out = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]) {
                FileHandle.standardOutput.write(out + Data("\n".utf8))
            }
        }
        exit(0)
    }

    final class Server {
        /// How many of a landmark's OSM buildings get_landmark lists, the
        /// largest first: the answer must come through Claude Code whole.
        static let listedBuildings = 120
        /// Whether the run asked for fine detail (LANDMARK_DETAIL in the
        /// server's environment): more comparisons a build.
        static let fine = ProcessInfo.processInfo.environment["LANDMARK_DETAIL"] == "fine"
        let folder: URL
        var references: URL { folder.appendingPathComponent("references") }
        /// The data folder, for the caches every landmark shares.
        var root: URL { (0..<6).reduce(folder) { url, _ in url.deletingLastPathComponent() } }
        var cacheFolder: URL { root.appendingPathComponent("cache") }
        /// What the agent searched through: the candidates it was shown.
        var searchFolder: URL { folder.appendingPathComponent("search") }
        /// The rounds of the work: one a set_recipe, each with its recipe,
        /// its model and every picture made of that model. Before the first
        /// recipe, round 00.
        var roundsFolder: URL { folder.appendingPathComponent("rounds") }
        var currentRound: URL {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: roundsFolder.path)) ?? []).filter { Int($0) != nil }.sorted()
            return roundsFolder.appendingPathComponent(names.last ?? "00")
        }
        func nextRound() -> URL {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: roundsFolder.path)) ?? []).compactMap { Int($0) }
            return roundsFolder.appendingPathComponent(String(format: "%02d", (names.max() ?? 0) + 1))
        }

        init(folder: URL) { self.folder = folder }

        /// The reply to a message, nil for a notification.
        func handle(_ m: [String: Any]) -> [String: Any]? {
            guard let id = m["id"] else { return nil }
            let params = m["params"] as? [String: Any] ?? [:]
            switch m["method"] as? String ?? "" {
            case "initialize":
                return ok(id, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                               "capabilities": ["tools": [:]],
                               "serverInfo": ["name": "landmark", "version": "1"]])
            case "ping":
                return ok(id, [:])
            case "tools/list":
                return ok(id, ["tools": Self.tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                do {
                    return ok(id, ["content": try call(name, args), "isError": false])
                } catch {
                    return ok(id, ["content": [text("\(error)")], "isError": true])
                }
            default:
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "no method \(m["method"] ?? "")"]]
            }
        }

        func ok(_ id: Any, _ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }
        func image(_ url: URL) -> [String: Any]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            // A screenshot can be large: shrunk to what the agent needs.
            if data.count > 900_000, url.pathExtension.lowercased() == "png" {
                let small = url.deletingPathExtension().appendingPathExtension("small.jpg")
                _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "1400", "-s", "format", "jpeg", url.path, "--out", small.path])
                if let d = try? Data(contentsOf: small) { return ["type": "image", "data": d.base64EncodedString(), "mimeType": "image/jpeg"] }
            }
            return ["type": "image", "data": data.base64EncodedString(), "mimeType": mime]
        }

        struct Failure: Error, CustomStringConvertible {
            let description: String
            init(_ d: String) { description = d }
        }

        /// The facades the last set_recipe changed, nil for all (the first
        /// build, or no last round to compare with).
        var lastTouched: [Int]? = nil

        /// The street photos find_street_photos bore out by their tracks in
        /// this session, by id, with the pose they were judged by.
        var confirmed: [String: StreetView] = [:]

    /// The street photos search_street_photos listed in this session, by id,
    /// with the pose they were shown by, Mapillary's description, and
    /// whether that pose is a guess (its compass pointed away).
    var candidates: [String: (view: StreetView, entry: [String: Any], guessed: Bool)] = [:]

    /// The search spent in this session (`LandmarkMCP+Budget`): the pages
    /// of search_street_photos by facade ("" for the whole landmark), and
    /// the photos looked at large.
    var searched: [String: Int] = [:]
    var looked = 0

        /// Runs a program, its output and errors together.
        static func run(_ exe: URL, _ args: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return (-1, "\(error)") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
