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
        var args = ["-p", request ?? Self.firstRequest(name, detail: Self.detail(of: folder)), "--output-format", "stream-json", "--verbose",
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
        let detail = Self.detail(of: folder)
        if let request { console.append("> \(request)") } else { console.append("Detail: \(detail)") }
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

    /// How detailed the landmark's model is to be (landmark.json's detail).
    static func detail(of folder: URL) -> String {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("landmark.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "normal" }
        return json["detail"] as? String ?? "normal"
    }

    static func firstRequest(_ name: String, detail: String) -> String {
        let level: String
        switch detail {
        case "simple":
            level = """
            DETAIL: simple. The masses, their roofs, the main colours and the one or two things that make it recognisable \\
            (a portico, a dome, a tower). No windows, no small relief. Two rounds. Under 5 000 triangles.
            """
        case "detailed":
            level = """
            DETAIL: detailed. Everything that reads from across the street: every mass of the building with its own roof, \\
            the windows with the real storeys and rhythm of each facade (arched where they are arched), every entrance with \\
            its portal, the plinth, string courses, the cornice with its depth, pilasters and columns where the facade has \\
            them, balustrades and parapets, the sculpture, chimneys and roof lanterns, the attic and its windows. Model from \\
            shapes what the words do not cover (a balustrade of cylinders in a row, a rusticated base as thin boxes, a \\
            moulding as a loft). Six to eight rounds, each on one facade or one part, checked with compare_with_photo. \\
            Up to 60 000 triangles (set_recipe tells the count).
            """
        default:
            level = """
            DETAIL: normal. The masses with their roofs, the windows of every facade in their rhythm, the entrances, the \\
            cornice, the plinth, the relief the facade has (pilasters, bands) and the sculpture that makes it recognisable. \\
            Three to five rounds. Under 25 000 triangles (set_recipe tells the count).
            """
        }
        return """
        Make the stylized low-poly model of the landmark "\(name)" (its folder is the working directory).
        \(level)
        1. get_landmark, then render_views with boxes: true to see its OSM buildings.
        2. list_references: photos kept from earlier work are there to use, look at them with show_reference. Then the \
        references, in this order:
           a. find_commons_photos (Wikimedia Commons, its category and around it, on a contact sheet): keep one or two \
        classic views of the whole with save_commons_photo, to know the building and to judge the street photos by.
           b. find_street_photos (Mapillary, street level all around it): the best candidates a track at a time, and a \
        contact sheet with the landmark framed in red on each by the camera's pose, the rest dimmed. Poses are sometimes \
        wrong: judge from the sheet which frames really hold the landmark, keep those (one or two a side, the main facade \
        and the entrances first) with save_street_photo; a kept photo comes back with everything outside the frame painted \
        black, so look at it and drop_reference any whose frame holds another building.
           c. satellite_view: the roofs from straight above with the OSM outlines and a grid in metres (the recipe's x \
        and y): the roof shapes, ridges, domes and lanterns, the courtyards, where the parts stand.
           d. find_commons_photos again for what these do not show: the whole from afar, the roofs at a slant (aerial, \
        drone), the details that make it recognisable (a sculpture, a portal).
        Keep 5 to 9 good ones in all. The web (WebSearch, WebFetch) only when these give nothing.
        3. Write its recipe with set_recipe, then compare: compare_with_photo for each kept street photo shows the model \
        rendered from the photo's own camera beside it, so what differs is plain (count the columns and the windows, \
        check the roof's shape and height, the entrances, the colours); render_views for the whole and from above; \
        render_from for a look from any place. Correct the recipe and compare again, until the shapes agree.
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
