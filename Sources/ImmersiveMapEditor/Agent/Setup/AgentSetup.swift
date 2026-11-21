import Foundation

/// A folder set up for an agent the user starts in it from a terminal (the
/// user, 2026-11-20: their own `claude` or `codex` launchers, through their
/// own proxy, not runs of the editor's): the editor's modelling tools
/// declared as the project's MCP server for both, written each time the
/// prompt or the folder's command is copied, so the detail and the
/// exaggeration are the ones set then. Two kinds of folder:
///
/// - a landmark's own (`prepare`), its tools `landmark-mcp FOLDER`
///   (`LandmarkMCP`), for one agent modelling it;
/// - a tile's `landmarks/` (`prepareTile`), the tools of every landmark of
///   the tile behind one server, `landmark-mcp --tile FOLDER` (`TileMCP`),
///   for one session that models them all with a subagent each.
/// - the data folder's `agent/` (`prepareArea`), the tiles marked on the map
///   with their plan, `landmark-mcp --area FOLDER` (`AreaMCP`), for one
///   session that prepares, models and archives them all.
///
/// Each gets the same three files:
///
/// - `.mcp.json`: Claude Code's project MCP servers.
/// - `.claude/settings.json`: the server approved and its tools, web search
///   and fetch allowed without asking, and none of the user's CLAUDE.md
///   files or auto memory, with the larger tool answers get_landmark needs.
/// - `.codex/config.toml`: Codex's project config with the same server
///   (Codex reads it once the folder is trusted, as it asks at its first
///   start there). No proxy is passed on (`env_vars` would make each
///   variable a required one, the server refused without it): the tools
///   reach Mapillary, Esri and Commons through the Mac's own proxy
///   settings (`Download`).
///
/// Nothing secret goes into the files: the tools read Mapillary's token from
/// the editor's keychain themselves (`App`), and no proxy is named.
enum AgentSetup {
    /// A landmark's folder set up for one agent modelling it, at `fine` detail.
    static func prepare(_ folder: URL, fine: Bool) throws {
        try write(folder, server: ["landmark-mcp", folder.path], fine: fine)
    }

    /// A tile's `landmarks/` folder set up for one session that models all
    /// its landmarks with a subagent each (`LandmarkAgent.tilePrompt`).
    static func prepareTile(_ landmarks: URL, fine: Bool) throws {
        try write(landmarks, server: ["landmark-mcp", "--tile", landmarks.path], fine: fine)
    }

    /// The data folder's `agent/` set up for one session that goes through
    /// the tiles marked on the map (`AreaMCP`, `LandmarkAgent.areaPrompt`).
    static func prepareArea(_ folder: URL, fine: Bool) throws {
        try write(folder, server: ["landmark-mcp", "--area", folder.path], fine: fine)
    }

    /// The three files written into `folder`, the server the editor itself
    /// run with `server` as its arguments.
    private static func write(_ folder: URL, server arguments: [String], fine: Bool) throws {
        let fm = FileManager.default
        let server: [String: Any] = ["command": Bundle.main.executableURL!.path, "args": arguments, "env": environment(fine: fine)]
        try json(["mcpServers": ["landmark": server]]).write(to: folder.appendingPathComponent(".mcp.json"), options: .atomic)
        let claude = folder.appendingPathComponent(".claude")
        try fm.createDirectory(at: claude, withIntermediateDirectories: true)
        try json(claudeSettings).write(to: claude.appendingPathComponent("settings.json"), options: .atomic)
        let codex = folder.appendingPathComponent(".codex")
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data(codexConfig(arguments, fine: fine).utf8).write(to: codex.appendingPathComponent("config.toml"), options: .atomic)
    }

    /// The command that goes into the folder in a terminal, quoted for the shell.
    static func changeDirectory(_ folder: URL) -> String {
        "cd '" + folder.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The tools' environment: the detail asked and the generator's exaggeration.
    static func environment(fine: Bool) -> [String: String] {
        AgentSettings.generatorEnvironment.merging(["LANDMARK_DETAIL": fine ? "fine" : "normal"]) { _, new in new }
    }

    static let claudeSettings: [String: Any] = [
        "enableAllProjectMcpServers": true,
        "enabledMcpjsonServers": ["landmark"],
        "permissions": ["allow": ["mcp__landmark", "WebSearch", "WebFetch"]],
        "env": [
            "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1",
            "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
            // A tool's answer Claude Code passes on whole: its default of 25
            // thousand tokens cut get_landmark off for St Basil's 514 parts
            // (the user, 2026-11-04); the answers are bounded on our side too.
            "MAX_MCP_OUTPUT_TOKENS": "60000",
            // A tool call may take minutes: list_references gathers every
            // reference when none are kept, a fine set_recipe builds and
            // renders for long; twenty minutes before Claude Code gives up.
            "MCP_TOOL_TIMEOUT": "1200000",
        ],
    ]

    /// Codex's project config: the same server, a call allowed twenty
    /// minutes (the references gathered, a fine build).
    static func codexConfig(_ arguments: [String], fine: Bool) -> String {
        let env = environment(fine: fine).sorted { $0.key < $1.key }.map { "\($0.key) = \(toml($0.value))" }
        return """
        # Written by Immersive Map Editor when the landmark's prompt is copied.
        [mcp_servers.landmark]
        command = \(toml(Bundle.main.executableURL!.path))
        args = [\(arguments.map(toml).joined(separator: ", "))]
        env = { \(env.joined(separator: ", ")) }
        required = true
        startup_timeout_sec = 30
        tool_timeout_sec = 1200

        """
    }

    /// A TOML basic string: JSON's escapes, which TOML shares, slashes left as they are.
    private static func toml(_ value: String) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
    }

    private static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
