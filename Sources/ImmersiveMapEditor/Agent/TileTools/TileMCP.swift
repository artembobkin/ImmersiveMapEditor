import Foundation
import TileKit

/// The modelling tools of every landmark of a tile behind one MCP server
/// (`ImmersiveMapEditor landmark-mcp --tile FOLDER`, FOLDER the tile's
/// `landmarks/`), for one agent session that hands each landmark without
/// a model to a subagent of its own (the user, 2026-11-21: the whole tile
/// modelled from one prompt, not a session a landmark).
///
/// Each tool is a landmark's tool (`LandmarkMCP`) with one more argument,
/// `landmark`, its folder's name, the call passed to that landmark's own
/// server (`LandmarkRouter`). Three tools of the tile's own: `list_landmarks`,
/// `get_brief`, the landmark's prompt as Copy Prompt gives it, and
/// `build_tile`, the tile built once its models are made (`TileBuild`).
enum TileMCP {
    static func run(landmarks folder: URL) -> Never {
        let landmarks = folder.standardizedFileURL
        let channel = MCPChannel()
        let router = LandmarkRouter(channel: channel)
        channel.serve { m in
            guard !channel.answerProtocol(m, tools: tools), let id = m["id"] else { return }
            let params = m["params"] as? [String: Any] ?? [:]
            var args = params["arguments"] as? [String: Any] ?? [:]
            let landmark = args.removeValue(forKey: "landmark") as? String ?? ""
            let name = params["name"] as? String ?? ""
            if name == "list_landmarks" {
                channel.reply(MCPChannel.result(id, [MCPChannel.text(LandmarkRouter.listLandmarks(in: landmarks))]))
                return
            }
            if name == "build_tile" {
                // On a thread of its own: the subagents' calls go on meanwhile.
                Thread.detachNewThread {
                    do {
                        guard let (root, tile) = TileBuild.tile(ofLandmarks: landmarks) else { throw MCPChannel.Failure("this folder is no tile's landmarks/") }
                        let said = try TileBuild.run(root: root, z: tile.z, tiles: [tile], parts: TileBuild.sheetParts)
                        channel.reply(MCPChannel.result(id, [MCPChannel.text("\(tile.name): \(said). " + TileBuild.tidied(landmarks))]))
                    } catch {
                        channel.reply(MCPChannel.failure(id, "\(error)"))
                    }
                }
                return
            }
            guard LandmarkRouter.isName(landmark) else {
                channel.reply(MCPChannel.failure(id, "give landmark: the id list_landmarks names"))
                return
            }
            let folder = landmarks.appendingPathComponent(landmark)
            if name == "get_brief" {
                do {
                    let brief = try LandmarkRouter.brief(folder, calling: "The landmark tools here serve every landmark of the tile: give landmark: \"\(landmark)\" in every call.")
                    channel.reply(MCPChannel.result(id, [MCPChannel.text(brief)]))
                } catch {
                    channel.reply(MCPChannel.failure(id, "\(error)"))
                }
                return
            }
            router.call(name, args, landmark: folder, id: id)
        }
        router.quit()
        exit(0)
    }

    static let landmarkArgument: [String: Any] = ["type": "string", "description": "The landmark's id, as list_landmarks names it."]

    /// The landmark's tools, each taking `landmark`, and the tile's own.
    static let tools: [[String: Any]] = [
        ["name": "list_landmarks",
         "description": "Every landmark of the tile: its id (what every other tool takes as landmark), name, buildings, and whether it has a model yet.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "build_tile",
         "description": "Builds the tile with its landmarks' models, once every landmark has finished (made or skipped): its 3D tile as the editor builds it, with the parts of the editor's build sheet, then its finished landmarks' working files tidied (their candidates and old rounds; models, recipes and references stay). A minute or so.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "get_brief",
         "description": "The whole brief for modelling one landmark: what to do, the plan and its budget. The first call of whoever models it.",
         "inputSchema": ["type": "object", "properties": ["landmark": landmarkArgument], "required": ["landmark"]]],
    ] + MCPChannel.adding([("landmark", landmarkArgument)], to: LandmarkMCP.Server.tools)
}
