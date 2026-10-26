import Foundation
import Observation

/// The landmarks' agent: Claude Code (`claude -p`, on the user's
/// subscription, through the proxy of Settings) run in a landmark's folder
/// with the editor's modelling tools (LandmarkMCP) and web search, nothing
/// else: no shell, no file tools. It looks for freely licensed photos, writes
/// the landmark's recipe, renders it and corrects it. Its conversation is
/// kept (agent.json in the folder), so the user can go on asking. What it
/// does goes to the console; each model it builds is shown at once.
@Observable
@MainActor
final class LandmarkAgent {
    private(set) var running = false
    private var process: Process?
    /// Called when the agent may have built a new model.
    var modelChanged: () -> Void = {}

    static let system = """
    You make stylized low-poly 3D models of real landmarks for a cartoon-style city map, through the landmark tools only: \
    you cannot run commands or edit files. Every model is a recipe of a few architectural words (get_landmark explains \
    them); the generator builds it in the map's one style and palette. Work from the landmark's OSM buildings (its \
    outlines and heights) and from freely licensed photos you find on the web (Wikimedia Commons), saved with \
    save_reference_photo with their author and licence; never use Google or Yandex imagery. Compare your renders with the \
    photos and correct the recipe until the silhouette, proportions, main colours and the few telling details agree. \
    Write short notes of what you do, in English.
    """

    /// Whether the landmark in `folder` has a conversation to go on with.
    static func hasConversation(_ folder: URL) -> Bool { conversation(folder) != nil }

    /// What the agent makes in a landmark's folder, besides the photos.
    static let work = ["views", "recipe.json", "model.glb", "agent.json"]

    /// Whether the agent has made anything in `folder`.
    static func hasWork(_ folder: URL) -> Bool {
        (work + ["references"]).contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Removes everything the agent made in `folder`: its photos, renders,
    /// recipe, model and conversation. The landmark itself (landmark.json,
    /// footprint.geojson) stays.
    static func forget(_ folder: URL) {
        for name in work + ["references"] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }

    /// A new attempt starts from OSM again: the renders, recipe, model and
    /// conversation of the last one go, the photos stay to be used again.
    static func startOver(_ folder: URL) {
        for name in work { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }

    private static func conversation(_ folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("agent.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["session"] as? String
    }

    /// Starts modelling the landmark, or goes on with its conversation when
    /// `request` is given.
    func start(folder: URL, name: String, request: String?, console: BuildRunner) {
        guard !running else { return }
        guard let claude = ClaudeSettings.executable else {
            console.append("No claude found: set its path in Settings > Claude.")
            return
        }
        guard !ClaudeSettings.proxy.isEmpty else {
            console.append("No proxy set: Claude Code must go through the proxy. Settings > Claude.")
            return
        }
        guard console.begin("Claude: \(name)", stage: "Claude is modelling \(name)") else { return }
        var args = ["-p", request ?? Self.firstRequest(name), "--output-format", "stream-json", "--verbose",
                    "--tools", "WebSearch,WebFetch",
                    "--allowedTools", "WebSearch,WebFetch,mcp__landmark",
                    "--permission-mode", "dontAsk",
                    "--strict-mcp-config", "--mcp-config", Self.mcpConfig(folder),
                    "--append-system-prompt", Self.system]
        if let model = UserDefaults.standard.string(forKey: ClaudeSettings.modelKey), !model.isEmpty {
            args += ["--model", model]
        }
        if request != nil, let session = Self.conversation(folder) {
            args += ["--resume", session]
        } else {
            Self.startOver(folder)
            modelChanged()
            let session = UUID().uuidString.lowercased()
            args += ["--session-id", session]
            let json = try? JSONSerialization.data(withJSONObject: ["session": session, "started": ISO8601DateFormatter().string(from: Date())],
                                                   options: [.prettyPrinted, .sortedKeys])
            try? json?.write(to: folder.appendingPathComponent("agent.json"))
        }
        if let request { console.append("> \(request)") }
        let p = Process()
        p.executableURL = claude
        p.arguments = args
        p.currentDirectoryURL = folder
        p.environment = ClaudeSettings.environment
        let pipe = Pipe(), errors = Pipe()
        p.standardOutput = pipe
        p.standardError = errors
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            console.append("Cannot start claude: \(error.localizedDescription)")
            console.end(false)
            return
        }
        process = p
        running = true
        Task {
            var ok = false
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    if let event = Self.event(line) {
                        if let text = event.text { console.append(text) }
                        if event.toolDone { modelChanged() }
                        if let result = event.ok { ok = result }
                    }
                }
            } catch {
                console.append("\(error.localizedDescription)")
            }
            p.waitUntilExit()
            let said = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if p.terminationStatus != 0, !said.isEmpty { console.append(said) }
            modelChanged()
            console.end(ok && p.terminationStatus == 0)
            running = false
            process = nil
        }
    }

