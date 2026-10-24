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
    }

    public struct Shelter {
        public var id: String
        public var position: P2
        public var heading: Double
    }

    public static let version = 1
    public static let osm2streetsRevision = "fc119c4"

    public var z, x0, y0, x1, y1: Int
    public var seededDate: String
    public var seededRevision: String
    public var areas: [Area] = []
    public var markings: [Mark] = []
    public var shelters: [Shelter] = []

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

    /// The road document in roads/ whose range holds the tile.
    public static func find(z: Int, x: Int, y: Int, root: URL = pipelineRoot) -> URL? {
        let folder = root.appendingPathComponent("roads")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }
        for name in names.sorted() {
            let url = folder.appendingPathComponent(name)
            if let doc = try? read(url), doc.holds(z: z, x: x, y: y) { return url }
        }
        return nil
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

public struct PipelineError: Error, CustomStringConvertible {
    public let description: String
    public init(_ s: String) { description = s }
}

/// Seeding the road document from osm2streets, and reading it for a build.
public enum Roads {
    static let roadClasses: [String: Double] = ["primary": 14, "secondary": 11, "tertiary": 8, "unclassified": 6,
                                                 "residential": 6, "living_street": 5, "service": 4]
    static let sett: Set<String> = ["sett", "cobblestone", "unhewn_cobblestone"]
    static let drive: Set<String> = ["Driving", "Bus", "SharedLeftTurn", "Parking(Parallel)", "Parking(Perpendicular)",
                                     "Parking(Diagonal)", "Biking", "Shoulder", "Construction", "LightRail"]
    static let smoothClose = 2.0    // the roadway's closing, filling notches
    static let smoothOpen = 0.6     // and its opening, dropping spikes
    static let taper = 12.0         // how far a road's change of width is spread

    /// Valid, on a 1 cm grid: overlay operations on lane polygons that
    /// touch and nearly overlap stay robust.
    public static func clean(_ g: Geometry) -> Geometry { g.makeValid().setPrecision(0.01).makeValid() }

    // MARK: Seeding from osm2streets

    /// A GeoJSON geometry in lon and lat, moved by `f`.
    static func geojson(_ g: [String: Any], _ f: (P2) -> P2) -> Geometry {
        func pt(_ a: Any) -> P2 {
            let c = (a as? [NSNumber])?.map(\.doubleValue) ?? [0, 0]
            return f(P2(c[0], c[1]))
        }
        func ring(_ a: Any) -> [P2] { (a as? [Any] ?? []).map(pt) }
        func polygon(_ a: Any) -> Geometry {
            let rings = (a as? [Any] ?? []).map(ring)
            guard let outer = rings.first else { return .empty }
            return .polygon(outer, holes: Array(rings.dropFirst()))
        }
        let c = g["coordinates"] ?? []
        switch g["type"] as? String {
        case "Polygon": return polygon(c)
        case "MultiPolygon": return .collection((c as? [Any] ?? []).map(polygon))
        case "LineString": return .lineString(ring(c))
        case "MultiLineString": return .collection((c as? [Any] ?? []).map { .lineString(ring($0)) })
        case "Point": return .point(pt(c))
        default: return .empty
        }
    }

