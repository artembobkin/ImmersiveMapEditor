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

    /// A list left out is empty: the synthesized decoding wanted every key
    /// whatever its default, and a recipe with no features was refused
    /// (the user, 2026-11-03: a turn of Claude's lost to it).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        masses = try c.decodeIfPresent([Mass].self, forKey: .masses) ?? []
        features = try c.decodeIfPresent([Feature].self, forKey: .features) ?? []
        shapes = try c.decodeIfPresent([Shape].self, forKey: .shapes) ?? []
    }

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
        /// A text's thickness.
        public var depth: Double?
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
        /// A text shape's letters.
        public var text: String?
        /// What makes the building recognisable from afar: drawn a size up
        /// by the generator (the user, 2026-10-28, after Zenly).
        public var emphasis: Bool?
        /// A glass shape's glazing: the colour of its frame (lm_dark unless
        /// given) and the spacing of its mullions.
        public var frame: String?
        public var mullions: Double?
        /// An upright box or a prism takes entrances and windows as a mass
        /// does, cut into its walls (the user, 2026-11-02: a podium's doors
        /// drawn as dark plates stood proud of it).
        public var doors: [Door]?
        public var windows: Windows?
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
        /// A glass mass's glazing: the colour of its frame (lm_dark unless
        /// given) and the spacing of its mullions.
        public var frame: String?
        public var mullions: Double?
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
        /// high above the plinth's top, glass at its back, no portal.
        public var sill: Double?
        /// A glazed entrance: a door with glass at its back. A window's
        /// back is glass whatever this says.
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
        /// The sills' and surrounds' colour, lm_white unless given.
        public var colour: String?
        /// A surround (jambs and a lintel standing a little proud) around
        /// every window, with its sill: on unless false, for a plain
        /// modern wall.
        public var surround: Bool?
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
        /// What makes the building recognisable from afar: drawn a size up.
        public var emphasis: Bool?
    }

    public init() {}

    /// Glass, for a modern building: the map's one glass, and the bright
    /// glass of a skyscraper. Not sided like a wall, flat.
    public static let glassColours = ["lm_glass", "lm_sky_glass"]
    static let colourList = Palette.landmark.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        + ", and for glass: lm_glass (a curtain wall, a glazed roof), lm_sky_glass (the bright glass of a tower)"

    public static func read(_ url: URL) throws -> LandmarkRecipe {
        try JSONDecoder().decode(LandmarkRecipe.self, from: Data(contentsOf: url))
    }

    public func write(_ url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url)
    }
}