    func stop() { process?.terminate() }

    static func firstRequest(_ name: String) -> String {
        """
        Make the stylized low-poly model of the landmark "\(name)" (its folder is the working directory).
        1. get_landmark, then render_views with boxes: true to see its OSM buildings.
        2. list_references: photos kept from earlier work are there to use, look at them with show_reference. Then \
        find_street_photos (Mapillary, street level all around it): it returns the best candidates, a track at a time, \
        and a contact sheet with the landmark framed in red on each by the camera's pose. Poses are sometimes wrong: judge \
        from the sheet which frames really hold the landmark, keep those (one or two a side, the main facade and the \
        entrances first) with save_street_photo, look at each as it comes back, and drop_reference any whose frame is on \
        another building. Search the web for more freely licensed photos (Wikimedia Commons) only for what the street \
        does not show: the whole from afar, the roofs from above. Keep 4 to 8 good ones in all.
        3. Write its recipe with set_recipe, render_views, compare with the photos, correct. Three to five rounds, until the \
        silhouette, proportions, colours and main details agree.
        4. Before you finish, check from eye level in front of the main facade (render_views from the side it faces) and \
        from above, against this list: every entrance the photos show is a door; every roof reads as a volume (eaves and \
        fascia on a pitched roof, a parapet or balustrade on a flat one, never a bare flat cap on a historic building); \
        the cornice, pilasters or bands where the facade has them; the sculpture that makes the building recognisable; \
        the colours of the photos in the palette's words. Fix what is missing.
        5. End with a short summary: what the model has, and what you were not sure of.
        """
    }

    /// The MCP server of the modelling tools: the editor itself, for this folder.
    static func mcpConfig(_ folder: URL) -> String {
        var server: [String: Any] = ["command": Bundle.main.executableURL!.path, "args": ["landmark-mcp", folder.path]]
        let token = ClaudeSettings.mapillaryToken
        if !token.isEmpty { server["env"] = ["MAPILLARY_TOKEN": token] }
        let data = try! JSONSerialization.data(withJSONObject: ["mcpServers": ["landmark": server]], options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    /// One line of Claude Code's stream: what to show of it, whether a tool
    /// has finished (a model may have changed), and how the run ended.
    struct Event {
        var text: String?
        var toolDone = false
        var ok: Bool?
    }

    static func event(_ line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch json["type"] as? String {
        case "system" where json["subtype"] as? String == "init":
            let tools = (json["tools"] as? [String] ?? []).joined(separator: ", ")
            return Event(text: "Claude started (\(json["model"] as? String ?? "?")), tools: \(tools)")
        case "assistant":
            let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let lines = content.compactMap { c -> String? in
                switch c["type"] as? String {
                case "text": return (c["text"] as? String).map { "\n" + $0 }
                case "tool_use":
                    let name = (c["name"] as? String ?? "").replacingOccurrences(of: "mcp__landmark__", with: "")
                    return "→ \(name) \(brief(c["input"]))"
                default: return nil
                }
            }
            return lines.isEmpty ? nil : Event(text: lines.joined(separator: "\n"))
        case "user":
            let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let results = content.filter { $0["type"] as? String == "tool_result" }
            guard !results.isEmpty else { return nil }
            let lines = results.compactMap { r -> String? in
                let texts = (r["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? [(r["content"] as? String) ?? ""]
                let first = texts.joined(separator: " ").split(separator: "\n").first.map(String.init) ?? ""
                return r["is_error"] as? Bool == true ? "  ✗ \(first.prefix(300))" : (first.isEmpty ? nil : "  \(first.prefix(200))")
            }
            return Event(text: lines.isEmpty ? nil : lines.joined(separator: "\n"), toolDone: true)
        case "result":
            let error = json["is_error"] as? Bool ?? false
            let seconds = (json["duration_ms"] as? Double ?? 0) / 1000
            return Event(text: String(format: "\n%@ in %.0f s, %d turns", error ? "Ended with an error" : "Finished", seconds,
                                      json["num_turns"] as? Int ?? 0), ok: !error)
        default:
            return nil
        }
    }

    /// A tool's input in a line.
    static func brief(_ input: Any?) -> String {
        guard let input = input as? [String: Any], !input.isEmpty else { return "" }
        if input["recipe"] != nil { return "(recipe)" }
        let parts = input.keys.sorted().map { k -> String in
            let v = input[k].map { "\($0)" } ?? ""
            return "\(k): \(v.count > 80 ? String(v.prefix(80)) + "…" : v)"
        }
        return parts.joined(separator: ", ")
    }
}
