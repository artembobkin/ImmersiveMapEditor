import Foundation
import Geometry

/// Seeding: the roadway from osm2streets, smoothed, the markings and the
/// shelters from OSM, and a road document of them.
extension Roads {
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
}