    /// The osm2streets reconstruction in `folder` in local metres: the
    /// roadway, where roads meet, and the bus lanes. nil if there is none.
    ///
    /// The roadway is the driving, bus and parking lanes and the
    /// intersections between them, smoothed. Lanes in sett (Red Square) are
    /// left out: the vector tile shows the square.
    static func loadStreets(_ osm: Osm, _ folder: URL, _ work: Geometry) throws -> (Geometry, Geometry, [Geometry])? {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("lanes.geojson").path) else { return nil }
        func features(_ name: String) throws -> [([String: Any], Geometry)] {
            let data = try Data(contentsOf: folder.appendingPathComponent("\(name).geojson"))
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var out: [([String: Any], Geometry)] = []
            for case let f as [String: Any] in root["features"] as? [Any] ?? [] {
                let props = f["properties"] as? [String: Any] ?? [:]
                if (props["layer"] as? NSNumber)?.intValue ?? 0 != 0 { continue }
                let g = clean(geojson(f["geometry"] as? [String: Any] ?? [:]) { osm.projection.metres(lat: $0.y, lon: $0.x) })
                if g.isValid && g.intersects(work) { out.append((props, g)) }
            }
            return out
        }
        var drive: [Geometry] = [], settLanes: [Geometry] = [], bus: [Geometry] = []
        var byRoad: [Int: [Geometry]] = [:]
        for (props, g) in try features("lanes") {
            var kind = props["type"] as? String ?? ""
            let ways = (props["osm_way_ids"] as? [NSNumber] ?? []).compactMap { osm.ways[$0.int64Value] }
            let surface = ways.first.flatMap { $0.tags["surface"] }
            if kind == "Construction" {
                // A road under construction keeps the kind it is going to be.
                let built = ways.first.flatMap { $0.tags["construction"] }
                kind = roadClasses[built ?? ""] != nil ? "Driving" : "Footway"
            }
            if Roads.drive.contains(kind) {
                if sett.contains(surface ?? "") {
                    settLanes.append(g)
                } else {
                    drive.append(g)
                    byRoad[(props["road"] as? NSNumber)?.intValue ?? -1, default: []].append(g)
                }
                if kind == "Bus" { bus.append(g) }
            }
        }
        let driving = Geometry.unaryUnion(drive)
        let near = driving.buffer(0.5)
        let plain = try features("plain")
        let junctions = Geometry.unaryUnion(plain.filter { ($0.0["type"] as? String) == "intersection" && $0.1.intersects(near) }.map(\.1))
        let settRoads = Geometry.unaryUnion(settLanes)
        var roadway = Geometry.unaryUnion([driving, junctions.difference(settRoads.buffer(1))] + tapers(plain, byRoad))
        // osm2streets is right about where the roads go, but its junctions
        // are wedges that miss the lane edges, and lane widths step where
        // segments meet. A closing with round joins fills the notches and
        // wedges, a small opening drops the spikes left: compared on the
        // junctions of Lubyanka, this keeps the medians and the lane widths,
        // and nothing jagged.
        roadway = roadway.buffer(smoothClose).buffer(-smoothClose)
        roadway = roadway.buffer(-smoothOpen).buffer(smoothOpen)
        roadway = clean(roadway.difference(settRoads))
        // Where roads meet (not where one road merely changes its lanes): the
        // lane lines stop short of these.
        let meets = Geometry.unaryUnion(plain.filter {
            ($0.0["type"] as? String) == "intersection" && $0.1.intersects(near)
                && !["Connection", "MapEdge"].contains($0.0["intersection_kind"] as? String ?? "")
        }.map(\.1))
        return (roadway, meets, bus)
    }

    /// Where a road changes its number of lanes, osm2streets steps the lane
    /// edges and puts a thin Connection between the two segments: smoothing
    /// keeps the step's outer corner as a wedge. Each Connection gets the
    /// convex hull of both segments' lanes within taper of it instead, the
    /// slanted edge of a road that widens.
    static func tapers(_ plain: [([String: Any], Geometry)], _ byRoad: [Int: [Geometry]]) -> [Geometry] {
        var ends: [Int: [Int]] = [:]
        for (props, _) in plain where props["type"] as? String == "road" {
            for key in ["src_i", "dst_i"] {
                ends[(props[key] as? NSNumber)?.intValue ?? -1, default: []].append((props["id"] as? NSNumber)?.intValue ?? -1)
            }
        }
        var made: [Geometry] = []
        for (props, g) in plain {
            guard props["type"] as? String == "intersection", props["intersection_kind"] as? String == "Connection" else { continue }
            let roads = ends[(props["id"] as? NSNumber)?.intValue ?? -1] ?? []
            let lanes = roads.flatMap { byRoad[$0] ?? [] }
            if roads.count != 2 || lanes.isEmpty { continue }
            let piece = Geometry.unaryUnion(lanes).intersection(g.centroid.buffer(taper))
            // A bend, not a change of width: its hull would fill the inside of
            // the turn.
            if !piece.isEmpty && piece.convexHull.area < piece.area * 1.25 { made.append(piece.convexHull) }
        }
        return made
    }

    /// Every building and part outline in `work`: what a shelter must keep
    /// clear of while seeding.
    static func osmBuildings(_ osm: Osm, _ work: Geometry) -> Geometry {
        .unaryUnion(osm.areas().filter {
            ($0.tags["building"] != nil || $0.tags["building:part"] != nil) && !underground($0.tags) && $0.shape.intersects(work)
        }.map(\.shape))
    }

    /// A road document's content from osm2streets and OSM, in the local
    /// metres of the projection: areas, markings and shelters, without ids.
    public static func seed(_ osm: Osm, streets: URL, work: Geometry) throws
        -> (areas: [(String, [P2], [[P2]])], markings: [Mark], shelters: [(P2, Double)]) {
        guard let (rough, meets, bus) = try loadStreets(osm, streets, work) else {
            throw PipelineError("no osm2streets output in \(streets.path)")
        }
        let roadway = clean(rough.intersection(work).simplify(0.05))
        let areas = roadway.polygons.map { p in ("add", ring(p.exterior, ccw: true), p.interiors.map { ring($0, ccw: false) }) }
        let zebras = Markings.zebras(osm, roadway, work)
        let zones = zebras.isEmpty ? nil : Geometry.unaryUnion(zebras.compactMap { Markings.zebraBars($0, roadway)?.1 })
        var lines: [Mark] = []
        for l in Markings.laneLines(osm, roadway, meets, work) {
            // Wiped from the zebras' zones, as the build would.
            if let zones {
                for piece in Geometry.lineString(l.points).difference(zones).lines where piece.length >= 1 {
                    var m = l
                    m.points = piece.coords
                    lines.append(m)
                }
            } else {
                lines.append(l)
            }
        }
        let stops = Markings.stopKerbs(osm, roadway, work)
        let marks = lines + zebras + Markings.busStops(stops) + Markings.busLetters(bus)
        return (areas, marks, shelters(stops, osmBuildings(osm, work), roadway))
    }

    /// A ring's points, open, wound counter-clockwise or clockwise.
    static func ring(_ r: [P2], ccw: Bool) -> [P2] {
        let p = Geometry.polygon(r).oriented(ccw ? 1 : -1).exterior
        return Array(p.dropLast())
    }

    /// A shelter behind every stop's kerb, along it, the road on its left.
    /// One that would stand on a building or the road is left out.
    static func shelters(_ stops: [(P2, P2, P2)], _ buildings: Geometry, _ roadway: Geometry) -> [(P2, Double)] {
        let (lx, ly, _) = shelterSize
        let keepOut = buildings.buffer(0.3).union(roadway)
        var made: [(P2, Double)] = []
        for (kerb, dir, n) in stops {
            var u = dir
            if u.x * n.y - u.y * n.x < 0 { u = -u }
            let centre = kerb - n * shelterBack
            let heading = atan2(u.y, u.x)
            let rect = Geometry.box(-lx / 2 - 1.2, -ly / 2, lx / 2, ly / 2).rotate(heading, origin: .zero, radians: true)
            if rect.translate(centre.x, centre.y).intersects(keepOut) { continue }
            made.append((centre, heading * 180 / .pi))
        }
        return made
    }

    /// `seed`'s content in local metres to a document in lon and lat, with ids.
    public static func document(_ content: (areas: [(String, [P2], [[P2]])], markings: [Mark], shelters: [(P2, Double)]),
                                region: Region, date: Date = Date()) -> RoadDocument {
        func ll(_ p: P2) -> P2 {
            let (lon, lat) = region.lonLat(p)
            return P2(lon, lat)
        }
        var counts: [String: Int] = [:]
        func ident(_ letter: String) -> String {
            counts[letter, default: 0] += 1
            return "\(letter)\(counts[letter]!)"
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: "UTC")
        var doc = RoadDocument(z: region.z, x0: region.x0, y0: region.y0, x1: region.x1, y1: region.y1,
                               seededDate: iso.string(from: date).replacingOccurrences(of: "Z", with: "+00:00"),
                               seededRevision: RoadDocument.osm2streetsRevision)
        doc.areas = content.areas.map { RoadDocument.Area(id: ident("a"), op: $0.0, outer: $0.1.map(ll), holes: $0.2.map { $0.map(ll) }) }
        let letters = ["line": "m", "zebra": "z", "zigzag": "g", "letter": "l"]
        doc.markings = content.markings.map { m in
            var k = m
            k.id = ident(letters[m.kind] ?? "m")
            k.points = m.points.map(ll)
            k.centre = m.centre.map(ll)
            return k
        }
        doc.shelters = content.shelters.map { RoadDocument.Shelter(id: ident("s"), position: ll($0.0), heading: $0.1) }
        return doc
    }

    // MARK: Loading for a build

    /// The document in the projection's local metres, as shapes for Ground:
    /// the roadway, white and yellow paint (not yet clipped to the roadway)
    /// and the shelters (centre, heading in radians).
    public static func load(_ doc: RoadDocument, _ p: Projecting, work: Geometry)
        -> (roadway: Geometry, white: Geometry?, yellow: Geometry?, shelters: [(P2, Double)]) {
        func m(_ q: P2) -> P2 { p.metres(lat: q.y, lon: q.x) }
        let reach = work.buffer(60)
        var add: [Geometry] = [], cut: [Geometry] = []
        for a in doc.areas {
            let poly = Geometry.polygon(a.outer.map(m), holes: a.holes.map { $0.map(m) })
            guard poly.intersects(reach) else { continue }
            if a.op == "add" { add.append(clean(poly)) } else { cut.append(clean(poly)) }
        }
        var roadway = clean(.unaryUnion(add))
        if !cut.isEmpty { roadway = clean(roadway.difference(.unaryUnion(cut))) }
        var white: [Geometry] = [], bars: [Geometry] = [], yellow: [Geometry] = [], zones: [Geometry] = []
        for var mark in doc.markings {
            mark.points = mark.points.map(m)
            mark.centre = mark.centre.map(m)
            guard let anchor = mark.centre ?? mark.points.first else { continue }
            if Geometry.point(anchor).distance(reach) > 200 { continue }
            switch mark.kind {
            case "line":
                if mark.colour == "yellow" { yellow += Markings.linePaint(mark) } else { white += Markings.linePaint(mark) }
            case "zebra":
                if let (b, z) = Markings.zebraBars(mark, roadway) {
                    bars.append(b)
                    zones.append(z)
                }
            case "zigzag":
                if let g = Markings.zigzagPaint(mark) { yellow.append(g) }
            case "letter":
                white.append(Markings.letterPaint(mark))
            default:
                break
            }
        }
        // Every other white marking is wiped from a zebra's zone.
        var w: Geometry? = white.isEmpty ? nil : .unaryUnion(white)
        if let ww = w, !zones.isEmpty { w = ww.difference(.unaryUnion(zones)) }
        if w != nil || !bars.isEmpty { w = .unaryUnion((w.map { [$0] } ?? []) + bars) }
        let near = work.buffer(10)
        let shelters = doc.shelters.compactMap { s -> (P2, Double)? in
            let c = m(s.position)
            return near.contains(c) ? (c, s.heading * .pi / 180) : nil
        }
        return (roadway, w, yellow.isEmpty ? nil : .unaryUnion(yellow), shelters)
    }
}
