import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// Street-level photos of a landmark (Mapillary's) judged by geometry: from
/// where each camera stands, which way it looks and how wide (its focal
/// length), against the landmark's facades (the sides of its convex hull)
/// and height from OSM and the other buildings of the tile, which facades
/// are in the frame, how much of each, how square on, and whether a
/// neighbour stands in the way. The candidates are chosen facade by facade:
/// for every facade the photo that shows it best, then a second from
/// another track (a Mapillary sequence: one car's or walker's pass) or
/// another angle, so a landmark the street photos surround is seen from all
/// its sides, and a facade no photo shows is named. A kept photo gets the
/// landmark framed in red, and a panorama is cut to it, so the agent knows
/// which building it is looking at.
struct StreetScene {
    /// Longitude and latitude of the landmark's centre.
    let lon: Double, lat: Double
    /// Metres a degree, east and north.
    let kx: Double, ky: Double
    /// The corners of the landmark's convex hull, counter-clockwise, in
    /// metres around its centre: enough for where it is seen from, a few
    /// dozen instead of the thousands of corners of a landmark of many parts.
    let corners: [P2]
    /// The hull's sides: what a photo can show.
    let facades: [Facade]
    /// How tall it is at most.
    let top: Double
    /// The other buildings of the tile, to see what hides it, each with its
    /// bounds (west, south, east, north).
    let others: [(shape: Geometry, bounds: (Double, Double, Double, Double))]
    /// Every building of the tile, the landmark's own too, 2 m in from its
    /// walls: a track that crosses one did not go there, its GPS strayed
    /// (the 2 m let a camera on a narrow pavement by).
    let cores: [(shape: Geometry, bounds: (Double, Double, Double, Double))]

    /// One side of the hull: a wall a camera can face. A chain of the
    /// hull's edges running one way, the short ones (a corner's chamfer,
    /// a portico's step) in with their longer neighbours.
    struct Facade {
        /// Its ends, the chord from the first edge's start to the last's end.
        let a: P2, b: P2
        /// Outward, unit length, of the chord.
        let normal: P2
        /// Along its edges.
        let length: Double
        /// The compass side it faces: "north", "north-east", ...
        let side: String
        /// "the north facade", with its end when two face one way.
        let name: String
        /// Points along its edges every few metres, each with its edge's
        /// outward normal: how much of it a camera sees is how many of them
        /// it sees.
        let samples: [(p: P2, n: P2)]
    }

    /// How many facades the landmark's hull has, from its landmark.json
    /// alone: what the turn limit and the panel ask, without the tile's
    /// buildings around it (the user, 2026-11-03: the panel built the whole
    /// scene for the count, the tile's OSM read and every building made,
    /// at each of its redraws, the window frozen).
    static func facadeCount(folder: URL) -> Int? {
        guard let source = try? LandmarkSource(folder.appendingPathComponent("landmark.json")) else { return nil }
        let all = source.buildings.flatMap { $0.polygons.flatMap { $0.first ?? [] } }
        let hull = Geometry.collection(all.map { Geometry.point($0) }).convexHull
        var ring = hull.kind == .polygon ? Array(hull.exterior.dropLast()) : all
        if signedArea(ring) < 0 { ring.reverse() }
        return facades(of: ring).count
    }

    init(folder: URL) throws {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        (lon, lat) = source.centre
        kx = cos(lat * .pi / 180) * 111_320.0
        ky = 110_574.0
        let all = source.buildings.flatMap { $0.polygons.flatMap { $0.first ?? [] } }
        let hull = Geometry.collection(all.map { Geometry.point($0) }).convexHull
        var ring = hull.kind == .polygon ? Array(hull.exterior.dropLast()) : all
        if signedArea(ring) < 0 { ring.reverse() }
        corners = ring
        facades = Self.facades(of: ring)
        top = source.buildings.compactMap(\.height).max() ?? 15
        let own = Set(source.buildings.map(\.osm))
        var others: [(shape: Geometry, bounds: (Double, Double, Double, Double))] = []
        // The tile's buildings, apart from the landmark's own.
        let tileFolder = folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("osm")
        if let tile = try? Tile(folder: tileFolder), let osm = try? Osm(tile) {
            let centre = tile.metres(lat: lat, lon: lon)
            for a in osm.areas() where a.tags["building"] != nil && a.tags["building"] != "no" && !own.contains("\(a.kind)/\(a.id)") {
                for poly in a.shape.polygons where poly.area > 20 {
                    let shape = Geometry.polygon(poly.exterior.map { $0 - centre })
                    others.append((shape, shape.bounds))
                }
            }
        }
        self.others = others
        let mine = source.buildings.flatMap { b in b.polygons.compactMap { $0.first }.filter { $0.count >= 3 }.map { Geometry.polygon($0) } }
        cores = (others.map(\.shape) + mine).compactMap { shape in
            let core = shape.buffer(-2)
            return core.isEmpty || core.area < 1 ? nil : (core, core.bounds)
        }
    }

