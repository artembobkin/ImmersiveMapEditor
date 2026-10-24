import Foundation

/// The road document of build/roads.py (its doc comment is the format's
/// reference), held in local metres while it is edited and written back in
/// lon/lat, in the same layout the pipeline writes.
struct RoadDocument {
    struct Tiles { var z, x0, y0, x1, y1: Int }

    struct Area {
        var id: String
        var op: String              // "add" or "cut"
        var rings: [[Vec2]]         // the outer ring first, counter-clockwise, then the holes, clockwise
    }

    struct Marking {
        var id: String
        var kind: String            // line, zebra, zigzag, letter
        var style = "dashed"        // line: solid, dashed, double
        var colour = "white"        // line: white, yellow
        var points: [Vec2] = []     // line, zigzag (its baseline)
        var centre = Vec2.zero      // zebra, letter
        var heading = 0.0           // zebra, letter: degrees counter-clockwise from east
        var span = 10.0             // zebra: kerb to kerb
        var bar = 0.5               // zebra
        var length = 4.0            // zebra: a bar's length
        var side = 1                // zigzag: the roadway on the left (1) or right (-1)
        var step = 2.0              // zigzag
        var depth = 0.9             // zigzag
        var text = "A"              // letter

        /// Where it is, for moving and picking.
        var anchor: Vec2 { points.isEmpty ? centre : points.reduce(.zero, +) / Double(points.count) }
    }

    struct Shelter {
        var id: String
        var position: Vec2
        var heading: Double         // its length along it, the road on its left
    }

    var tiles: Tiles
    var seededDate: String
    var seededRevision: String
    var areas: [Area] = []
    var markings: [Marking] = []
    var shelters: [Shelter] = []

    var projection: Projection { Projection(z: tiles.z, x0: tiles.x0, y0: tiles.y0, x1: tiles.x1, y1: tiles.y1) }

    var name: String { "\(tiles.z)_\(tiles.x0)_\(tiles.y0)_\(tiles.x1)_\(tiles.y1)" }

    /// A new id for a kind's letter: one more than the highest in use.
    func newID(_ letter: String) -> String {
        let ids = areas.map(\.id) + markings.map(\.id) + shelters.map(\.id)
        let top = ids.filter { $0.hasPrefix(letter) }.compactMap { Int($0.dropFirst(letter.count)) }.max() ?? 0
        return "\(letter)\(top + 1)"
    }

    static func letter(of kind: String) -> String {
        ["line": "m", "zebra": "z", "zigzag": "g", "letter": "l"][kind] ?? "m"
    }
}

enum DocumentError: LocalizedError {
    case format(String)
    var errorDescription: String? { if case .format(let s) = self { return s }; return nil }
}

// MARK: Reading

extension RoadDocument {
    static func read(_ url: URL) throws -> RoadDocument {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocumentError.format("not a JSON object")
        }
        guard root["version"] as? Int == 1 else { throw DocumentError.format("road document version is not 1") }
        guard let t = root["tiles"] as? [String: Int], let z = t["z"], let x0 = t["x0"], let y0 = t["y0"],
              let x1 = t["x1"], let y1 = t["y1"] else { throw DocumentError.format("no tiles") }
        let seeded = root["seeded"] as? [String: String] ?? [:]
        var doc = RoadDocument(tiles: Tiles(z: z, x0: x0, y0: y0, x1: x1, y1: y1),
                               seededDate: seeded["date"] ?? "", seededRevision: seeded["osm2streets"] ?? "")
        let proj = doc.projection
        func point(_ any: Any?) -> Vec2 {
            guard let c = any as? [Double], c.count >= 2 else { return .zero }
            return proj.metres(lon: c[0], lat: c[1])
        }
        func line(_ any: Any?) -> [Vec2] { (any as? [Any] ?? []).map(point) }
        func number(_ any: Any?, _ fallback: Double) -> Double { (any as? NSNumber)?.doubleValue ?? fallback }

