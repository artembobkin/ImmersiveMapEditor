import Foundation
import Geometry

/// The road document: the roadway, its markings and the bus shelters of a
/// range of tiles, the one source of the roads once it is seeded. The
/// pipeline seeds it from osm2streets and OSM (`Roads.seed`), the user
/// corrects it by hand in the editor, and every build reads it
/// (`Roads.load`). Seeding again overwrites the hand edits, so it is never
/// done without being asked for.
///
///   roads/<z>_<x0>_<y0>_<x1>_<y1>.json
///
/// The format, version 1. JSON, one feature to a line, keys in this order,
/// so a hand edit reads in a diff. Coordinates are [longitude, latitude] in
/// WGS84, 8 decimals; other numbers have at most 3 decimals and no trailing
/// zeros. Headings are degrees counter-clockwise from east.
///
///   {
///   "version": 1,
///   "tiles": {"z": 15, "x0": 19808, "y0": 10242, "x1": 19809, "y1": 10243},
///   "seeded": {"date": "2026-10-24T09:00:00+00:00", "osm2streets": "fc119c4"},
///   "areas": [
///   {"id": "a1", "op": "add", "outer": [[lon, lat], ...], "holes": [[[lon, lat], ...], ...]},
///   ...
///   ],
///   "markings": [
///   {"id": "m1", "kind": "line", "style": "dashed", "colour": "white", "points": [[lon, lat], ...]},
///   {"id": "z1", "kind": "zebra", "centre": [lon, lat], "heading": 31.5, "span": 14.2, "bar": 0.5, "length": 4},
///   {"id": "g1", "kind": "zigzag", "side": 1, "step": 2, "depth": 0.9, "points": [[lon, lat], [lon, lat]]},
///   {"id": "l1", "kind": "letter", "text": "A", "centre": [lon, lat], "heading": 120},
///   ...
///   ],
///   "shelters": [
///   {"id": "s1", "position": [lon, lat], "heading": 75},
///   ...
///   ]
///   }
///
/// - Areas: the roadway is the union of the `add` areas less the union of
///   the `cut` areas. Rings are open, the outer one counter-clockwise, holes
///   clockwise.
/// - Markings: what Markings makes of them. A line's style is solid, dashed
///   or double, its colour white or yellow.
/// - Shelters: a bus shelter's centre, its length along the heading, the
///   road on its left.
///
/// Ids are unique within the document: a letter for the kind (a area, m
/// line, z zebra, g zigzag, l letter, s shelter) and a number.
public struct RoadDocument {
    public struct Area {
        public var id: String
        public var op: String               // add, cut
        public var outer: [P2]
        public var holes: [[P2]]

        public init(id: String, op: String, outer: [P2], holes: [[P2]]) {
            self.id = id
            self.op = op
            self.outer = outer
            self.holes = holes
        }
    }

    public struct Shelter {
        public var id: String
        public var position: P2
        public var heading: Double

        public init(id: String, position: P2, heading: Double) {
            self.id = id
            self.position = position
            self.heading = heading
        }
    }

    public static let version = 1
    public static let osm2streetsRevision = "fc119c4"

    public var z, x0, y0, x1, y1: Int
    public var seededDate: String
    public var seededRevision: String
    public var areas: [Area] = []
    public var markings: [Mark] = []
    public var shelters: [Shelter] = []

    public init(z: Int, x0: Int, y0: Int, x1: Int, y1: Int, seededDate: String, seededRevision: String) {
        (self.z, self.x0, self.y0, self.x1, self.y1) = (z, x0, y0, x1, y1)
        self.seededDate = seededDate
        self.seededRevision = seededRevision
    }

    public var name: String { "\(z)_\(x0)_\(y0)_\(x1)_\(y1)" }

    public func holds(z tz: Int, x: Int, y: Int) -> Bool {
        tz == z && (x0...x1).contains(x) && (y0...y1).contains(y)
    }

    // MARK: Reading

