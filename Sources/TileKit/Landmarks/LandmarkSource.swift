import Foundation
import Geometry

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
        /// A monument, not a building: a statue, a sculpture, a vehicle on a
        /// pedestal (the user, 2026-11-05).
        public let monument: Bool
        /// Mapped as a node: its polygon is the plot round it, `plotRadius`
        /// metres, not a wall.
        public let point: Bool
        public let plotRadius: Double?
    }

    public let name: String
    /// Whether the landmark is a monument (every building of it one).
    public var isMonument: Bool { !buildings.isEmpty && buildings.allSatisfy(\.monument) }
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
                            height: (b["height_m"] as? NSNumber)?.doubleValue,
                            monument: b["monument"] as? Bool ?? false, point: b["point"] as? Bool ?? false,
                            plotRadius: (b["plot_radius_m"] as? NSNumber)?.doubleValue)
        }
    }

    /// A courtyard: a ring in metres the building's parts enclose, open to
    /// the sky above its `floor`: the ground, or the roof of the part under
    /// it (the Hotel Moskva's garden lies on a 16 m podium, its wings around
    /// it from there up).
    public struct Courtyard {
        public let ring: [P2]
        public let floor: Double
        public var area: Double { abs(signedArea(ring)) }
        public var centre: P2 { ring.reduce(P2.zero, +) / Double(ring.count) }
    }

    /// The courtyards: the holes in the union of the footprints of the parts
    /// standing above each level (the parts when there are any, else the
    /// outlines), the level the ground and then every part's top in turn,
    /// a hole's floor the level it first opens at (gaps under 0.6 m between
    /// parts closed, a hole under 60 m² or narrower than 8 m, a light well
    /// between roof parts, left out, a hole found at one level not found
    /// again at the next). An OSM outline is one ring around the
    /// whole block, courtyard and all, and only its parts show the courtyard
    /// open (the user, 2026-11-03: the Hotel Moskva's courtyard roofed over
    /// by a mass of its outline from the ground to the cornice).
    public var courtyards: [Courtyard] {
        let parts = buildings.filter(\.part)
        let footprints = (parts.isEmpty ? buildings : parts)
        func shape(_ b: Building) -> [Geometry] {
            b.polygons.compactMap { rings -> Geometry? in
                guard let outer = rings.first, outer.count >= 3 else { return nil }
                return Geometry.polygon(outer + [outer[0]], holes: rings.dropFirst().filter { $0.count >= 3 }.map { $0 + [$0[0]] })
            }
        }
        let tallest = footprints.compactMap(\.height).max() ?? 0
        let levels = [0.0] + Set(footprints.compactMap(\.height)).sorted().filter { $0 < tallest - 3 }
        var found: [Courtyard] = []
        for level in levels {
            let above = footprints.filter { ($0.height ?? 0) > level + 0.5 }.flatMap(shape)
            guard !above.isEmpty else { continue }
            let joined = Geometry.unaryUnion(above).buffer(0.3, quadSegs: 1).buffer(-0.3, quadSegs: 1)
            for hole in joined.polygons.flatMap(\.interiors) {
                let ring = Array(hole.dropLast())
                let open = Geometry.polygon(hole)
                guard abs(signedArea(ring)) >= 60, open.buffer(-4, quadSegs: 1).area > 0 else { continue }
                // The same courtyard opens wider at every level above its floor.
                guard !found.contains(where: { open.intersection(Geometry.polygon($0.ring + [$0.ring[0]])).area > open.area * 0.5 }) else { continue }
                found.append(Courtyard(ring: ring, floor: level))
            }
        }
        return found
    }

    /// An outline's outer ring by its OSM id: its largest polygon's.
    public func ring(_ osm: String) -> [P2]? {
        buildings.first { $0.osm == osm }?.polygons.max { abs(signedArea($0[0])) < abs(signedArea($1[0])) }?[0]
    }

    /// A first recipe from OSM alone: a mass for every part (or outline when
    /// there are no parts) from its base to its height, its roof by
    /// roof:shape, its colours the palette's landmark colours nearest to
    /// building:colour and roof:colour, windows by its levels.
    public static let starterMasses = 80

    public func starterRecipe() -> LandmarkRecipe {
        let parts = buildings.filter(\.part)
        var r = LandmarkRecipe()
        // A monument: a figure on a pedestal at the point, its height from
        // OSM, nothing of the plot (the user, 2026-11-05).
        if isMonument {
            let h = buildings.compactMap(\.height).max() ?? 6
            let json = """
            {"features": [{"kind": "statue", "shape": "figure", "at": [0, 0], "heading": 180, "base": 0, "pedestal": \(String(format: "%.1f", min(3, h * 0.4))), "height": \(String(format: "%.1f", max(1, h * 0.6))), "colour": "lm_dark", "emphasis": true}]}
            """
            return (try? JSONDecoder().decode(LandmarkRecipe.self, from: Data(json.utf8))) ?? r
        }
        // The largest `starterMasses` parts at most: St Basil's 514 made a
        // starter the agent's tool could not pass on (the user, 2026-11-04).
        let taken = (parts.isEmpty ? buildings : parts)
            .sorted { $0.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } > $1.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } }
            .prefix(Self.starterMasses)
        r.masses = taken.map { b in
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
