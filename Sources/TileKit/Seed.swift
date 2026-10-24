import Foundation
import Geometry

/// Seeds the road document of a range of tiles from osm2streets and OSM,
/// and writes what the editor shows under it. Every tile of the range must
/// be fetched. Writes:
///
///   data/regions/<range>/osm.json      the tiles' OSM merged, each element once
///   data/regions/<range>/streets/      osm2streets over all of it, once, so
///                                      junctions on a tile's edge come out the
///                                      same for the tiles on either side
///   data/regions/<range>/context.json  the editor's underlay: building
///                                      outlines, road centre lines, crossings
///                                      and bus stops, in lon and lat
///   roads/<range>.json                 the road document
///
/// A road document holds hand edits: it is not overwritten unless forced.
/// osm2streets is the one tool that is not Swift: a small Rust program in
/// tools/osm2streets_cli, built once with `cargo build --release`.
public enum Seed {
    static let margin = 80.0        // metres of streets around the range, within the fetched margin

    public static var cli: URL { pipelineRoot.appendingPathComponent("tools/osm2streets_cli/target/release/osm2streets-cli") }

    public static func run(z: Int, x0: Int, y0: Int, x1: Int, y1: Int, force: Bool = false) throws -> URL {
        let region = Region(z: z, x0: x0, y0: y0, x1: x1, y1: y1)
        let folder = pipelineRoot.appendingPathComponent("data/regions/\(region.name)")
        region.folder = folder
        let path = pipelineRoot.appendingPathComponent("roads/\(region.name).json")
        if FileManager.default.fileExists(atPath: path.path) && !force {
            throw PipelineError("roads/\(region.name).json exists and may hold hand edits: seed it again only when forced")
        }
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw PipelineError("build the osm2streets CLI first: (cd tools/osm2streets_cli && cargo build --release)")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let elements = try merge(region, folder)
        let streets = try streets(region, elements, folder)
        let osm = try Osm(region)
        let work = region.bounds.buffer(margin, join: .mitre)
        let doc = Roads.document(try Roads.seed(osm, streets: streets, work: work), region: region)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try doc.write(path)
        var kinds: [String: Int] = [:]
        for m in doc.markings { kinds[m.kind, default: 0] += 1 }
        print("roads/\(region.name).json: \(doc.areas.count) areas, markings \(kinds), \(doc.shelters.count) shelters")
        try context(osm, region, work, folder)
        return path
    }

    /// The tiles' osm.json as one, every element once.
    static func merge(_ region: Region, _ folder: URL) throws -> [[String: Any]] {
        var seen = Set<String>(), elements: [[String: Any]] = []
        for (x, y) in region.tiles {
            let url = Fetch.folder(z: region.z, x: x, y: y).appendingPathComponent("osm.json")
            guard let data = try? Data(contentsOf: url) else {
                throw PipelineError("\(url.path) is missing: fetch the tile first")
            }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            for case let e as [String: Any] in root["elements"] as? [Any] ?? [] {
                let key = "\(e["type"] ?? "")/\(e["id"] ?? "")"
                if seen.insert(key).inserted { elements.append(e) }
            }
        }
        try JSONSerialization.data(withJSONObject: ["elements": elements]).write(to: folder.appendingPathComponent("osm.json"))
        return elements
    }

