import Foundation
import Geometry

/// The style's palette, after the maps it learns from: buildings are a calm
/// ground of one family of warm plaster under one cool roof colour, windows
/// a darker tone of their wall, and the colour is left to the landmarks.
/// Hex as it shows on screen: the engine samples the texture raw, so these
/// bytes are the colours drawn. The order is the order of the cells.
///
/// The tables below are the defaults. The data folder's `config/palette.json`
/// (`{"colours": {"plaster_a": "#…"}}`, edited in the editor's Style view)
/// replaces any of them by name: `load` reads it, `apply` puts the colours
/// in and derives every tone again.
public enum Palette {
    public private(set) static var base: [(String, String)] = [
        // The roads: cool roadway, a light kerb, off-white and yellow paint
        ("asphalt", "#6E6A7D"), ("kerb", "#A6A3B1"), ("marking", "#ECE8E1"), ("marking_yellow", "#E8C24A"),
        // Kept so the cells of every other colour stay where they were
        ("pavement", "#C9C4C7"), ("paving", "#DDD6D0"), ("paving_edge", "#C3BAB4"), ("sett", "#9B9691"),
        ("sett_edge", "#86817D"), ("grass", "#8CC56B"), ("crown_a", "#5DAE4B"), ("crown_b", "#7BC25A"),
        ("crown_c", "#4C9A45"), ("crown_a_shade", "#4A9440"), ("crown_b_shade", "#62A84A"),
        ("crown_c_shade", "#3D7F3A"), ("trunk", "#8A5A3C"),
        // Roofs: one cool colour, lighter on the slopes that face the sun
        ("roof", "#7F8AA6"), ("roof_flat", "#9AA2B8"), ("rim", "#F6EEDF"), ("plinth", "#A0958F"),
        ("earth", "#A69886"), ("lamp_light", "#F7EDCB"),
        // Landmark placeholders, until a landmark is made by hand
        ("clay", "#E6E0D6"), ("clay_roof", "#C9C1B5"),
    ]

    /// Walls: the plaster family, brick, modern, and the plain box of a
    /// building that is not a typical house. Each takes a shade per side of
    /// the sun, and so do its window reveals and its glass.
    public private(set) static var walls: [(String, String)] = [
        ("plaster_a", "#EFD3A1"), ("plaster_b", "#E9C48C"), ("plaster_c", "#F2DDB8"), ("brick", "#C8735A"),
        ("modern", "#D9D6D0"), ("box", "#D4D0CA"),
    ]

    /// The compass bearing the sun comes from. The engine's sun must come
    /// from here too.
    public static let sunFrom = 225.0

    /// The side of a building facing the sun is lighter and warmer, the far
    /// side darker and cooler: a factor per channel.
    public static let sides: [(String, (Double, Double, Double))] = [
        ("lit", (1.03, 1.0, 0.97)), ("side", (0.91, 0.91, 0.93)), ("shade", (0.80, 0.81, 0.88)),
    ]
    static let roofSides: [(String, (Double, Double, Double))] = [
        ("lit", (1.08, 1.08, 1.06)), ("side", (1.0, 1.0, 1.0)), ("shade", (0.9, 0.9, 0.95)),
    ]
    static let reveal = 0.82    // a window's reveals against its wall
    static let glass = 0.52     // a window's glass against its wall
    /// A landmark's window: its glass a light pane of sky (the toy's window,
    /// the user, 2026-10-27: a window lighter than its wall reads as a
    /// window from afar, a dark one as a hole), its reveal darker than an
    /// ordinary building's, so the pane has a rim.
    static let landmarkGlass = "#D3E4F0"
    static let landmarkReveal = 0.72

    /// The things of a construction site and the street, sided like walls.
    public private(set) static var props: [(String, String)] = [
        ("fence", "#5E8B78"), ("fence_post", "#45695B"), ("fence_rail", "#ECE9E1"), ("crane", "#F2B53A"),
        ("machine", "#EE9F32"), ("machine_dark", "#4B4752"), ("cabin", "#4F84C4"), ("cabin_b", "#E6E3DD"),
        ("cab_glass", "#6E8DA6"), ("concrete", "#B3AEA8"), ("sand", "#D9B57C"), ("frame", "#5B5E6C"),
        ("sign", "#3D6FB8"), ("bench", "#9A6E4A"), ("soil", "#8E7D6B"), ("gravel", "#A3A2A6"), ("pipe", "#6C7A8E"),
        ("pallet", "#B48C5F"),
    ]

    /// The landmarks' own colours, the same in every tile: a model is
    /// repainted in these. Sided like walls, with window tones.
    public private(set) static var landmark: [(String, String)] = [
        ("lm_white", "#EEE8DC"), ("lm_cream", "#E8D6B2"), ("lm_ochre", "#E3BE7E"), ("lm_red", "#B54A3C"),
        ("lm_rose", "#D39A8A"), ("lm_green", "#5E8C74"), ("lm_dark_green", "#3E5E52"), ("lm_gold", "#D8A93F"),
        ("lm_stone", "#ABA7A3"), ("lm_dark", "#4B4752"), ("lm_roof", "#CBC5BC"),
    ]

