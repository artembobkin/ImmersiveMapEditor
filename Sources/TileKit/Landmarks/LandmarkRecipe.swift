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
/// lm_dark, lm_roof).
///
///   {"version": 1,
///    "masses": [{"id": "body", "outline": "way/123" | "polygon": [[x, y], ...],
///                "cuts": [{"from": [x, y], "to": [x, y], "keep": [x, y]}], "minus": ["tower"],
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
///                 {"kind": "statue", "shape": "figure" | "horse" | "quadriga" | "equestrian" | "obelisk"
///                                             | "cross" | "star", "at": [x, y], "heading": 180,
///                  "base": 23, "pedestal": 1, "height": 5, "width": 3, "colour": "lm_dark"},
///                 {"kind": "box", "polygon": [[x, y], ...], "base": 0, "top": 2,
///                  "colour": "lm_stone"},
///                 {"kind": "steps", "from": [x, y], "to": [x, y], "depth": 4,
///                  "height": 1.5, "count": 5, "colour": "lm_stone"}],
///    "shapes": [{"kind": "box" | "cylinder" | "cone" | "sphere" | "dome" | "prism" | "loft", ...}]}
///
/// Shapes are free modelling (see `guide`): a box of a size, a cylinder or
/// cone of a radius and height, a sphere or dome of a radius, a prism of a
/// polygon with holes, a loft (a ring drawn toward its centre along a
/// profile of scale and rise), each at a place on a base, turned to a
/// heading and tipped by a pitch, and copied in a row (`repeat`) or around
/// a point (`around`).
///
/// A mass's outline is an OSM element of the landmark (its outer ring) or a
/// polygon of its own; a pediment and a colonnade stand along the line from
/// `from` to `to`, a pediment reaching `depth` to its right (the outside of
/// an outline wound counter-clockwise).
public struct LandmarkRecipe: Codable {
    public var version = 1
    public var masses: [Mass] = []
    public var features: [Feature] = []
    /// Free modelling: solids of simple shapes, where the words above do not
    /// describe the building.
    public var shapes: [Shape] = []

    public struct Shape: Codable {
        public var kind: String
        public var at: [Double]?
        public var base: Double?
        public var top: Double?
        /// A box: along its heading, across it, up.
        public var size: [Double]?
        public var radius: Double?
        public var radius_top: Double?
        public var height: Double?
        public var segments: Int?
        public var polygon: [[Double]]?
        public var outline: String?
        public var holes: [[[Double]]]?
        /// A loft's rings: scale toward the centre and rise, from the base up.
        public var profile: [[Double]]?
        /// A compass bearing the shape is turned to, and its tip forward.
        public var heading: Double?
        public var pitch: Double?
        public var colour: String?
        public var `repeat`: Repeat?
        public var around: Around?
    }

    public struct Repeat: Codable {
        public var count: Int
        /// Metres east, north and up between copies.
        public var step: [Double]
    }

    public struct Around: Codable {
        public var count: Int
        public var centre: [Double]
    }

    public struct Mass: Codable {
        public var id: String?
        public var outline: String?
        public var polygon: [[Double]]?
        /// The outline cut by lines: the mass is the part on the `keep` side
        /// of every cut, so two parts of one building share its walls and
        /// meet on the cut (the user, 2026-10-28: a wall is one wall).
        public var cuts: [Cut]?
        /// The ids of masses taken out of this one's footprint: the rest of
        /// an outline beside its cut parts.
        public var minus: [String]?
        public var base: Double = 0
        public var top: Double
        public var colour: String = "lm_cream"
        public var plinth: Band?
        public var cornice: Band?
        public var windows: Windows?
        public var roof: Roof?
        /// Entrances: recesses cut in the wall nearest each, with a portal.
        public var doors: [Door]?
        /// Vertical strips standing proud of the walls, between the windows.
        public var pilasters: Pilasters?
        /// String courses: a band standing proud at every storey line.
        public var bands: Band?
    }

    /// A straight cut through an outline, and which side to keep.
    public struct Cut: Codable {
        public var from: [Double]
        public var to: [Double]
        public var keep: [Double]
    }

    public struct Door: Codable {
        public var at: [Double]
        public var width: Double?
        public var height: Double?
        public var depth: Double?
        public var arched: Bool?
        /// A frame around it standing proud, this wide; 0 for none.
        public var portal: Double?
        public var colour: String?
        /// A window at a place of its own instead of a door: its sill this
        /// high above the wall's foot, glass at its back, no portal.
        public var sill: Double?
        public var glass: Bool?
    }

    public struct Pilasters: Codable {
        public var spacing: Double
        public var width: Double?
        public var depth: Double?
        public var colour: String?
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
        /// A pitched roof's eaves beyond the wall (0.6 m unless given), with
        /// a fascia under them.
        public var overhang: Double?
        /// A flat roof's low wall around its edge.
        public var parapet: Double?
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
        /// A statue's shape, which way it faces (a compass bearing) and the
        /// pedestal under it.
        public var shape: String?
        public var heading: Double?
        public var pedestal: Double?
    }

    public init() {}

