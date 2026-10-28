import Foundation
import Observation

/// The landmarks' agent: Claude Code (`claude -p`, on the user's
/// subscription, through the proxy of Settings) run in a landmark's folder
/// with the editor's modelling tools (LandmarkMCP) and web search, nothing
/// else: no shell, no file tools, and none of the user's CLAUDE.md files or
/// memory (ClaudeSettings.environment). It looks for freely licensed photos, writes
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
    static let work = ["rounds", "search", "views", "recipe.json", "model.glb", "agent.json"]

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

    /// A new attempt starts from OSM again: the rounds, the searches, the
    /// recipe, model and conversation of the last one go, the photos stay
    /// to be used again.
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
    func start(folder: URL, name: String, request: String?, console: BuildRunner, followUps: Int = 0) {
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
        // A new attempt: the references gathered first, with no agent (the
        // user, 2026-10-28), the agent started when they are in.
        if request == nil {
            Self.startOver(folder)
            modelChanged()
            running = true
            gather(folder: folder, console: console) { [weak self] in
                guard let self else { return }
                self.running = false
                self.launch(claude, folder: folder, name: name, request: nil, console: console, followUps: followUps)
            }
            return
        }
        launch(claude, folder: folder, name: name, request: request, console: console, followUps: followUps)
    }

    /// The references of a landmark gathered by the editor itself (its
    /// --gather-references, the same code the agent's tools run), its
    /// report in the console; then `done`.
    private func gather(folder: URL, console: BuildRunner, done: @escaping @MainActor () -> Void) {
        console.append("Gathering the references: the street photos of every facade, the satellite view, Commons.")
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--gather-references", folder.path]
        p.environment = ClaudeSettings.environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            console.append("Cannot gather the references: \(error.localizedDescription)")
            done()
            return
        }
        process = p
        Task {
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines where !line.hasPrefix("signed ") {
                    console.append("  " + line)
                }
            } catch {}
            p.waitUntilExit()
            process = nil
            done()
        }
    }

    private func launch(_ claude: URL, folder: URL, name: String, request: String?, console: BuildRunner, followUps: Int) {
        var args = ["-p", request ?? Self.firstRequest(name), "--output-format", "stream-json", "--verbose",
                    "--tools", "WebSearch,WebFetch",
                    "--allowedTools", "WebSearch,WebFetch,mcp__landmark",
                    "--permission-mode", "dontAsk",
                    "--strict-mcp-config", "--mcp-config", Self.mcpConfig(folder),
                    "--append-system-prompt", Self.system]
        if let model = UserDefaults.standard.string(forKey: ClaudeSettings.modelKey), !model.isEmpty {
            args += ["--model", model]
        }
        // The safety stop on the turns: the plan fits in well under it.
        let turns = ClaudeSettings.maxTurns(facades: LandmarkMCP.Server.facadeCount(folder))
        if turns > 0 { args += ["--max-turns", "\(turns)"] }
        if let effort = UserDefaults.standard.string(forKey: ClaudeSettings.effortKey), !effort.isEmpty {
            args += ["--effort", effort]
        }
        if request != nil, let session = Self.conversation(folder) {
            args += ["--resume", session]
        } else {
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

    /// What the editor asks when the user wants the facades reviewed on the
    /// final model (not asked on its own since 2026-10-28: the plan ends
    /// with the build of the fixes).
    static func reviewRequest(_ due: [String]) -> String {
        "Review the facades on the final model: \(due.joined(separator: ", ")). review_facade each: the model beside "
            + "its best photo. Count what the photo shows against the model, fix what differs in one build, then end with "
            + "your summary, a line for each facade: what its photo shows and what the model has."
    }

    func stop() { process?.terminate() }

    /// The first request: the brief with the plan. Every landmark is
    /// modelled in full detail (the user, 2026-10-28: no levels).
    static func firstRequest(_ name: String) -> String {
        let level = """
            DETAIL: everything that reads from across the street: every mass of the building with its own roof, \
            the windows with the real storeys and rhythm of each facade (arched where they are arched), every entrance with \
            its portal, the plinth, string courses, the cornice with its depth, pilasters and columns where the facade has \
            them, balustrades and parapets, the sculpture, chimneys and roof lanterns, the attic and its windows. Model from \
            shapes what the words do not cover (a balustrade of cylinders in a row, a rusticated base as thin boxes, a \
            moulding as a loft). Up to 60 000 triangles (set_recipe tells the count).
            """
        return """
        Make the stylized low-poly model of the landmark "\(name)" (its folder is the working directory).
        \(level)
        The plan, and the budget: one build of the whole from the references, one build of the fixes its comparisons \
        show, a summary. Four tool calls; two builds. Work from what each call returns; do not ask for more pictures \
        than it gives.
        1. get_landmark, then list_references. The references are gathered for you before you start, and this shows \
        them: the best street photo of each facade (Mapillary, the landmark framed in red on each by the camera's pose; \
        kept in a folder for each facade, its best one to three in best/, the others in other/, all by name: \
        north-facade/best/photo-03.jpg, the path to give show_reference, compare_with_photo and drop_reference), the \
        satellite view (the roofs from straight above with the OSM outlines and a grid in metres, the recipe's x and y: \
        the roof shapes, ridges, domes and lanterns, the courtyards, where the parts stand), and from Wikimedia Commons a \
        view of the whole and one from above when it has them. If it shows nothing, gather_references. Nothing else to \
        search for.
        A wall is one wall (the user, 2026-10-28): the building's walls are its OSM outline, and each stretch of them \
        belongs to one mass. A building of parts with different heights, windows or roofs is the one outline cut into \
        them (cuts: a line through the outline and the side to keep; the rest of it minus the parts), never a polygon of \
        your own drawn along the outline, which the build refuses. A polygon only for what OSM has no outline of (a \
        tower on the roof, a drum, a porch), clear of the walls. Tidiness before likeness: a toy is symmetrical, one \
        rhythm of windows a wall in one grid with its pilasters and bands; where the photos show irregularity, draw the \
        regular version of it.
        2. The build: write the whole recipe with set_recipe from these pictures, every facade from its best photo: \
        the masses and their roofs, the windows of each facade in their rhythm, the entrances with their portals, the \
        cornice, the plinth, the relief (pilasters, bands), the sculpture that makes it recognisable; the walls' colours \
        from the photos and the roofs' colours satellite_view read, in the palette's words. The build comes back with the \
        model rendered beside the best photo of every facade from that photo's own camera, and beside the satellite view \
        from above: that is your review. Count what each photo shows against the model (columns, windows, storeys, \
        arches, entrances, the cornice, the relief, the roof, the colours).
        3. The fixes: one set_recipe with everything that differed. It comes back beside the best photo of every facade \
        it changed. No further build unless something is plainly wrong (a mass missing, a roof of the wrong shape).
        \(ClaudeSettings.emphasis != "off" ? """
        4. What makes it recognisable: the one or two things a person points at from afar (a sign, a tower, a dome, a \\
        statue, a star, a portico), never more. First ask yourself: you may know this place by its name and its OSM tags \\
        (the quadriga over the Bolshoi's portico, the star in a ring on Detsky Mir's corner). If you know it, just model \\
        it from what you know, placed by the satellite view, and open a photo only if you want to, when you lack its \\
        place or size. \\
        \(ClaudeSettings.emphasis == "photos" ? "Only when you do not know the building, look along the roof and at the corners of the whole-building photo for what stands there. " : "If you do not know the building, leave this step out: no photos for it. ")\\
        Model each in full in the build of the fixes, a sign as a text shape \\
        on its frame of boxes, a star as a statue of shape star (in a ring shape where it has one), and mark it \\
        "emphasis": true: the generator draws it larger than life, as a cartoon map does.
        5.
        """ : "4.") End with a short summary: a line for each facade, what its photo shows and what the model has; then what you \
        were not sure of.
        """
    }

    /// The MCP server of the modelling tools: the editor itself, for this folder.
    static func mcpConfig(_ folder: URL) -> String {
        var server: [String: Any] = ["command": Bundle.main.executableURL!.path, "args": ["landmark-mcp", folder.path]]
        var env: [String: String] = [:]
        let token = ClaudeSettings.mapillaryToken
        if !token.isEmpty { env["MAPILLARY_TOKEN"] = token }
        if !env.isEmpty { server["env"] = env }
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
            let effort = UserDefaults.standard.string(forKey: ClaudeSettings.effortKey).flatMap { $0.isEmpty ? nil : ", effort \($0)" } ?? ""
            return Event(text: "Claude started (\(json["model"] as? String ?? "?")\(effort)), tools: \(tools)")
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
                let all = texts.joined(separator: "\n").split(separator: "\n").map(String.init)
                let first = all.first ?? ""
                if r["is_error"] as? Bool == true { return "  ✗ \(first.prefix(300))" }
                guard !first.isEmpty else { return nil }
                // The first line of a result, and the generator's physical
                // warnings whole: the user watches those too.
                var shown = ["  \(first.prefix(200))"]
                if let k = all.firstIndex(where: { $0.hasPrefix("NOT PHYSICAL") }) {
                    shown += all[k...].map { "  ⚠ \($0.prefix(300))" }
                }
                return shown.joined(separator: "\n")
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
