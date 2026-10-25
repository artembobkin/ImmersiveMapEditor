/// muv-osm's `Surface` (`surface.rs`) with its `SurfaceKind`, `Smoothness`
/// (`lanes/lane.rs`), and `Colour` (`colour.rs`): a `#rgb` or `#rrggbb`
/// value, or a CSS colour name. serde writes an RGB colour as `#` and its
/// three channels in hexadecimal without padding, as Muv does.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public enum SurfaceKind: Int, SimpleEnum, Sendable {
    case paved, asphalt, chipseal, concrete, concreteLanes, concretePlates, pavingStones, sett, unhewnCobblestone,
         cobblestone, brick, metal, wood, steppingStones, rubber
    case unpaved, compacted, fineGravel, gravel, rock, pebblestone, ground, dirt, grass, grassPaver, metalGrid, mud,
         sand, woodchips, snow, ice, salt
    case clay, tartan, artificialTurf, acrylic, carpet

    public static let rustNames = [
        "Paved", "Asphalt", "Chipseal", "Concrete", "ConcreteLanes", "ConcretePlates", "PavingStones", "Sett",
        "UnhewnCobblestone", "Cobblestone", "Brick", "Metal", "Wood", "SteppingStones", "Rubber",
        "Unpaved", "Compacted", "FineGravel", "Gravel", "Rock", "Pebblestone", "Ground", "Dirt", "Grass", "GrassPaver",
        "MetalGrid", "Mud", "Sand", "Woodchips", "Snow", "Ice", "Salt",
        "Clay", "Tartan", "ArtificialTurf", "Acrylic", "Carpet",
    ]
    public static let osmNames = makeOsmNames([.concreteLanes: ["concrete:lanes"], .concretePlates: ["concrete:plates"],
                                        .dirt: ["dirt", "earth"]])
}

public enum Smoothness: Int, SimpleEnum, Sendable {
    case excellent, good, intermediate, bad, veryBad, horrible, veryHorrible, impassable

    public static let rustNames = ["Excellent", "Good", "Intermediate", "Bad", "VeryBad", "Horrible", "VeryHorrible",
                            "Impassable"]
    public static let osmNames = makeOsmNames()
}

/// `Colour`: serde's untagged enum, an RGB string or the name's variant.
public enum Colour: Equatable, Sendable, MuvSerialize {
    case rgb(UInt8, UInt8, UInt8)
    case named(Int)

    static let names = [
        "Aliceblue", "Antiquewhite", "Aqua", "Aquamarine", "Azure", "Beige", "Bisque", "Black", "Blanchedalmond",
        "Blue", "Blueviolet", "Brown", "Burlywood", "Cadetblue", "Chartreuse", "Chocolate", "Coral", "Cornflowerblue",
        "Cornsilk", "Crimson", "Cyan", "Darkblue", "Darkcyan", "Darkgoldenrod", "Darkgray", "Darkgreen", "Darkgrey",
        "Darkkhaki", "Darkmagenta", "Darkolivegreen", "Darkorange", "Darkorchid", "Darkred", "Darksalmon",
        "Darkseagreen", "Darkslateblue", "Darkslategray", "Darkslategrey", "Darkturquoise", "Darkviolet", "Deeppink",
        "Deepskyblue", "Dimgray", "Dimgrey", "Dodgerblue", "Firebrick", "Floralwhite", "Forestgreen", "Fuchsia",
        "Gainsboro", "Ghostwhite", "Gold", "Goldenrod", "Gray", "Green", "Greenyellow", "Grey", "Honeydew", "Hotpink",
        "Indianred", "Indigo", "Ivory", "Khaki", "Lavender", "Lavenderblush", "Lawngreen", "Lemonchiffon", "Lightblue",
        "Lightcoral", "Lightcyan", "Lightgoldenrodyellow", "Lightgray", "Lightgreen", "Lightgrey", "Lightpink",
        "Lightsalmon", "Lightseagreen", "Lightskyblue", "Lightslategray", "Lightslategrey", "Lightsteelblue",
        "Lightyellow", "Lime", "Limegreen", "Linen", "Magenta", "Maroon", "Mediumaquamarine", "Mediumblue",
        "Mediumorchid", "Mediumpurple", "Mediumseagreen", "Mediumslateblue", "Mediumspringgreen", "Mediumturquoise",
        "Mediumvioletred", "Midnightblue", "Mintcream", "Mistyrose", "Moccasin", "Navajowhite", "Navy", "Oldlace",
        "Olive", "Olivedrab", "Orange", "Orangered", "Orchid", "Palegoldenrod", "Palegreen", "Paleturquoise",
        "Palevioletred", "Papayawhip", "Peachpuff", "Peru", "Pink", "Plum", "Powderblue", "Purple", "Red", "Rosybrown",
        "Royalblue", "Saddlebrown", "Salmon", "Sandybrown", "Seagreen", "Seashell", "Sienna", "Silver", "Skyblue",
        "Slateblue", "Slategray", "Slategrey", "Snow", "Springgreen", "Steelblue", "Tan", "Teal", "Thistle", "Tomato",
        "Turquoise", "Violet", "Wheat", "White", "Whitesmoke", "Yellow", "Yellowgreen",
    ]
    private static let byName = OsmNames(names.indices.map { ($0, names[$0]) })

    /// `FromOsmStr for Colour`.
    static func fromOsmStr(_ s: String) -> Colour? {
        if let hex = s.rustStripPrefix("#") { return rgb(withoutPrefix: hex) }
        return byName.parse(s).map { .named($0) }
    }

    /// `Colour::parse_tags`: the `colour` subtag.
    static func parseTags<T: Taglike>(_ tags: T) -> Colour? {
        tags.getValue("colour").flatMap(fromOsmStr)
    }

    private static func hexDigit(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    /// `Rgb::from_osm_str_without_prefix`.
    private static func rgb(withoutPrefix s: String) -> Colour? {
        let b = Array(s.utf8)
        let d = b.map(hexDigit)
        if d.contains(where: { $0 == nil }) { return nil }
        let v = d.map { $0! }
        switch v.count {
        case 3: return .rgb(v[0] * 17, v[1] * 17, v[2] * 17)
        case 6: return .rgb(v[0] * 16 + v[1], v[2] * 16 + v[3], v[4] * 16 + v[5])
        default: return nil
        }
    }

    public func muvJSON() -> MuvJSON {
        switch self {
        case let .rgb(r, g, b): return .string("#" + String(r, radix: 16) + String(g, radix: 16) + String(b, radix: 16))
        case .named(let i): return .string(Self.names[i])
        }
    }
}

/// `Surface`: a kind and maybe a colour.
public struct Surface: Equatable, Sendable, MuvSerialize {
    public var kind: SurfaceKind
    public var colour: Colour?

    init(kind: SurfaceKind, colour: Colour? = nil) {
        self.kind = kind
        self.colour = colour
    }

    /// `FromOsm for Surface`.
    static func fromOsm<T: Taglike>(_ tag: T) -> Surface? {
        guard let kind = tag.value.flatMap(SurfaceKind.fromOsmStr) else { return nil }
        return Surface(kind: kind, colour: Colour.parseTags(tag))
    }

    public func muvJSON() -> MuvJSON { .object(["kind": kind.muvJSON(), "colour": colour.muvJSON()]) }
}
