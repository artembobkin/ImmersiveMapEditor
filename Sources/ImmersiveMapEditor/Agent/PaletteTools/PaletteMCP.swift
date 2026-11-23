import Foundation
import TileKit

/// The palette agent's tools, an MCP server on stdio (`ImmersiveMapEditor
/// palette-mcp DATA_FOLDER`, set up in the data folder's `agent/palette/`
/// by `AgentSetup.preparePalette`): a palette of the data folder made to fit
/// a city with the agent (the user, 2026-11-22: the Palettes tab's colours
/// for one's own city, made with an agent, and the editor showing each
/// change as it lands, `Session.watchFolder`). The tools:
///
/// - `list_palettes`, `get_palette`: the palettes kept, and one's colours
///   by group with what each paints, set or default;
/// - `create_palette`: a copy of another under a new name;
/// - `set_colours`: colours set, reset, and the city's own landmark
///   colours added, written at once (`PaletteStore`);
/// - `show_palette`: the palette drawn, facades and swatches (`PaletteSheet`);
/// - `city_photos`: Mapillary's street photos around a point of the city
///   (`PaletteMCP+City`), to see its facades and roofs.
///
/// Nothing outside the data folder's palettes is changed, and no tile is
/// told to use a palette: that stays the user's choice in the editor.
enum PaletteMCP {
    static func run(root: URL) -> Never {
        let store = PaletteStore(paths: WorkspacePaths(root: root.standardizedFileURL))
        let work = store.paths.root.appendingPathComponent("agent").appendingPathComponent("palette")
        let channel = MCPChannel()
        channel.serve { m in
            guard !channel.answerProtocol(m, tools: tools), let id = m["id"] else { return }
            let params = m["params"] as? [String: Any] ?? [:]
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                channel.reply(MCPChannel.result(id, try call(params["name"] as? String ?? "", args, store: store, work: work)))
            } catch {
                channel.reply(MCPChannel.failure(id, "\(error)"))
            }
        }
        exit(0)
    }

    static func call(_ name: String, _ args: [String: Any], store: PaletteStore, work: URL) throws -> [[String: Any]] {
        switch name {
        case "list_palettes":
            return [MCPChannel.text(list(store))]
        case "get_palette":
            return [MCPChannel.text(describe(try palette(args, store)))]
        case "create_palette":
            return [MCPChannel.text(try create(args, store))]
        case "set_colours":
            let (said, palette) = try setColours(args, store)
            return [MCPChannel.text(said)] + (try sheet(palette, work: work))
        case "show_palette":
            return try sheet(try palette(args, store), work: work)
        case "city_photos":
            return try cityPhotos(args, work: work)
        default:
            throw MCPChannel.Failure("no tool \(name)")
        }
    }

    /// The palette an argument names.
    static func palette(_ args: [String: Any], _ store: PaletteStore) throws -> Palette.File {
        let name = args["name"] as? String ?? ""
        guard let palette = store.read(name) else {
            throw MCPChannel.Failure("no palette \"\(name)\": one of " + store.names.joined(separator: ", "))
        }
        return palette
    }

    static func list(_ store: PaletteStore) -> String {
        let tiles = store.tilesByPalette, standard = store.defaultName
        return store.names.map { name in
            var line = "- \(name)"
            if let p = store.read(name) { line += ": \(p.colours.count) colours set over the defaults, \(p.extra.count) landmark colours added" }
            if name == standard { line += "; the data folder's, for every tile that remembers none" }
            if let t = tiles[name] { line += "; remembered by \(t.count) tile\(t.count == 1 ? "" : "s")" }
            return line
        }.joined(separator: "\n")
    }

    /// What each group paints, as the agent is told it.
    static let groupNotes = [
        "Roads and ground": "the roadway, kerbs and paint, paving, grass, trees, and the ordinary buildings' roofs (roof sloped, roof_flat flat)",
        "Walls": "the ordinary buildings' walls, every house of a tile: plaster_a, plaster_b and plaster_c the plaster family most houses take, brick, modern (glass and panel blocks), box (a building that is no typical house); each gets its lit, side and shade tones and its windows' tones derived",
        "Props": "construction sites and street furniture",
        "Landmarks": "the colours the landmarks' recipes paint with, by name: a model built is painted in them, so a change repaints every landmark of a tile built with this palette; lm_glass and lm_sky_glass are fixed",
    ]

    static func describe(_ palette: Palette.File) -> String {
        var lines = ["Palette \(palette.name). Hex as drawn: the engine shows these bytes raw."]
        for (group, colours) in Palette.defaults {
            lines.append("")
            lines.append("\(group): \(groupNotes[group] ?? "")")
            for (key, standard) in colours {
                if let set = palette.colours[key] { lines.append("  \(key) \(set) (set; default \(standard))") } else { lines.append("  \(key) \(standard)") }
            }
            if group == "Landmarks" {
                for (key, hex) in palette.extra { lines.append("  \(key) \(palette.colours[key] ?? hex) (added by this palette)") }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func create(_ args: [String: Any], _ store: PaletteStore) throws -> String {
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard PaletteStore.isName(name) else { throw MCPChannel.Failure("give name: a palette's name, a city or a style, no slash") }
        guard store.read(name) == nil else { throw MCPChannel.Failure("\(name) is kept already: change it with set_colours") }
        let from = args["from"] as? String ?? store.defaultName ?? "Common"
        guard let source = store.read(from) else { throw MCPChannel.Failure("no palette \"\(from)\" to copy: one of " + store.names.joined(separator: ", ")) }
        try store.write(Palette.File(name: name, colours: source.colours, extra: source.extra))
        return "\(name) made, a copy of \(from). The editor lists it; the user chooses which tiles use it."
    }

    static func setColours(_ args: [String: Any], _ store: PaletteStore) throws -> (String, Palette.File) {
        var palette = try palette(args, store)
        let given = args["colours"] as? [String: Any] ?? [:]
        let resets = args["reset"] as? [String] ?? []
        guard !given.isEmpty || !resets.isEmpty else { throw MCPChannel.Failure("give colours ({\"plaster_a\": \"#E8D2A6\"}) or reset ([\"plaster_a\"])") }
        let known = Set(Palette.defaults.flatMap { $0.colours.map(\.0) })
        var said: [String] = [], refused: [String] = []
        for (raw, value) in given.sorted(by: { $0.key < $1.key }) {
            let key = raw.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
            guard let hex = hex(value as? String ?? "") else { refused.append("\(raw): not a hex colour, #RRGGBB"); continue }
            if known.contains(key) {
                palette.colours[key] = hex
                said.append("\(key) \(hex)")
            } else if let i = palette.extra.firstIndex(where: { $0.0 == key }) {
                palette.extra[i].1 = hex
                said.append("\(key) \(hex)")
            } else if key.hasPrefix("lm_"), key.count > 3, !key.contains("."), key != "lm_glass", key != "lm_sky_glass" {
                palette.extra.append((key, hex))
                said.append("\(key) \(hex) added")
            } else {
                refused.append("\(raw): no such colour (a new landmark colour is named lm_<material>)")
            }
        }
        for raw in resets {
            let key = raw.lowercased()
            if palette.extra.contains(where: { $0.0 == key }) {
                palette.extra.removeAll { $0.0 == key }
                palette.colours[key] = nil
                said.append("\(key) taken out")
            } else if palette.colours.removeValue(forKey: key) != nil {
                said.append("\(key) back to its default")
            } else {
                refused.append("\(raw): neither set nor added")
            }
        }
        if !said.isEmpty { try store.write(palette) }
        let text = (said.isEmpty ? "Nothing changed." : "Set in \(palette.name): " + said.joined(separator: ", ") + ". The editor shows it now; a tile paints with it when built again.")
            + (refused.isEmpty ? "" : "\nRefused: " + refused.joined(separator: "; "))
        return (text, palette)
    }

    /// "#e8d2a6", "E8D2A6" as "#E8D2A6"; nil for anything else.
    static func hex(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces).uppercased()
        let h = v.hasPrefix("#") ? v : "#" + v
        return h.count == 7 && Int(h.dropFirst(), radix: 16) != nil ? h : nil
    }

    /// The palette drawn, as an image for the agent.
    static func sheet(_ palette: Palette.File, work: URL) throws -> [[String: Any]] {
        Palette.apply(palette.colours, extra: palette.extra, name: palette.name)
        let folder = work.appendingPathComponent("sheets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(palette.name + ".png")
        try PaletteSheet.draw(title: "\(palette.name)   (• set over the default)", set: Set(palette.colours.keys), to: file)
        return [["type": "image", "data": try Data(contentsOf: file).base64EncodedString(), "mimeType": "image/png"]]
    }

    static let nameArgument: [String: Any] = ["type": "string", "description": "The palette's name, as list_palettes names it."]

    static let tools: [[String: Any]] = [
        ["name": "list_palettes",
         "description": "The palettes of the data folder: how many colours each sets and adds, which is the data folder's (for the tiles that remember none), how many tiles remember each.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "get_palette",
         "description": "Every colour of a palette by group, with what the group paints, each set by the palette or its default.",
         "inputSchema": ["type": "object", "properties": ["name": nameArgument], "required": ["name"]]],
        ["name": "create_palette",
         "description": "A new palette, a copy of another (the data folder's unless from is given), under a name: the city's.",
         "inputSchema": ["type": "object", "properties": [
             "name": ["type": "string", "description": "The new palette's name: the city, or a style."],
             "from": ["type": "string", "description": "The palette to copy; the data folder's by default."]],
                         "required": ["name"]]],
        ["name": "set_colours",
         "description": "Colours of a palette set, saved at once (the editor shows them as they land), and the palette drawn after. Any colour get_palette names; a new landmark colour, the city's own material, is added by naming it lm_<material> (lm_terracotta). reset puts a colour back to its default, or takes an added one out.",
         "inputSchema": ["type": "object", "properties": [
             "name": nameArgument,
             "colours": ["type": "object", "description": "Colour name to hex, {\"plaster_a\": \"#E8D2A6\", \"lm_terracotta\": \"#B5653F\"}.",
                         "additionalProperties": ["type": "string"]],
             "reset": ["type": "array", "items": ["type": "string"], "description": "Colour names back to their defaults, or added ones taken out."]],
                         "required": ["name"]]],
        ["name": "show_palette",
         "description": "The palette drawn: each wall and landmark colour as a small facade of its lit, side and shade tones with a window, the others as swatches, labelled.",
         "inputSchema": ["type": "object", "properties": ["name": nameArgument], "required": ["name"]]],
        ["name": "city_photos",
         "description": "Mapillary's street photos around a point of the city, the newest, nine on one sheet with their dates: its facades, roofs and ground as they look. A few points, the old centre and the ordinary streets, tell the city's colours.",
         "inputSchema": ["type": "object", "properties": [
             "lat": ["type": "number"], "lon": ["type": "number"],
             "radius": ["type": "number", "description": "Metres around the point, 500 by default, 1500 at most."]],
                         "required": ["lat", "lon"]]],
    ]
}
