import Foundation
import TileKit

/// The whole of an area behind one MCP server (`ImmersiveMapEditor
/// landmark-mcp --area FOLDER`, FOLDER the data folder's `agent/` with its
/// `plan.json`, `AreaPlan`): the tiles marked on the map gone through one
/// after another by one agent session, each prepared (its OSM cut from the
/// extracts and its landmarks made as the plan says), its landmarks without
/// a model handed to subagents, and at the end every tile built and the
/// engine's archive made anew (the user, 2026-11-21: the whole process
/// automatic, tile after tile, after choosing the tiles and the landmarks).
///
/// The area's own tools: `list_tiles`, `prepare_tile`, `list_landmarks`,
/// `get_brief`, `build_tile` and `update_archive`; every landmark tool (`LandmarkMCP`)
/// with two more arguments, `tile` and `landmark`, passed to that
/// landmark's own server (`LandmarkRouter`). The long ones (a tile's OSM, a
/// build of every tile) run on a thread of their own, so the subagents'
/// calls go on meanwhile.
enum AreaMCP {
    static func run(agent folder: URL) -> Never {
        let area = Area(folder: folder.standardizedFileURL)
        let channel = MCPChannel()
        let router = LandmarkRouter(channel: channel)
        channel.serve { m in
            guard !channel.answerProtocol(m, tools: tools), let id = m["id"] else { return }
            let params = m["params"] as? [String: Any] ?? [:]
            var args = params["arguments"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let tileName = args.removeValue(forKey: "tile") as? String ?? ""
            let landmark = args.removeValue(forKey: "landmark") as? String ?? ""
            // The slow ones answer from a thread of their own.
            func later(_ work: @escaping @Sendable () throws -> String) {
                Thread.detachNewThread {
                    do { channel.reply(MCPChannel.result(id, [MCPChannel.text(try work())])) } catch { channel.reply(MCPChannel.failure(id, "\(error)")) }
                }
            }
            switch name {
            case "list_tiles":
                channel.reply(MCPChannel.result(id, [MCPChannel.text(area.listTiles())]))
            case "update_archive":
                later { try area.updateArchive() }
            default:
                guard let tile = area.tile(tileName) else {
                    channel.reply(MCPChannel.failure(id, "give tile: one of list_tiles' tiles, as z/x/y"))
                    return
                }
                if name == "prepare_tile" { later { try area.prepare(tile) }; return }
                if name == "build_tile" { later { try area.build(tile) }; return }
                let landmarks = area.paths.tileLandmarks(z: tile.z, x: tile.x, y: tile.y)
                if name == "list_landmarks" {
                    channel.reply(MCPChannel.result(id, [MCPChannel.text(LandmarkRouter.listLandmarks(in: landmarks))]))
                    return
                }
                guard LandmarkRouter.isName(landmark) else {
                    channel.reply(MCPChannel.failure(id, "give landmark: the id list_landmarks names for tile \(tile.name)"))
                    return
                }
                let folder = landmarks.appendingPathComponent(landmark)
                if name == "get_brief" {
                    do {
                        let brief = try LandmarkRouter.brief(folder, calling: "The landmark tools here serve every landmark of the area: give tile: \"\(tile.name)\" and landmark: \"\(landmark)\" in every call.")
                        channel.reply(MCPChannel.result(id, [MCPChannel.text(brief)]))
                    } catch {
                        channel.reply(MCPChannel.failure(id, "\(error)"))
                    }
                    return
                }
                router.call(name, args, landmark: folder, id: id)
            }
        }
        router.quit()
        exit(0)
    }

    static let tileArgument: [String: Any] = ["type": "string", "description": "The tile, z/x/y, as list_tiles names it."]
    static let landmarkArgument: [String: Any] = ["type": "string", "description": "The landmark's id, as list_landmarks names it."]

    static let tools: [[String: Any]] = [
        ["name": "list_tiles",
         "description": "The tiles of the area in the order to go through them, each with whether it has its OSM, whether it is prepared, how many landmarks and how many without a model.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "prepare_tile",
         "description": "Readies a tile: its OSM cut from the extracts when it has none, then its landmarks made of the buildings the user chose, once (a tile prepared before is left as it is). Says what it made and lists the tile's landmarks. A minute or two.",
         "inputSchema": ["type": "object", "properties": ["tile": tileArgument], "required": ["tile"]]],
        ["name": "list_landmarks",
         "description": "Every landmark of a tile: its id (what the landmark tools take as landmark), name, buildings, and whether it has a model yet.",
         "inputSchema": ["type": "object", "properties": ["tile": tileArgument], "required": ["tile"]]],
        ["name": "get_brief",
         "description": "The whole brief for modelling one landmark: what to do, the plan and its budget. The first call of whoever models it.",
         "inputSchema": ["type": "object", "properties": ["tile": tileArgument, "landmark": landmarkArgument], "required": ["tile", "landmark"]]],
        ["name": "build_tile",
         "description": "Builds a tile with its landmarks' models, once every landmark of it has finished (made or skipped): its 3D tile as the editor builds it, with the parts the user chose, then its finished landmarks' working files tidied (their candidates and old rounds; models, recipes and references stay). A minute or so; it runs while you go on with the next tile.",
         "inputSchema": ["type": "object", "properties": ["tile": tileArgument], "required": ["tile"]]],
        ["name": "update_archive",
         "description": "Every tile of the area with its OSM built again where its inputs changed (its landmarks' models among them), then the engine's model archive made anew, for the editor's Engine view. Several minutes. Call it once, at the end.",
         "inputSchema": ["type": "object", "properties": [:]]],
    ] + MCPChannel.adding([("tile", tileArgument), ("landmark", landmarkArgument)], to: LandmarkMCP.Server.tools)
}