    /// Overpass JSON as OSM XML, nodes first, then ways, then relations.
    static func osmXML(_ elements: [[String: Any]]) -> String {
        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") + "\""
        }
        let order = ["node": 0, "way": 1, "relation": 2]
        let sorted = elements.sorted {
            let a = (order[$0["type"] as? String ?? ""] ?? 3, ($0["id"] as? NSNumber)?.int64Value ?? 0)
            let b = (order[$1["type"] as? String ?? ""] ?? 3, ($1["id"] as? NSNumber)?.int64Value ?? 0)
            return a < b
        }
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osm version=\"0.6\" generator=\"TilePipeline\">\n"
        for e in sorted {
            let meta = "id=\"\(e["id"] ?? 0)\" version=\"\(e["version"] ?? 1)\""
            let tags = (e["tags"] as? [String: Any] ?? [:]).map { "<tag k=\(q($0.key)) v=\(q("\($0.value)"))/>" }.joined()
            switch e["type"] as? String {
            case "node":
                out += "<node \(meta) lat=\"\(e["lat"] ?? 0)\" lon=\"\(e["lon"] ?? 0)\">\(tags)</node>\n"
            case "way":
                let refs = (e["nodes"] as? [Any] ?? []).map { "<nd ref=\"\($0)\"/>" }.joined()
                out += "<way \(meta)>\(refs)\(tags)</way>\n"
            default:
                let members = (e["members"] as? [[String: Any]] ?? []).map {
                    "<member type=\"\($0["type"] ?? "")\" ref=\"\($0["ref"] ?? 0)\" role=\(q($0["role"] as? String ?? ""))/>"
                }.joined()
                out += "<relation \(meta)>\(members)\(tags)</relation>\n"
            }
        }
        return out + "</osm>\n"
    }

    /// osm2streets over the merged OSM, clipped to the range plus `margin`.
    static func streets(_ region: Region, _ elements: [[String: Any]], _ folder: URL) throws -> URL {
        let out = folder.appendingPathComponent("streets")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let input = out.appendingPathComponent("input.osm")
        try osmXML(elements).write(to: input, atomically: true, encoding: .utf8)
        let (x0, y0, x1, y1) = region.bounds.buffer(margin, join: .mitre).bounds
        let (w, s) = region.lonLat(P2(x0, y0)), (e, n) = region.lonLat(P2(x1, y1))
        let clip: [String: Any] = ["type": "Feature", "properties": [String: Any](),
                                   "geometry": ["type": "Polygon", "coordinates": [[[w, s], [e, s], [e, n], [w, n], [w, s]]]]]
        let clipURL = out.appendingPathComponent("clip.geojson")
        try JSONSerialization.data(withJSONObject: clip).write(to: clipURL)
        let p = Process()
        p.executableURL = cli
        p.arguments = [input.path, clipURL.path, out.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw PipelineError("osm2streets failed: \(String(decoding: log.suffix(4000), as: UTF8.self))")
        }
        print(String(decoding: log, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        try? FileManager.default.removeItem(at: input)
        return out
    }

    /// What the editor draws under the roads, in lon and lat, 7 decimals.
    static func context(_ osm: Osm, _ region: Region, _ work: Geometry, _ folder: URL) throws {
        func ll(_ pts: [P2]) -> [[Double]] {
            pts.map { p in
                let (lon, lat) = region.lonLat(p)
                return [(lon * 1e7).rounded() / 1e7, (lat * 1e7).rounded() / 1e7]
            }
        }
        var buildings: [[[Double]]] = []
        for a in osm.areas() where a.tags["building"] != nil && !underground(a.tags) && a.shape.intersects(work) {
            for p in a.shape.polygons { buildings.append(ll(Array(p.exterior.dropLast()))) }
        }
        let kinds: Set<String> = Set(Roads.roadClasses.keys).union(["primary_link", "secondary_link", "tertiary_link",
                                                                     "pedestrian", "footway"])
        var lines: [[String: Any]] = []
        for (_, tags, line) in osm.lines() {
            let kind = tags["highway"] ?? ""
            guard kinds.contains(kind) || tags["footway"] == "crossing", line.intersects(work), tags["area"] != "yes" else { continue }
            lines.append(["highway": kind, "lanes": tags["lanes"] ?? NSNull(), "oneway": tags["oneway"] ?? NSNull(),
                          "name": tags["name"] ?? NSNull(), "points": ll(line.coords)])
        }
        var nodes: [[String: Any]] = []
        for id in osm.nodeOrder {
            let n = osm.nodes[id]!
            let kind = n.tags["highway"] == "crossing" ? "crossing"
                : (n.tags["highway"] == "bus_stop" || n.tags["public_transport"] == "platform") ? "bus_stop" : nil
            if let kind { nodes.append(["kind": kind, "point": [(n.lon * 1e7).rounded() / 1e7, (n.lat * 1e7).rounded() / 1e7]]) }
        }
        try JSONSerialization.data(withJSONObject: ["buildings": buildings, "roads": lines, "nodes": nodes])
            .write(to: folder.appendingPathComponent("context.json"))
        print("context: \(buildings.count) buildings, \(lines.count) roads, \(nodes.count) nodes")
    }
}
