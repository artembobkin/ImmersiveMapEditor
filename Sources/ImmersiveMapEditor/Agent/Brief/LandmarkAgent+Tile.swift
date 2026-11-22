import Foundation

/// The brief of a whole tile: the prompt of one session started in the
/// tile's `landmarks/` folder that hands every landmark without a model to
/// a subagent, each of which takes its landmark's own brief (`get_brief`,
/// `LandmarkAgent.prompt`). The tools it works through: `TileMCP`.
extension LandmarkAgent {
    /// How many landmarks the tile's session models at once, a subagent
    /// each: each builds and renders on this Mac.
    static let tileAtOnce = 3

    /// The prompt of a session started in a tile's `landmarks/` folder
    /// (`AgentSetup.prepareTile`, the tools of every landmark behind one
    /// server, `TileMCP`): it models every landmark without a model, each
    /// by a subagent of its own with that landmark's whole brief (the user,
    /// 2026-11-21: the whole tile from one prompt). The session itself only
    /// hands out the work, so the pictures stay with the subagents.
    static func tilePrompt(_ tile: String, count: Int) -> String {
        """
        You coordinate the modelling of the landmarks of map tile \(tile) that have no model yet (\(count) now), \
        through the landmark tools (the MCP server "landmark"), where every tool takes the landmark's id as `landmark`. \
        Do not run commands or edit files, and do not model a landmark yourself: a subagent models each.
        1. Call list_landmarks.
        2. For each landmark it marks NO MODEL, start a subagent (the Task tool in Claude Code, spawn_agent in Codex) with this prompt, \
        its id and name put in: "You model one landmark of the tile, id ID (NAME), through the landmark tools only, \
        giving landmark: 'ID' in every call. First call get_brief with landmark 'ID' and follow it to the end. \
        Then answer in three lines: what you built, how many builds, what still differs from the photos." \
        Run \(tileAtOnce) subagents at once, no more: start the next as one finishes (in Codex, wait_agent for them and close_agent a finished one), until every one is done. \
        Their pictures stay with them: do not look at a landmark's pictures yourself.
        A landmark skipped for want of references, a subagent that failed or gave up, a tool that answered with an \
        error: none of these ends the run. Note it for the report and go on with the next landmark until every one is done.
        3. When all have finished (made or skipped), call build_tile: the tile is built with its new models.
        4. Call list_landmarks again and report: which have a model now, which were skipped for want of references (a \
        subagent that skipped its landmark is done: never start it again), and for the others without one, why (from \
        their subagents' answers); then what build_tile said.
        """
    }
}
