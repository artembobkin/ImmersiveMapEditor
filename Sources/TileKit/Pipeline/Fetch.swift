import Foundation
import Geometry

/// Takes the source data of map tiles into tiles/<z>/<x>/<y>/osm/:
///
///   osm.bin    every OSM element in the tile plus a margin, with the full
///              geometry of the multipolygons that reach in, cut from the
///              OSM extract of the data folder that holds the tile
///              (`OsmExtract`, sources/osm/*.osm.pbf, downloaded by the user
///              from Geofabrik or elsewhere) and kept in TileKit's binary
///              (OsmCache)
///   tile.json  the tile's bounds, its Mercator centre and scale, and where
///              and when its OSM was taken
///
/// No public API is asked (the user, 2026-11-21: before, Overpass's public
/// servers, overloaded and down half the time). A tile no extract holds is
/// refused, the way to get one said. The OSM on disk is kept unless asked
/// to take it again, so the sources stay fixed while the style is worked out.
public enum Fetch {
    static func longitudeOfColumn(_ c: Double, _ z: Int) -> Double { c / pow(2, Double(z)) * 360 - 180 }

    /// The tile's edges, its Mercator centre, the tile units a metre takes
    /// there (as the engine's baker computes them) and the box taken around it.
    static func describe(z: Int, x: Int, y: Int, margin: Double) -> [String: Any] {
        let south = latitudeOfRow(Double(y + 1), z), north = latitudeOfRow(Double(y), z)
        let west = longitudeOfColumn(Double(x), z), east = longitudeOfColumn(Double(x + 1), z)
        let lat = latitudeOfRow(Double(y) + 0.5, z), lon = longitudeOfColumn(Double(x) + 0.5, z)
        let upm = pow(2, Double(z)) * tileExtent / (earthCircumference * cos(lat * .pi / 180))
        // The margin in degrees at the centre's scale.
        let dlat = margin / 111320, dlon = margin / (111320 * cos(lat * .pi / 180))
        return [
            "tile": ["z": z, "x": x, "y": y],
            "bounds": ["south": south, "west": west, "north": north, "east": east],
            "centre": ["latitude": lat, "longitude": lon],
            "units_per_metre": upm,
            "size_m": tileExtent / upm,
            "margin_m": margin,
            "fetch_bounds": ["south": south - dlat, "west": west - dlon, "north": north + dlat, "east": east + dlon],
        ]
    }

    static func box(_ info: [String: Any]) -> OsmExtract.Box {
        let b = info["fetch_bounds"] as! [String: Double]
        return OsmExtract.Box(south: b["south"]!, west: b["west"]!, north: b["north"]!, east: b["east"]!)
    }

    static func summary(_ elements: [[String: Any]]) -> [String: Any] {
        var kinds: [String: Int] = [:]
        for e in elements { kinds[e["type"] as? String ?? "?", default: 0] += 1 }
        let tagged = elements.compactMap { $0["tags"] as? [String: String] }
        func count(_ f: ([String: String]) -> Bool) -> Int { tagged.filter(f).count }
        return [
            "elements": kinds,
            "buildings": count { $0["building"] != nil },
            "building_parts": count { $0["building:part"] != nil },
            "with_height": count { $0["height"] != nil && ($0["building"] != nil || $0["building:part"] != nil) },
            "with_levels": count { $0["building:levels"] != nil },
            "with_roof_shape": count { $0["roof:shape"] != nil },
            "highways": count { $0["highway"] != nil },
            "trees": count { $0["natural"] == "tree" },
            "water": count { $0["natural"] == "water" || $0["waterway"] != nil },
        ]
    }

    /// Takes one tile's OSM unless it is on disk (or `force`), and writes
    /// its tile.json.
    public static func tile(_ paths: WorkspacePaths, z: Int, x: Int, y: Int, margin: Double = 100, force: Bool = false) throws {
        let failed = try tiles(paths, z: z, tiles: [(x, y)], margin: margin, force: force)
        if let first = failed.first { throw PipelineError(first.reason) }
    }