    public static func read(_ url: URL) throws -> RoadDocument {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        guard root["version"] as? Int == version else {
            throw PipelineError("\(url.lastPathComponent): road document version \(root["version"] ?? "none"), this pipeline reads \(version)")
        }
        let t = root["tiles"] as? [String: Int] ?? [:]
        let s = root["seeded"] as? [String: String] ?? [:]
        var doc = RoadDocument(z: t["z"] ?? 15, x0: t["x0"] ?? 0, y0: t["y0"] ?? 0, x1: t["x1"] ?? 0, y1: t["y1"] ?? 0,
                               seededDate: s["date"] ?? "", seededRevision: s["osm2streets"] ?? "")
        func point(_ a: Any?) -> P2 {
            let c = (a as? [NSNumber])?.map(\.doubleValue) ?? [0, 0]
            return P2(c[0], c[1])
        }
        func line(_ a: Any?) -> [P2] { (a as? [Any] ?? []).map(point) }
        func number(_ a: Any?, _ d: Double) -> Double { (a as? NSNumber)?.doubleValue ?? d }
        for case let a as [String: Any] in root["areas"] as? [Any] ?? [] {
            doc.areas.append(Area(id: a["id"] as? String ?? "", op: a["op"] as? String ?? "add", outer: line(a["outer"]),
                                  holes: (a["holes"] as? [Any] ?? []).map(line)))
        }
        for case let m as [String: Any] in root["markings"] as? [Any] ?? [] {
            var k = Mark(kind: m["kind"] as? String ?? "line")
            k.id = m["id"] as? String ?? ""
            k.style = m["style"] as? String ?? k.style
            k.colour = m["colour"] as? String ?? k.colour
            k.points = line(m["points"])
            if m["centre"] != nil { k.centre = point(m["centre"]) }
            k.heading = number(m["heading"], k.heading)
            k.span = number(m["span"], k.span)
            k.bar = number(m["bar"], k.bar)
            k.length = number(m["length"], k.length)
            k.side = Int(number(m["side"], Double(k.side)))
            k.step = number(m["step"], k.step)
            k.depth = number(m["depth"], k.depth)
            k.text = m["text"] as? String ?? k.text
            doc.markings.append(k)
        }
        for case let s as [String: Any] in root["shelters"] as? [Any] ?? [] {
            doc.shelters.append(Shelter(id: s["id"] as? String ?? "", position: point(s["position"]),
                                        heading: number(s["heading"], 0)))
        }
        return doc
    }

    /// The tile's road document, in its folder, if it has one.
    public static func find(z: Int, x: Int, y: Int, in paths: WorkspacePaths) -> URL? {
        let url = paths.roadDocument(z: z, x: x, y: y)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Writing

    /// A number as the document writes it: at most 3 decimals, no trailing
    /// zeros. The editor writes the same.
    static func number(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" || s.isEmpty ? "0" : s
    }

    static func coordinate(_ p: P2) -> String { String(format: "[%.8f, %.8f]", p.x, p.y) }
    static func line(_ pts: [P2]) -> String { "[" + pts.map(coordinate).joined(separator: ", ") + "]" }
    static func string(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    /// The document in its one layout.
    public func text() -> String {
        func feature(_ pairs: [(String, String)]) -> String {
            "{" + pairs.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ") + "}"
        }
        var out = ["{", "\"version\": \(RoadDocument.version),",
                   "\"tiles\": {\"z\": \(z), \"x0\": \(x0), \"y0\": \(y0), \"x1\": \(x1), \"y1\": \(y1)},",
                   "\"seeded\": {\"date\": \(Self.string(seededDate)), \"osm2streets\": \(Self.string(seededRevision))},"]
        func section(_ name: String, _ lines: [String], last: Bool = false) {
            out.append("\"\(name)\": [")
            for (i, l) in lines.enumerated() { out.append(l + (i < lines.count - 1 ? "," : "")) }
            out.append("]" + (last ? "" : ","))
        }
        let n = Self.number, c = Self.coordinate, s = Self.string
        section("areas", areas.map {
            feature([("id", s($0.id)), ("op", s($0.op)), ("outer", Self.line($0.outer)),
                     ("holes", "[" + $0.holes.map(Self.line).joined(separator: ", ") + "]")])
        })
        section("markings", markings.map { m in
            var pairs = [("id", s(m.id)), ("kind", s(m.kind))]
            switch m.kind {
            case "line": pairs += [("style", s(m.style)), ("colour", s(m.colour)), ("points", Self.line(m.points))]
            case "zebra": pairs += [("centre", c(m.centre ?? .zero)), ("heading", n(m.heading)), ("span", n(m.span)),
                                    ("bar", n(m.bar)), ("length", n(m.length))]
            case "zigzag": pairs += [("side", n(Double(m.side))), ("step", n(m.step)), ("depth", n(m.depth)),
                                     ("points", Self.line(m.points))]
            default: pairs += [("text", s(m.text)), ("centre", c(m.centre ?? .zero)), ("heading", n(m.heading))]
            }
            return feature(pairs)
        })
        section("shelters", shelters.map {
            feature([("id", s($0.id)), ("position", c($0.position)), ("heading", n($0.heading))])
        }, last: true)
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }

    public func write(_ url: URL) throws { try text().write(to: url, atomically: true, encoding: .utf8) }
}
