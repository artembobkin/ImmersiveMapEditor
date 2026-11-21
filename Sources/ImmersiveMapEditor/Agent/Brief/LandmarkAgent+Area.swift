import Foundation

/// The brief of an area: the prompt of one session started in the data
/// folder's `agent/` that goes through the tiles marked on the map, one
/// after another: each prepared (its OSM, its landmarks as the user chose),
/// each landmark without a model handed to a subagent with its own brief
/// (`get_brief`), and the engine's archive made anew at the end. The tools
/// it works through: `AreaMCP`.
extension LandmarkAgent {
    static func areaPrompt(tiles: Int) -> String {
        """
        You run the modelling of an area of the map, \(tiles) tiles, from start to end, through the landmark tools (the \
        MCP server "landmark"). Do not run commands or edit files, and do not model a landmark yourself: a subagent models each.
        1. Call list_tiles: the tiles in the order to go through them.
        2. Tile after tile, in that order: prepare_tile (its OSM, and its landmarks made of the buildings the user chose), \
        then for each landmark it lists as NO MODEL start a subagent (the Task tool in Claude Code, spawn_agent in Codex) \
        with this prompt, its tile, id and name put in: "You model one landmark, tile TILE, id ID (NAME), through the \
        landmark tools only, giving tile: 'TILE' and landmark: 'ID' in every call. First call get_brief with them and follow \
        it to the end. Then answer in three lines: what you built, how many builds, what still differs from the photos."
        Keep \(tileAtOnce) subagents running, no more: start the next as one finishes (in Codex, wait_agent for them and \
        close_agent a finished one). When a tile has no landmark left to start, prepare the next tile and go on, so the \
        subagents never wait. Their pictures stay with them: do not look at a landmark's pictures yourself.
        3. When every landmark of every tile has finished, call update_archive once: the tiles are built with their new \
        models and the engine's archive is made anew.
        4. Report, tile by tile: the landmarks made, which have a model now, which were skipped for want of references \
        (a subagent that skipped its landmark is done: never start it again), and for the others without one, why (from \
        their subagents' answers); then what update_archive said.
        """
    }
}
