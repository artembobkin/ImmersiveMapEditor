import Foundation
import Geometry

/// A landmark's recipe: what its stylized low-poly model is made of, in a
/// few architectural words, written by hand or by an agent (Claude) from
/// the landmark's OSM buildings and photos; LandmarkGenerator builds the
/// model from it, so every landmark comes out in one style and the palette.
/// It is `recipe.json` in the landmark's folder (tiles/<z>/<x>/<y>/
/// landmarks/<id>/). Places are metres east and north of the landmark's
/// centre (landmark.json's `centre`), heights metres above the ground,
/// colours the palette's landmark colours by name (lm_white, lm_cream,
/// lm_ochre, lm_red, lm_rose, lm_green, lm_dark_green, lm_gold, lm_stone,
/// lm_dark).
///
///   {"version": 1,
///    "masses": [{"id": "body", "outline": "way/123" | "polygon": [[x, y], ...],
///                "base": 0, "top": 23, "colour": "lm_cream",
///                "plinth": {"height": 1.5, "colour": "lm_stone"},
///                "cornice": {"height": 0.8, "depth": 0.5, "colour": "lm_white"},
///                "windows": {"storeys": 3, "spacing": 3.5, "width": 1.4, "height": 2.4,
///                            "arched": false, "colour": "lm_dark"},
///                "roof": {"shape": "flat" | "gabled" | "hipped" | "pyramidal" | "dome"
///                                  | "onion" | "spire" | "mansard",
///                         "height": 6, "colour": "lm_green"}}],
///    "features": [{"kind": "colonnade", "from": [x, y], "to": [x, y], "base": 1.5,
///                  "height": 15, "columns": 8, "radius": 0.7, "colour": "lm_white"},
///                 {"kind": "pediment", "from": [x, y], "to": [x, y], "base": 18,
///                  "height": 4, "depth": 2, "colour": "lm_cream"},
///                 {"kind": "statue", "at": [x, y], "base": 23, "height": 5, "width": 3,
///                  "colour": "lm_dark"},
///                 {"kind": "box", "polygon": [[x, y], ...], "base": 0, "top": 2,
///                  "colour": "lm_stone"},
///                 {"kind": "steps", "from": [x, y], "to": [x, y], "depth": 4,
///                  "height": 1.5, "count": 5, "colour": "lm_stone"}]}
///
/// A mass's outline is an OSM element of the landmark (its outer ring) or a
/// polygon of its own; a pediment and a colonnade stand along the line from
/// `from` to `to`, a pediment reaching `depth` to its right (the outside of
/// an outline wound counter-clockwise).
public struct LandmarkRecipe: Codable {
    public var version = 1
    public var masses: [Mass] = []
    public var features: [Feature] = []

    public struct Mass: Codable {
        public var id: String?
        public var outline: String?
        public var polygon: [[Double]]?
        public var base: Double = 0
        public var top: Double
        public var colour: String = "lm_cream"
        public var plinth: Band?
        public var cornice: Band?
        public var windows: Windows?
        public var roof: Roof?
    }

    public struct Band: Codable {
        public var height: Double
        public var depth: Double?
        public var colour: String?
    }

    public struct Windows: Codable {
        public var storeys: Int
        public var spacing: Double = 3.5
        public var width: Double = 1.4
        public var height: Double = 2.2
        public var arched: Bool?
        public var colour: String?
    }

    public struct Roof: Codable {
        public var shape: String
        public var height: Double?
        public var colour: String?
    }

    public struct Feature: Codable {
        public var kind: String
        public var from: [Double]?
        public var to: [Double]?
        public var at: [Double]?
        public var polygon: [[Double]]?
        public var base: Double?
        public var top: Double?
        public var height: Double?
        public var depth: Double?
        public var width: Double?
        public var radius: Double?
        public var columns: Int?
        public var count: Int?
        public var colour: String?
    }

    public init() {}

    public static func read(_ url: URL) throws -> LandmarkRecipe {
        try JSONDecoder().decode(LandmarkRecipe.self, from: Data(contentsOf: url))
    }

    public func write(_ url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url)
    }
}