    /// The groups of the colours that can be set: their names and defaults.
    public static let defaults: [(group: String, colours: [(String, String)])] = [
        ("Roads and ground", base), ("Walls", walls), ("Props", props), ("Landmarks", landmark),
    ]

    /// The colours set over the defaults, by name.
    public private(set) static var overrides: [String: String] = [:]

    /// Puts colours in over the defaults (an empty dictionary: the defaults
    /// alone) and derives every tone again.
    public static func apply(_ colours: [String: String]) {
        overrides = colours.filter { Int($0.value.dropFirst(), radix: 16) != nil && $0.value.count == 7 }
        func set(_ table: [(String, String)]) -> [(String, String)] { table.map { ($0.0, overrides[$0.0] ?? $0.1) } }
        base = set(defaults[0].colours)
        walls = set(defaults[1].colours)
        props = set(defaults[2].colours)
        landmark = set(defaults[3].colours)
        all = derive()
        names = Set(all.map(\.0))
        hexByName = Dictionary(all, uniquingKeysWith: { a, _ in a })
    }

    /// The palette file of a data folder.
    public static func file(_ paths: WorkspacePaths) -> URL { paths.config.appendingPathComponent("palette.json") }

    /// Reads the data folder's palette, if it has one, over the defaults.
    public static func load(_ paths: WorkspacePaths) {
        guard let data = try? Data(contentsOf: file(paths)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let colours = json["colours"] as? [String: String] else { return apply([:]) }
        apply(colours)
    }

    /// Writes the colours set to the data folder's palette and applies them.
    public static func save(_ colours: [String: String], _ paths: WorkspacePaths) throws {
        apply(colours)
        try FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        let json: [String: Any] = ["colours": overrides, "note": "The colours set over the editor's defaults, by name: edited in the Style view."]
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: file(paths))
    }

    /// Every colour name the palette has.
    public private(set) static var names: Set<String> = Set(all.map(\.0))

    /// A colour's hex by its name: a cell's, or a wall tone's family
    /// ("lm_cream.reveal": its side tone) for a preview.
    public static func hex(_ name: String) -> String? {
        if let h = hexByName[name] { return h }
        return hexByName[name + ".side"] ?? hexByName[name + ".lit"]
    }
    private(set) static var hexByName: [String: String] = Dictionary(all, uniquingKeysWith: { a, _ in a })

    public static func rgb(_ hex: String) -> (Int, Int, Int) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = Int(h, radix: 16) ?? 0
        return ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    }

    static func tone(_ hex: String, _ f: (Double, Double, Double)) -> String {
        let (r, g, b) = rgb(hex)
        func c(_ v: Int, _ k: Double) -> Int { min(255, Int((Double(v) * k + 0.5).rounded(.down))) }
        return String(format: "#%02X%02X%02X", c(r, f.0), c(g, f.1), c(b, f.2))
    }

    static func tone(_ hex: String, _ k: Double) -> String { tone(hex, (k, k, k)) }

    /// Every colour by name, in cell order.
    public private(set) static var all: [(String, String)] = derive()

    static func derive() -> [(String, String)] {
        var out = base
        let glassTint = (glass * 0.92, glass * 0.96, glass * 1.12)
        for (wall, hex) in walls {
            for (side, f) in sides {
                out.append(("\(wall).\(side)", tone(hex, f)))
                out.append(("\(wall).reveal.\(side)", tone(tone(hex, reveal), f)))
                out.append(("\(wall).glass.\(side)", tone(tone(hex, glassTint), f)))
            }
        }
        let roof = base.first { $0.0 == "roof" }?.1 ?? "#7F8AA6"
        for (side, f) in roofSides { out.append(("roof.\(side)", tone(roof, f))) }
        for (name, hex) in props {
            for (side, f) in sides { out.append(("\(name).\(side)", tone(hex, f))) }
        }
        for (name, hex) in landmark {
            for (side, f) in sides {
                out.append(("\(name).\(side)", tone(hex, f)))
                out.append(("\(name).reveal.\(side)", tone(tone(hex, landmarkReveal), f)))
                out.append(("\(name).glass.\(side)", tone(landmarkGlass, f)))
            }
        }
        out.append(("lm_glass", "#7E9DB0"))
        out.append(("lm_sky_glass", "#4E92D6"))
        return out
    }

    /// The face shade: a colour's name with a step of shade, "name~2". A
    /// face shut in by what is around it (a window's reveal, a ceiling
    /// under a portico, the wall behind columns) takes its colour a step
    /// or more darker, and a little cooler, flat over the face (the user,
    /// 2026-10-28: depth from the building's own geometry, in the style's
    /// flat colours). `step` is how much darker each step is.
    public static let shadeSteps = 3
    /// The quantum of a face's shade: a factor on its colour is rounded to
    /// a multiple of this, and the cell named by the multiple, "name~7".
    public static let shadeQuantum = 1.0 / 32
    public static func shaded(_ name: String, factor: Double, coarse: Int = 1) -> String {
        // `coarse` merges levels, 2 for every second one, when a tile would
        // need more cells than the largest palette holds.
        var level = Int(((1 - min(max(factor, 0), 1)) / shadeQuantum).rounded())
        level = (level + coarse / 2) / max(1, coarse) * max(1, coarse)
        return level > 0 ? "\(name)~\(level)" : name
    }
    public static func hexShaded(_ name: String) -> String? {
        guard let tilde = name.lastIndex(of: "~") else { return hexAny(name) }
        guard let level = Int(name[name.index(after: tilde)...]), let base = hexAny(String(name[..<tilde])) else { return nil }
        let k = max(0, 1 - shadeQuantum * Double(level))
        return tone(base, (k * 0.98, k, k * 1.04))
    }

    /// A colour's hex by any name the build uses: a cell's, or a sided
    /// name without its side ("lm_cream.reveal": the plain reveal tone), for
    /// the faces painted flat when the side tones are off.
    public static func hexAny(_ name: String) -> String? {
        if let h = hexByName[name] { return h }
        let parts = name.split(separator: ".").map(String.init)
        guard let base = parts.first else { return nil }
        let table = walls + props + landmark + base_
        guard var hex = table.first(where: { $0.0 == base })?.1 else { return hex(name) }
        let lm = landmark.contains { $0.0 == base }
        if parts.contains("reveal") { hex = tone(hex, lm ? landmarkReveal : reveal) }
        if parts.contains("glass") { hex = lm ? landmarkGlass : tone(hex, (glass * 0.92, glass * 0.96, glass * 1.12)) }
        return hex
    }
    private static var base_: [(String, String)] { base }

    /// A sided name without its side: "lm_cream.lit" is "lm_cream".
    public static func plain(_ name: String) -> String {
        for side in ["lit", "side", "shade"] where name.hasSuffix("." + side) { return String(name.dropLast(side.count + 1)) }
        return name
    }

    /// Which side of the sun a face looks to, from its normal in plan.
    public static func side(_ nx: Double, _ ny: Double) -> String {
        let l = hypot(nx, ny)
        if l < 1e-6 { return "lit" }
        let b = sunFrom * .pi / 180
        let d = (nx * sin(b) + ny * cos(b)) / l
        return d > 0.35 ? "lit" : d < -0.35 ? "shade" : "side"
    }
}

