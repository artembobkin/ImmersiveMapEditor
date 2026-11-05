import Foundation
import Observation
import TileKit

/// The landmarks' agent: Claude Code (`claude -p`, on the user's
/// subscription, through the proxy of Settings) run in a landmark's folder
/// with the editor's modelling tools (LandmarkMCP) and web search, nothing
/// else: no shell, no file tools, and none of the user's CLAUDE.md files or
/// memory (ClaudeSettings.environment). It looks for freely licensed photos, writes
/// the landmark's recipe, renders it and corrects it. Its conversation is
/// kept (agent.json in the folder), so the user can go on asking.
///
/// The runs, one a landmark (`LandmarkRun`), are jobs of the session's
/// pool (`JobPool`): several landmarks are modelled at once, up to
/// `ClaudeSettings.atOnce`, the rest queued (the user, 2026-11-01), the
/// references gathered for one landmark at a time, Claude in parallel. A
/// run's log is its own console, shown at the foot of the window while its
/// landmark is open; a finished run stays until the landmark is modelled
/// again, so its summary can be read. This is the view of the pool as
/// landmarks: the runs by landmark, started, stopped and counted.
@Observable
@MainActor
final class LandmarkAgent {
    private let pool: JobPool
    /// Called with the landmark's id when a run may have built a new model.
    var modelChanged: (String) -> Void = { _ in }

    init(pool: JobPool) { self.pool = pool }

    var runs: [LandmarkRun] { pool.jobs.compactMap { $0 as? LandmarkRun } }

    /// The runs still queued or going.
    var active: [LandmarkRun] { runs.filter { $0.state.active } }
    /// Whether any landmark is queued or being modelled.
    var running: Bool { !active.isEmpty }

    /// The runs in the order a list shows them: going, then queued, then
    /// ended, the latest first.
    var listed: [LandmarkRun] {
        let keyed = runs.enumerated().map { i, r -> (LandmarkRun, (Int, Double, Int)) in
            (r, r.state.running ? (0, 0, i) : r.state.active ? (1, 0, i) : (2, -(r.ended?.timeIntervalSinceReferenceDate ?? 0), i))
        }
        return keyed.sorted { $0.1 < $1.1 }.map(\.0)
    }
    /// The run of a landmark, its last one.
    func run(of id: String) -> LandmarkRun? { runs.last { $0.id == id } }
    /// Whether the landmark's own run is queued or going.
    func isActive(_ id: String) -> Bool { run(of: id)?.state.active ?? false }

    /// What the pool is doing, for the status line: nothing when idle.
    var status: String? {
        let going = active.filter { $0.state.running }.count, queued = active.count - going
        guard going + queued > 0 else { return nil }
        return "Claude: \(going) modelling" + (queued > 0 ? ", \(queued) queued" : "")
    }

    /// Queues the landmark: a new attempt from OSM, or a request to go on
    /// with its conversation. A landmark already queued or going is left
    /// alone; a finished run of it is replaced.
    func start(tile: TileKey, id: String, folder: URL, name: String, request: String?) {
        guard !isActive(id) else { return }
        let run = LandmarkRun(tile: tile, id: id, name: name, folder: folder, request: request)
        run.modelChanged = { [weak self] in self?.modelChanged(id) }
        pool.add(run)
    }

    func stop(_ id: String) { run(of: id)?.stop() }

    func stopAll() { for run in active { run.stop() } }

    /// The pool asked to start what it can: after At once is changed.
    func pump() { pool.pump() }

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
    static let work = ["rounds", "search", "views", "recipe.json", "model.glb", "agent.json", "agent.log", LandmarkRun.streamName, LandmarkRun.pidName]

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