        for case let a as [String: Any] in root["areas"] as? [Any] ?? [] {
            let holes = (a["holes"] as? [Any] ?? []).map(line)
            doc.areas.append(Area(id: a["id"] as? String ?? "", op: a["op"] as? String ?? "add",
                                  rings: [line(a["outer"])] + holes))
        }
        for case let m as [String: Any] in root["markings"] as? [Any] ?? [] {
            var k = Marking(id: m["id"] as? String ?? "", kind: m["kind"] as? String ?? "line")
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
}

// MARK: Writing

extension RoadDocument {
    /// The document as build/roads.py `write` lays it out, byte for byte.
    func text() -> String {
        let proj = projection
        func number(_ v: Double) -> String {
            var s = String(format: "%.3f", v)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s == "-0" || s.isEmpty ? "0" : s
        }
        func coordinate(_ p: Vec2) -> String {
            let (lon, lat) = proj.lonLat(p)
            return String(format: "[%.8f, %.8f]", lon, lat)
        }
        func line(_ pts: [Vec2]) -> String { "[" + pts.map(coordinate).joined(separator: ", ") + "]" }
        func string(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(s)\""
        }
        func feature(_ pairs: [(String, String)]) -> String {
            "{" + pairs.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ") + "}"
        }

        var out = ["{", "\"version\": 1,",
                   "\"tiles\": {\"z\": \(tiles.z), \"x0\": \(tiles.x0), \"y0\": \(tiles.y0), \"x1\": \(tiles.x1), \"y1\": \(tiles.y1)},",
                   "\"seeded\": {\"date\": \(string(seededDate)), \"osm2streets\": \(string(seededRevision))},"]
        func section(_ name: String, _ lines: [String], last: Bool = false) {
            out.append("\"\(name)\": [")
            for (i, l) in lines.enumerated() { out.append(l + (i < lines.count - 1 ? "," : "")) }
            out.append("]" + (last ? "" : ","))
        }
        section("areas", areas.map { a in
            feature([("id", string(a.id)), ("op", string(a.op)), ("outer", line(a.rings[0])),
                     ("holes", "[" + a.rings.dropFirst().map(line).joined(separator: ", ") + "]")])
        })
        section("markings", markings.map { m in
            var pairs = [("id", string(m.id)), ("kind", string(m.kind))]
            switch m.kind {
            case "line":
                pairs += [("style", string(m.style)), ("colour", string(m.colour)), ("points", line(m.points))]
            case "zebra":
                pairs += [("centre", coordinate(m.centre)), ("heading", number(m.heading)), ("span", number(m.span)),
                          ("bar", number(m.bar)), ("length", number(m.length))]
            case "zigzag":
                pairs += [("side", number(Double(m.side))), ("step", number(m.step)), ("depth", number(m.depth)),
                          ("points", line(m.points))]
            default:
                pairs += [("text", string(m.text)), ("centre", coordinate(m.centre)), ("heading", number(m.heading))]
            }
            return feature(pairs)
        })
        section("shelters", shelters.map { s in
            feature([("id", string(s.id)), ("position", coordinate(s.position)), ("heading", number(s.heading))])
        }, last: true)
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }

    func write(_ url: URL) throws {
        try text().write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: The underlay

/// What the editor draws under the roads, from data/regions/<range>/context.json
/// (fetch/seed_roads.py): building outlines, OSM centre lines, crossings and
/// bus stops. Read only.
struct Underlay {
    struct Road { var highway: String; var name: String?; var points: [Vec2] }
    var buildings: [[Vec2]] = []
    var roads: [Road] = []
    var crossings: [Vec2] = []
    var stops: [Vec2] = []

    static func read(_ url: URL, _ proj: Projection) -> Underlay {
        var c = Underlay()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
        func point(_ any: Any?) -> Vec2 {
            guard let p = any as? [Double], p.count >= 2 else { return .zero }
            return proj.metres(lon: p[0], lat: p[1])
        }
        c.buildings = (root["buildings"] as? [Any] ?? []).map { ($0 as? [Any] ?? []).map(point) }
        for case let r as [String: Any] in root["roads"] as? [Any] ?? [] {
            c.roads.append(Road(highway: r["highway"] as? String ?? "", name: r["name"] as? String,
                                points: (r["points"] as? [Any] ?? []).map(point)))
        }
        for case let n as [String: Any] in root["nodes"] as? [Any] ?? [] {
            if n["kind"] as? String == "crossing" { c.crossings.append(point(n["point"])) } else { c.stops.append(point(n["point"])) }
        }
        return c
    }
}