    /// Takes the OSM of every tile that has none on disk (all of them with
    /// `force`), the tiles cut from the same extracts cut together, each
    /// extract read once for all of them. The tiles no extract holds are
    /// left and returned with the reason; the others are taken.
    @discardableResult
    public static func tiles(_ paths: WorkspacePaths, z: Int, tiles: [(Int, Int)], margin: Double = 100,
                             force: Bool = false) throws -> [(tile: String, reason: String)] {
        let (extracts, unreadable) = OsmExtract.all(paths)
        for name in unreadable { print("[osm] \(name) in sources/osm is no OSM PBF file: skipped") }
        var failed: [(tile: String, reason: String)] = []
        var groups: [[URL]: (sources: [OsmExtract], tiles: [(x: Int, y: Int, info: [String: Any])])] = [:]
        for (x, y) in tiles {
            let name = "\(z)/\(x)/\(y)"
            let folder = paths.tileData(z: z, x: x, y: y)
            let info = describe(z: z, x: x, y: y, margin: margin)
            if Osm.isFetched(folder) && !force {
                if tiles.count == 1 { print("[osm] \(name): on disk, kept") }
                continue
            }
            let sources = OsmExtract.sources(for: box(info), in: extracts)
            guard !sources.isEmpty else {
                let reason = extracts.isEmpty
                    ? "no OSM extract in the data folder's sources/osm: download the region of \(name) as .osm.pbf (download.geofabrik.de) into it"
                    : "no OSM extract in sources/osm holds \(name) (\(extracts.map(\.name).joined(separator: ", ")) do not): download its region as .osm.pbf into it"
                print("[osm] \(reason)")
                failed.append((name, reason))
                continue
            }
            groups[sources.map(\.url), default: (sources, [])].tiles.append((x, y, info))
        }
        for (_, group) in groups.sorted(by: { $0.key.map(\.path).joined() < $1.key.map(\.path).joined() }) {
            print("[osm] \(group.tiles.count) tile\(group.tiles.count == 1 ? "" : "s") from " + group.sources.map(\.name).joined(separator: " and "))
            let cut = try OsmExtract.cut(group.tiles.map { box($0.info) }, from: group.sources)
            if cut.missing.ways + cut.missing.nodes > 0 {
                print("[osm] WARN \(cut.missing.ways) ways and \(cut.missing.nodes) nodes of the multipolygons reaching in are in no extract: "
                      + "cut at the edge of their region, a lake or a bay across the border may be open. The extract of the region beside it, "
                      + "put into sources/osm, gives them")
            }
            for (tile, elements) in zip(group.tiles, cut.elements) {
                try save(paths, z: z, x: tile.x, y: tile.y, info: tile.info, elements: elements, sources: group.sources)
            }
        }
        return failed
    }

    /// A tile's elements kept as its osm.bin, with its tile.json.
    static func save(_ paths: WorkspacePaths, z: Int, x: Int, y: Int, info: [String: Any], elements: Osm.Elements,
                     sources: [OsmExtract]) throws {
        let folder = paths.tileData(z: z, x: x, y: y)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        // The data as of the oldest extract's date.
        let taken = sources.compactMap(\.timestamp).min().map { iso.string(from: $0) }
        let names = sources.map(\.name).joined(separator: ", ")
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(OsmCache.json))
        OsmCache.write(elements, folder: folder, stamp: "\(names) \(taken ?? "undated") \(iso.string(from: Date()))")
        // Read back as every reader will: the binary written is the one there.
        let kept = try OsmCache.elements(in: folder)
        var info = info
        let summary = summary(kept.overpass)
        info["osm"] = [
            "source": names,
            "fetched": iso.string(from: Date()).replacingOccurrences(of: "Z", with: "+00:00"),
            "timestamp": taken.map { $0 as Any } ?? NSNull(),
            "extract": sources.map { ["file": $0.name, "south": $0.south, "west": $0.west, "north": $0.north, "east": $0.east] as [String: Any] },
            "summary": summary,
            "attribution": "© OpenStreetMap contributors, ODbL",
        ]
        try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: folder.appendingPathComponent("tile.json"))
        print(String(format: "[tile] %d/%d/%d: %.1f m across, ", z, x, y, info["size_m"] as! Double) + "\(summary["elements"] as? [String: Int] ?? [:])")
    }
}