/// A landmark's OSM buildings as landmark.json holds them, in metres around
/// its centre: what a recipe's outlines refer to and what a starter recipe
/// is made from.
public struct LandmarkSource {
    public struct Building {
        public let osm: String
        public let part: Bool
        public let tags: [String: String]
        /// Its polygons, each its outer ring then its holes, in metres east
        /// and north of the centre.
        public let polygons: [[[P2]]]
        public let base: Double
        public let height: Double?
    }

    public let name: String
    /// Longitude and latitude.
    public let centre: (Double, Double)
    public let buildings: [Building]

    public init(_ url: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        name = json["name"] as? String ?? ""
        let c = json["centre"] as? [Double] ?? [0, 0]
        centre = (c[0], c[1])
        let k = cos(c[1] * .pi / 180) * 111_320.0
        func metres(_ p: [Double]) -> P2 { P2((p[0] - c[0]) * k, (p[1] - c[1]) * 110_574) }
        buildings = (json["buildings"] as? [[String: Any]] ?? []).map { b in
            let outline = b["outline"] as? [[[[Double]]]] ?? []
            return Building(osm: b["osm"] as? String ?? "", part: b["part"] as? Bool ?? false,
                            tags: b["tags"] as? [String: String] ?? [:],
                            polygons: outline.map { $0.map { ring in Array(ring.dropLast()).filter { $0.count >= 2 }.map(metres) } },
                            base: (b["min_height_m"] as? NSNumber)?.doubleValue ?? 0,
                            height: (b["height_m"] as? NSNumber)?.doubleValue)
        }
    }

    /// An outline's outer ring by its OSM id: its largest polygon's.
    public func ring(_ osm: String) -> [P2]? {
        buildings.first { $0.osm == osm }?.polygons.max { abs(signedArea($0[0])) < abs(signedArea($1[0])) }?[0]
    }

    /// A first recipe from OSM alone: a mass for every part (or outline when
    /// there are no parts) from its base to its height, its roof by
    /// roof:shape, its colours the palette's landmark colours nearest to
    /// building:colour and roof:colour, windows by its levels.
    public func starterRecipe() -> LandmarkRecipe {
        let parts = buildings.filter(\.part)
        var r = LandmarkRecipe()
        r.masses = (parts.isEmpty ? buildings : parts).map { b in
            let top = b.height ?? (b.part ? 10 : 12)
            var m = LandmarkRecipe.Mass(id: b.osm, outline: b.osm, base: b.base, top: max(top, b.base + 0.5),
                                        colour: Self.landmarkColour(b.tags["building:colour"]) ?? "lm_cream")
            if let shape = b.tags["roof:shape"], shape != "flat" {
                m.roof = .init(shape: shape, height: length(b.tags["roof:height"]),
                               colour: Self.landmarkColour(b.tags["roof:colour"]) ?? "lm_green")
            }
            if let levels = length(b.tags["building:levels"]), levels >= 1, top - b.base > 4 {
                m.windows = .init(storeys: Int(levels))
            }
            return m
        }
        return r
    }

    /// The palette's landmark colour nearest to an OSM colour (a name or
    /// #hex), nil without one.
    static func landmarkColour(_ value: String?) -> String? {
        guard let value = value?.lowercased(), !value.isEmpty else { return nil }
        let named: [String: String] = ["white": "#FFFFFF", "beige": "#E8D6B2", "cream": "#F0E2C0", "yellow": "#E8C860",
                                       "orange": "#E39A50", "red": "#B54A3C", "brown": "#8A5A3C", "pink": "#E0A0A0",
                                       "green": "#5E8C74", "darkgreen": "#3E5E52", "gold": "#D8A93F", "grey": "#A8A8A8",
                                       "gray": "#A8A8A8", "black": "#303030", "silver": "#C0C0C0", "blue": "#6080B0"]
        guard let hex = value.hasPrefix("#") ? value : named[value] else { return nil }
        let (r, g, b) = Palette.rgb(hex)
        return Palette.landmark.min { a, b2 in
            func d(_ h: String) -> Int { let (x, y, z) = Palette.rgb(h); return (x - r) * (x - r) + (y - g) * (y - g) + (z - b) * (z - b) }
            return d(a.1) < d(b2.1)
        }?.0
    }
}