/// The palette as an image: flat colours in 16 px cells from the top left.
/// No patterns: a pattern repeated over a large surface shimmers in the
/// distance. UVs come out with V up (row 0 at V = 1), as the build has
/// them until the export turns them.
public final class PaletteTexture {
    public static let cell = 16
    /// 256 px, 256 cells: the base palette, every colour of `Palette.all`.
    /// A texture of the names a tile uses with their shade steps grows to
    /// 512 px when they are more than 256.
    public let size: Int
    public private(set) var pixels: [UInt8]           // RGB, row 0 on top
    public private(set) var flat: [String: (Double, Double)] = [:]
    /// The name of each cell, in order.
    public let names: [String]

    /// The base palette: every colour, in `Palette.all`'s order, so a
    /// name's cell is the same in every build.
    public convenience init() { self.init(names: Palette.all.map(\.0)) }

    /// A palette of just these names (shaded names "name~k" among them,
    /// each k quanta darker), in the order given.
    public init(names: [String]) {
        let cell = PaletteTexture.cell
        let n = names.count <= 256 ? 256 : names.count <= 1024 ? 512 : 1024
        precondition(names.count <= (n / cell) * (n / cell), "too many colours for the palette: \(names.count)")
        size = n
        self.names = names
        pixels = [UInt8](repeating: 0, count: n * n * 3)
        let perRow = n / cell
        for (i, name) in names.enumerated() {
            let (r, c) = (i / perRow, i % perRow)
            let (cr, cg, cb) = Palette.rgb(Palette.hexShaded(name) ?? "#FF00FF")
            for y in (r * cell)..<((r + 1) * cell) {
                for x in (c * cell)..<((c + 1) * cell) {
                    let k = (y * n + x) * 3
                    pixels[k] = UInt8(cr); pixels[k + 1] = UInt8(cg); pixels[k + 2] = UInt8(cb)
                }
            }
            flat[name] = (Double(c * cell) + Double(cell) / 2, Double(r * cell) + Double(cell) / 2)
        }
    }

    public func has(_ name: String) -> Bool { flat[name] != nil }

    /// The UV of a colour's cell centre.
    public func uv(_ name: String) -> P2 {
        guard let (px, py) = flat[name] else { fatalError("no colour \(name) in the palette") }
        return P2(px / Double(size), 1 - py / Double(size))
    }

    /// The name of the cell a UV (V up) points into.
    public func name(at uv: P2) -> String? {
        let cell = PaletteTexture.cell, perRow = size / cell
        let c = Int(uv.x * Double(size)) / cell, r = Int((1 - uv.y) * Double(size)) / cell
        let i = r * perRow + c
        return i >= 0 && i < names.count ? names[i] : nil
    }
}