    /// Glass, for a modern building: the map's one glass, and the bright
    /// glass of a skyscraper. Not sided like a wall, flat.
    public static let glassColours = ["lm_glass", "lm_sky_glass"]
    static let colourList = Palette.landmark.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        + ", and for glass: lm_glass (a curtain wall, a glazed roof), lm_sky_glass (the bright glass of a tower)"

    /// The format and the style, as the landmarks' agent is told them.
    public static let guide = """
    THE RECIPE (recipe.json): a stylized low-poly model of the landmark, in one cartoon style shared by every landmark of the map. \
    You choose the words below; the generator builds the geometry, so keep to them. Places are metres east (x) and north (y) of the \
    landmark's centre, heights metres above the ground. Every colour is one of the palette's landmark colours by name: \
    \(colourList).

    {"version": 1,
     "masses": [{"id": "portico-base", "outline": "way/123"  (an OSM element of the landmark: its outer ring)
                   or "polygon": [[x, y], ...]  (a ring of your own, for a volume OSM does not draw),
                 "base": 0, "top": 23, "colour": "lm_cream",
                 "plinth": {"height": 1.5, "depth": 0.15, "colour": "lm_stone"},
                 "cornice": {"height": 0.8, "depth": 0.4, "colour": "lm_white"},
                 "windows": {"storeys": 3, "spacing": 3.5, "width": 1.4, "height": 2.4, "arched": false},
                 "doors": [{"at": [x, y], "width": 2.4, "height": 4, "depth": 0.6, "arched": true, "portal": 0.35, "colour": "lm_dark"},
                           {"at": [x, y], "sill": 9, "width": 1.6, "height": 2.8, "arched": true, "glass": true}],
                 "pilasters": {"spacing": 3.5, "width": 1.0, "depth": 0.3, "colour": "lm_white"},
                 "bands": {"height": 0.3, "depth": 0.15, "colour": "lm_white"},
                 "roof": {"shape": "flat|gabled|skillion|hipped|mansard|pyramidal|dome|onion|spire", "height": 6, "colour": "lm_stone",
                          "overhang": 0.6, "parapet": 1.0}}],
     "features": [{"kind": "colonnade", "from": [x, y], "to": [x, y], "base": 1.5, "height": 15, "columns": 8, "radius": 0.7, "colour": "lm_white"},
                  {"kind": "pediment", "from": [x, y], "to": [x, y], "base": 18, "height": 4, "depth": 2, "colour": "lm_cream"},
                  {"kind": "statue", "shape": "quadriga", "at": [x, y], "heading": 180, "base": 23, "pedestal": 1, "height": 5, "width": 8, "colour": "lm_dark"},
                  {"kind": "box", "polygon": [[x, y], ...], "base": 0, "top": 2, "colour": "lm_stone"},
                  {"kind": "steps", "from": [x, y], "to": [x, y], "depth": 4, "height": 1.5, "count": 5, "colour": "lm_stone"}]}

    - A wall is one wall. A building's walls are its OSM outline, and every stretch of them belongs to one mass: no two \
    masses may run along the same wall (a part drawn as its own polygon beside the outline's mass would put two grids \
    of windows on one wall; the build refuses it). A building of parts with different heights, windows or roofs is one \
    outline cut into them: a part is the outline with `cuts` (a straight line through it, from and to, and a point on \
    the side to `keep`; several cuts for a corner part), and the rest of the outline is the outline `minus` those parts' \
    ids. The parts meet on the cut and the generator joins them. A `polygon` of its own is only for what OSM has no \
    outline of (a tower on the roof, a dome's drum, a porch), and it must stand clear of the outline's walls or on its \
    own. The model is one shell: every mass and shape is a closed solid, and all of them are united. Masses that touch \
    must overlap: a tower sinks half a metre into its base, never with a slot between them (the generator sinks a \
    corner that stands on or near a neighbour's wall into it, but do not count on it). A mass is a prism of its outline from base to top, its walls in its colour, with an optional plinth and cornice band \
    standing proud, windows storey by storey on every wall long enough, and a roof on its top. A window is a recess cut \
    into the wall (the map's style): reveals and glass in tones of the wall, a light sill. Give windows only to a mass that \
    reads as storeys of windows, with the storeys and spacing the photos show. A window that the rows cannot place (one \
    between pilasters, a single large window, a window of its own above a door) is a door with a `sill` (metres above \
    the wall's foot) and `glass` true: cut in at that place, glass at its back, as the rows' windows are; from 10 m² (a shop front, a glazed \
    arch, a glass wall between piers) its back is the map's glass, lm_glass, which reads as glass from afar where a wall's dark tone reads as a hole. A door is an entrance cut into the wall \
    nearest its `at` (a point on or by that wall), deeper than a window, its leaf at the back and a portal standing proud \
    around it: every building has its entrances where the photos show them. Pilasters are vertical strips standing \
    proud of the walls (between the windows when they share the spacing); bands are string courses at the storey lines. \
    Give every size as the building has it: the generator draws the map's caricature itself, every cornice, band, pilaster, \
    portal, parapet and recess at least about half a metre to a metre, and windows a little larger, so a detail reads from afar. \
    A pitched roof has eaves 0.6 m beyond the walls with a fascia (`overhang` to change); a flat roof always gets a \
    parapet with a light rim (give `parapet` its height when the photos show a taller one). A flat roof's colour is the \
    map's own roof grey, lm_roof: leave it out unless satellite_view reads a colour of its own off the imagery (lm_green \
    or lm_dark_green green, lm_red red, lm_dark black); a pitched roof's colour is what the imagery reads (lm_stone grey \
    metal too), given for every mass: never a guess. A historic building never ends in a bare flat cap: a parapet, a balustrade of shapes, or a \
    pitched roof with its eaves, so the roof reads as a volume of its own. Gabled, skillion (one slope, \
    rising across the short side), hipped and mansard roofs rise over the outline's smallest rectangle (the ridge along its long side); dome, onion, spire and pyramidal draw the \
    outline in to a point, so give them a round or square outline. A roof's height defaults to the outline's size.
    - A statue is a sculpture by its shape: figure (a standing person), horse, quadriga (a chariot drawn by four horses, \
    as over a theatre's portico), equestrian (a rider on a horse), obelisk, cross (a church), star (a tower's). It faces \
    `heading` (a compass bearing: 0 north, 90 east, 180 south), stands at `at` on `base` (the top of the mass or pediment \
    under it) with an optional `pedestal`, `height` tall and about `width` wide. Use it for the sculpture that makes the \
    building recognisable, nothing else.
    - Where these words do not describe the building, model it yourself from shapes, as many as it takes:
      "shapes": [
       {"kind": "box", "at": [x, y], "base": 0, "size": [along, across, up], "heading": 0, "pitch": 0, "colour": "lm_stone"},
       {"kind": "cylinder", "at": [x, y], "base": 0, "radius": 1, "radius_top": 1, "height": 10, "segments": 16, "colour": "lm_white"},
       {"kind": "cone", "at": [x, y], "base": 30, "radius": 3, "height": 6, "segments": 8, "colour": "lm_green"},
       {"kind": "sphere", "at": [x, y], "base": 30, "radius": 2, "segments": 12, "colour": "lm_gold"},
       {"kind": "dome", "at": [x, y], "base": 30, "radius": 6, "segments": 16, "colour": "lm_green"},
       {"kind": "prism", "polygon": [[x, y], ...] or "outline": "way/123", "holes": [[[x, y], ...]], "base": 0, "top": 5, "colour": "lm_cream"},
       {"kind": "loft", "radius": 4, "segments": 16, or "polygon"/"outline", "base": 30, "profile": [[1, 0], [1.2, 0.5], [0.8, 3], [0, 5]], "colour": "lm_green"}]
      A shape stands at `at` (its centre in plan) on `base`, `heading` turns it (0 north, 90 east), `pitch` tips its top \
    forward (a cylinder with pitch 90 lies along its heading: a beam). A sphere stands on its base; a dome is a half \
    sphere, flat side down. A loft draws its ring toward its centre ring by ring, [scale, rise] from the base up: a drum \
    with a moulding, a vase, an onion, a tapering tower. `"repeat": {"count": 6, "step": [3.5, 0, 0]}` makes copies along \
    a step (metres east, north, up); `"around": {"count": 8, "centre": [x, y]}` makes copies turned around a point. Shapes \
    are solids: let them overlap, or sink one a little into what it stands on, rather than share a face exactly. Nothing \
    cuts a hole: an opening is a prism with holes, or a loft. Few large shapes before many small ones, and 8 to 16 segments.
    - A colonnade stands along the line from `from` to `to`, its columns evenly spaced, a beam on top. A pediment is a triangle \
    over the line, reaching `depth` to the line's right (looking from `from` to `to`): put it on a facade's line with the \
    outside on the right. Steps rise from the ground at `depth` to the right of the line up to `height` at the line.
    - The style: few large shapes over many small ones; the silhouette, proportions, the main colours and the few details \
    that make the building recognisable from a distance (a portico, a dome, a tower, a quadriga, a glass curtain wall, a \
    spire). The building can be of any kind and age: a church (drums with domes or onions, a cross on top), a tower (a tent \
    roof, a star), a palace, a station, a department store, a modern block of glass and stone (a mass in lm_glass with no \
    windows is a curtain wall), a monument (a pedestal and a statue). Model what is there. No textures, no fine \
    ornament. Windows only where the building reads as storeys of windows. Every model of the map looks of one family.
    - Everything is physical, as a building is, even where no photo shows it: steps lead up to a landing (a box or a \
    mass at their top height) that reaches the wall and the doors, the floor the portico's columns stand on; a colonnade \
    stands on a stylobate (a box) and carries its beam; a statue stands on a pedestal, a pediment or a roof; a balcony has \
    a floor; nothing floats and nothing ends in the air. set_recipe says what floats or leads nowhere: fix it before going on.
    - Use the OSM outlines where they are good. OSM heights can be wrong: trust the photos, and say so.
    """

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
            if let osm = b.tags["roof:shape"], case let shape = LandmarkGenerator.roofShape(osm: osm), shape != "flat" {
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