    /// Whether a point stands in a building's core.
    func inBuilding(_ p: P2) -> Bool {
        cores.contains { c in c.bounds.0 <= p.x && c.bounds.2 >= p.x && c.bounds.1 <= p.y && c.bounds.3 >= p.y && c.shape.contains(p) }
    }

    /// Whether a path crosses a building's core.
    func throughBuilding(_ path: [P2]) -> Bool {
        guard path.count >= 2 else { return path.first.map(inBuilding) ?? false }
        let xs = path.map(\.x), ys = path.map(\.y)
        let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let line = Geometry.lineString(path)
        return cores.contains { c in c.bounds.0 <= x1 && c.bounds.2 >= x0 && c.bounds.1 <= y1 && c.bounds.3 >= y0 && c.shape.intersects(line) }
    }

    /// Metres east and north of the centre.
    func metres(lon: Double, lat: Double) -> P2 { P2((lon - self.lon) * kx, (lat - self.lat) * ky) }

    /// Whether a point stands inside the hull (counter-clockwise).
    func inside(_ p: P2) -> Bool {
        guard corners.count >= 3 else { return false }
        for k in corners.indices {
            let a = corners[k], b = corners[(k + 1) % corners.count]
            if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) < 0 { return false }
        }
        return true
    }

    /// The stations a facade is looked at from, in order along it: from
    /// beyond one end, its first third, its middle, its last third, from
    /// beyond the other end. A camera stands at the station its foot of
    /// perpendicular on the facade falls in, in front of the facade and
    /// within 150 m of it.
    static let stations = 5
    func station(_ f: Int, of at: P2) -> Int? {
        let facade = facades[f]
        let d = facade.b - facade.a, length = simd_length(d)
        guard length > 0, simd_dot(at - facade.a, facade.normal) > 0, simd_dot(at - facade.a, facade.normal) <= 150 else { return nil }
        let t = simd_dot(at - facade.a, d) / length
        return t < 0 ? 0 : t < length / 3 ? 1 : t < 2 * length / 3 ? 2 : t <= length ? 3 : 4
    }
    func stationName(_ f: Int, _ k: Int) -> String {
        let facade = facades[f]
        let d = facade.b - facade.a
        let toB = StreetView.side(atan2(d.x, d.y) * 180 / .pi), toA = StreetView.side(atan2(-d.x, -d.y) * 180 / .pi)
        switch k {
        case 0: return "from beyond its \(toA) end"
        case 1: return "from its \(toA) third"
        case 2: return "from its middle"
        case 3: return "from its \(toB) third"
        default: return "from beyond its \(toB) end"
        }
    }

    /// How much of a facade some samples are, in words, with the end they
    /// are at when they are a part: "whole", "half (its east end)".
    func part(_ f: Int, _ flags: [Bool]) -> String {
        let facade = facades[f]
        let count = flags.filter { $0 }.count
        guard count > 0 else { return "nothing" }
        let fraction = Double(count) / Double(flags.count)
        let how = fraction > 0.85 ? "whole" : fraction > 0.6 ? "most of it" : fraction > 0.4 ? "half" : fraction > 0.25 ? "a third" : "a little"
        guard fraction <= 0.85 else { return how }
        let mean = Double(flags.indices.filter { flags[$0] }.reduce(0, +)) / Double(count), centre = Double(flags.count - 1) / 2
        guard abs(mean - centre) > Double(flags.count) * 0.12 else { return "\(how) (its middle)" }
        let d = mean > centre ? facade.b - facade.a : facade.a - facade.b
        return "\(how) (its \(StreetView.side(atan2(d.x, d.y) * 180 / .pi)) end)"
    }

    /// The hull's sides as facades: its edges, each short one (under 6 m, or
    /// a twelfth of the perimeter: a corner's chamfer, a portico's step) and
    /// each running within 15° of a neighbour joined to the neighbour nearest
    /// its direction, the shortest first, until only the real sides are
    /// left, each named by the side it faces.
    static func facades(of ring: [P2]) -> [Facade] {
        guard ring.count >= 3 else { return [] }
        typealias Edge = (a: P2, b: P2)
        var chains: [[Edge]] = ring.indices.map { [(ring[$0], ring[($0 + 1) % ring.count])] }
        func length(_ c: [Edge]) -> Double { c.reduce(0) { $0 + simd_length($1.b - $1.a) } }
        func direction(_ c: [Edge]) -> Double { atan2(c.last!.b.y - c.first!.a.y, c.last!.b.x - c.first!.a.x) * 180 / .pi }
        func turn(_ k: Int, _ j: Int) -> Double { abs(StreetView.wrap(direction(chains[k]) - direction(chains[j]))) }
        let small = max(6, chains.reduce(0) { $0 + length($1) } / 12)
        while chains.count > 1 {
            let n = chains.count
            // Two neighbours running one way join first, the straightest
            // pair of them; then the shortest small chain joins the
            // neighbour nearest its direction.
            if let k = (0..<n).filter({ turn($0, ($0 + 1) % n) < 15 }).min(by: { turn($0, ($0 + 1) % n) < turn($1, ($1 + 1) % n) }) {
                let next = (k + 1) % n
                chains[k] += chains[next]
                chains.remove(at: next)
                continue
            }
            guard let k = chains.indices.filter({ length(chains[$0]) < small }).min(by: { length(chains[$0]) < length(chains[$1]) }) else { break }
            let next = (k + 1) % n, prev = (k + n - 1) % n
            if n == 2 || turn(k, next) <= turn(k, prev) {
                chains[k] += chains[next]
                chains.remove(at: next)
            } else {
                chains[prev] += chains[k]
                chains.remove(at: k)
            }
        }
        var out: [Facade] = []
        for c in chains {
            let a = c.first!.a, b = c.last!.b
            let d = b - a
            guard simd_length(d) > 0.1 else { continue }
            let n = P2(d.y, -d.x) / simd_length(d)
            var samples: [(p: P2, n: P2)] = []
            for e in c {
                let ed = e.b - e.a, el = simd_length(ed)
                guard el > 0.1 else { continue }
                let count = max(2, min(40, Int(el / 4)))
                let en = P2(ed.y, -ed.x) / el
                samples += (0..<count).map { (e.a + ed * ((Double($0) + 0.5) / Double(count)), en) }
            }
            let side = StreetView.side(atan2(n.x, n.y) * 180 / .pi)
            out.append(Facade(a: a, b: b, normal: n, length: length(c), side: side, name: "the \(side) facade", samples: samples))
        }
        // Two facing one way are told apart by their ends.
        var named: [Facade] = []
        for f in out {
            let alike = out.filter { $0.side == f.side }
            guard alike.count > 1 else { named.append(f); continue }
            let t = P2(f.normal.y, -f.normal.x)
            let along = alike.map { simd_dot(($0.a + $0.b) / 2, t) }.sorted()
            let mine = simd_dot((f.a + f.b) / 2, t)
            let end = mine <= along.first! ? StreetView.side(atan2(-t.x, -t.y) * 180 / .pi)
                : mine >= along.last! ? StreetView.side(atan2(t.x, t.y) * 180 / .pi) : "middle"
            named.append(Facade(a: f.a, b: f.b, normal: f.normal, length: f.length, side: f.side,
                                name: "the \(f.side) facade, \(end == "middle" ? "the middle" : "\(end) end")", samples: f.samples))
        }
        return named
    }

    /// What a perspective camera there sees of the landmark: a kept photo's
    /// pose, or any place.
    func view(x: Double, y: Double, heading: Double, hfov: Double, width: Int, height: Int) -> StreetView? {
        let w = Double(width), h = Double(height), l = max(w, h)
        let focal = 0.5 * w / l / tan(max(10, min(170, hfov)) / 2 * .pi / 180)
        let photo = StreetPhoto(id: "pose", at: P2(x, y), compass: heading, focal: focal, width: width, height: height)
        return StreetView(photo, in: self, central: false)
    }
}