    static func conversation(_ folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("agent.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["session"] as? String
    }



    /// What the editor asks when the user wants the facades reviewed on the
    /// final model (not asked on its own since 2026-10-28: the plan ends
    /// with the build of the fixes).
    static func reviewRequest(_ due: [String]) -> String {
        "Review the facades on the final model: \(due.joined(separator: ", ")). review_facade each: the model beside "
            + "its best photo. Count what the photo shows against the model, fix what differs in one build, then end with "
            + "your summary, a line for each facade: what its photo shows and what the model has."
    }


    /// The first request: the brief with the plan. Every landmark is
    /// modelled in full detail (the user, 2026-10-28: no levels), and
    /// `fine` asks for the ornament too, with five fix builds (the user,
    /// 2026-11-05: the Painted Ladies as plain gabled boxes).
    static func firstRequest(_ name: String, monument: Bool = false, fine: Bool = false) -> String {
        if monument { return monumentRequest(name) }
        let level = """
            DETAIL: everything that reads from across the street: every mass of the building with its own roof, \
            the windows with the real storeys and rhythm of each facade (arched where they are arched), every entrance with \
            its portal, the plinth, string courses, the cornice with its depth, pilasters and columns where the facade has \
            them, balustrades and parapets, the sculpture, chimneys and roof lanterns, the attic and its windows. Model from \
            shapes what the words do not cover (a balustrade of cylinders in a row, a rusticated base as thin boxes, a \
            moulding as a loft). Up to \(fine ? "150 000" : "60 000") triangles (set_recipe tells the count).
            """ + (fine ? """

            FINE DETAIL, asked for this landmark: the ornament too, everything a person sees from the pavement, modelled \
            from shapes at its real size and placed from the walls' corners: every bay window as a prism (or a cylinder, \
            or a corner turret with its cone) standing proud of the wall with its own windows, base and cornice; the \
            porch with its columns, its arch or pediment, its balustrade and the stairs with their rails; the brackets \
            under the cornice and under the bays as rows of small boxes; the window surrounds with their pediments and \
            hoods; the gable's trim along its edges and its finial; the balustrades as rows of cylinders between posts; \
            the string courses between the storeys; the base's rustication; the chimneys. Count the ornament of each \
            facade in its photo and give the model the same count.
            """ : "")
        let fixes = fine ? "five" : "three"
        return """
        Make the stylized low-poly model of the landmark "\(name)" (its folder is the working directory).
        \(level)
        The plan, and the budget: one build of the whole from the references, then builds of the fixes while the \
        comparisons still show something to fix, \(fixes) of them at most, each with everything that differed, and a \
        summary. A plain building takes two builds, a rich facade \(fine ? "all of them" : "four"); never a build for a detail alone, and stop as \
        soon as a build changes little. Work from what each call returns; do not ask for more pictures than it gives.
        1. get_landmark (the building, its walls' corners in metres, the recipe format), then list_references. The references are gathered for you before you start, and this shows \
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
        3. The fixes: a set_recipe with everything that differed, all of it in one build, never one thing at a time. It \
        comes back beside the best photo of every facade it changed: count again, and build again only while a photo \
        still shows something the model lacks (a bay, a balcony stack, a storey, a roof of another shape), \(fixes) fix \
        builds at most. When a build changes little, that is the end.
        \(ClaudeSettings.emphasis != "off" ? """
        4. What makes it recognisable: the one or two things a person points at from afar (a sculpture, a star, a cross, a ball finial: what stands free on the building), \\
        never more. The building's own body, a tower, a dome, a cone, a drum, a portico, a platform, lettering, is never one: it is given \\
        its real size in the recipe and drawn at it, emphasis on anything but a statue, a ring or a sphere ignored and said back with the build. First ask yourself: you may know this place by its name and its OSM tags \\
        (a quadriga over a theatre's portico, a star in a ring on a store's corner, a gilded flame on a monument's tip, a \\
        crescent over a dome). Any country, any age: the words are the same. If you know it, just model \\
        it from what you know, placed by the satellite view, and open a photo only if you want to, when you lack its \\
        place or size. \\
        \(ClaudeSettings.emphasis == "photos" ? "Only when you do not know the building, look along the roof and at the corners of the whole-building photo for what stands there. " : "If you do not know the building, leave this step out: no photos for it. ")\\
        Model each in full in the build of the fixes, a star as a statue of shape star (in a ring shape where it \\
        has one), and mark it "emphasis": true: the generator draws it \\(String(format: "%.2g", ClaudeSettings.exaggeration)) times its size, \\
        larger than life, as a cartoon map does. Lettering is never one of these: solid letters that really stand on \\
        the building (on its roof or its cornice) are a text shape at their real size; a shop's signboard, a banner or \\
        an advertisement is not modelled at all.
        5.
        """ : "4.") End with a short summary: a line for each facade, what its photo shows and what the model has; then what you \
        were not sure of.
        """
    }

    /// The first request for a monument (the user, 2026-11-05: a statue, a
    /// helicopter on a pedestal, a point in OSM with no outline): no walls,
    /// no facades, the thing itself from the photos around it.
    static func monumentRequest(_ name: String) -> String {
        """
        Make the stylized low-poly model of the monument "\(name)" (its folder is the working directory).
        It is a monument, not a building: a statue, a sculpture, a vehicle or a stone on a pedestal, a point in OSM \
        with no outline. DETAIL: what a person sees from the pavement: the pedestal with its steps and mouldings, and \
        the figure or the object on it with its real silhouette (a rider and a horse, a standing person, a helicopter \
        with its rotor, tail boom and skids, an obelisk with its tip), at its real size from the photos and OSM's height. \
        Up to 20 000 triangles (set_recipe tells the count).
        The plan, and the budget: one build from the references, then a build of the fixes while the comparisons still \
        show something to fix, two of them at most, and a summary. Work from what each call returns.
        1. get_landmark (the plot, the recipe format: the ring it gives is the plot round the point, not a wall, and \
        nothing of it is built), then list_references: the street photos round it from Mapillary, each the monument \
        framed in red, kept by the side of the plot they look at (north-facade/best/photo-03.jpg, the path to give \
        show_reference, compare_with_photo and drop_reference), the satellite view (its shadow and its base tell its \
        footprint and heading) and from Wikimedia Commons a view of the whole when it has one. If it shows nothing, \
        gather_references. Nothing else to search for.
        2. The build: set_recipe with no masses. The pedestal a box, a cylinder, a prism or a loft shape standing on \
        the ground at (0, 0), its real size; the figure on it a statue feature where one fits (figure, equestrian, \
        obelisk, cross, star, flame), marked "emphasis": true, since it is what stands free; otherwise the object \
        assembled from shapes at its real size (a loft or a sweep for a body, cylinders for booms and barrels, thin boxes \
        for blades, wings and plates, spheres), facing the heading the photos and the satellite view show. Colours in \
        the palette's words: bronze lm_dark, stone lm_stone, gilt lm_gold, a painted machine its own colours. The build \
        comes back rendered beside the best photo from each side, from that photo's own camera, and beside the \
        satellite view: that is your review. Count the parts and compare the proportions.
        3. The fixes: one set_recipe with everything that differed; build again only while a photo still shows \
        something the model lacks, two fix builds at most. End with a short summary: what the photos show, what the \
        model has, and what you were not sure of.
        """
    }

    /// The MCP server of the modelling tools: the editor itself, for this folder.
    static func mcpConfig(_ folder: URL, fine: Bool = false) -> String {
        var server: [String: Any] = ["command": Bundle.main.executableURL!.path, "args": ["landmark-mcp", folder.path]]
        var env: [String: String] = [:]
        if fine { env["LANDMARK_DETAIL"] = "fine" }
        let token = ClaudeSettings.mapillaryToken
        if !token.isEmpty { env["MAPILLARY_TOKEN"] = token }
        env.merge(ClaudeSettings.generatorEnvironment) { _, new in new }
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
                // A refused recipe's problems, each (the user, 2026-11-03:
                // "Not built, the recipe has problems:" and nothing after).
                if first.hasPrefix("Not built") {
                    shown += all.dropFirst().prefix(12).map { "  ✗ \($0.prefix(300))" }
                }
                // What the generator ignored of a recipe it built (emphasis
                // where it is not for), said back after the summary.
                if first.hasPrefix("Built") {
                    shown += all.dropFirst().filter { $0.contains("ignored") }.prefix(6).map { "  ⚠ \($0.prefix(300))" }
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
