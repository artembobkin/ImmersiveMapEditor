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
        return StreetView(photo, in: self)
    }
}

/// One photo, as Mapillary describes it.
struct StreetPhoto {
    let id: String
    /// Where the camera stands, in the scene's metres.
    let at: P2
    /// Which way it looks, a compass bearing.
    let compass: Double?
    let pano: Bool
    /// "perspective", "fisheye" or "spherical".
    let camera: String
    /// Focal length over the longer side, OpenSfM's normalisation.
    let focal: Double
    let width: Int, height: Int
    let captured: Date?
    let author: String
    let sequence: String
    let thumb: String?
    /// How far the pose Mapillary computed (structure from motion) is from
    /// what the device recorded: a large difference means one of them is
    /// wrong, and the photo may not show what the geometry says.
    let poseDoubt: Bool
    /// Mapillary's own quality score, 0 to 1, when it has one.
    let quality: Double?
    /// Whether the pose is the device's alone (no computed one): Mapillary
    /// has not placed the photo by structure from motion.
    let fromDevice: Bool
    /// The local hour it was taken, to tell night from day.
    let hour: Int?

    static let fields = "id,computed_geometry,geometry,computed_compass_angle,compass_angle,captured_at,creator,is_pano,camera_type,camera_parameters,width,height,sequence,quality_score"

    /// Whether Mapillary has both poses and they disagree (by 20 m or 35°).
    static func posesDisagree(_ e: [String: Any], _ scene: StreetScene) -> Bool {
        guard let c = (e["computed_geometry"] as? [String: Any])?["coordinates"] as? [Double], c.count == 2,
              let raw = (e["geometry"] as? [String: Any])?["coordinates"] as? [Double], raw.count == 2 else { return false }
        if simd_length(scene.metres(lon: raw[0], lat: raw[1]) - scene.metres(lon: c[0], lat: c[1])) > 20 { return true }
        if let a = (e["computed_compass_angle"] as? NSNumber)?.doubleValue, let b = (e["compass_angle"] as? NSNumber)?.doubleValue,
           abs(StreetView.wrap(a - b)) > 35 { return true }
        return false
    }

    /// By the computed pose (structure from motion), or the device's own
    /// (`device`, or when Mapillary has no computed one: a photo the
    /// coverage tile places is as good a candidate by its device's pose).
    init?(_ e: [String: Any], _ scene: StreetScene, device: Bool = false) {
        let computed = device ? nil : (e["computed_geometry"] as? [String: Any])?["coordinates"] as? [Double]
        let raw = (e["geometry"] as? [String: Any])?["coordinates"] as? [Double]
        guard let id = e["id"] as? String, let c = computed ?? raw, c.count == 2 else { return nil }
        self.id = id
        at = scene.metres(lon: c[0], lat: c[1])
        fromDevice = computed == nil
        let angles = device ? [e["compass_angle"], e["computed_compass_angle"]] : [e["computed_compass_angle"], e["compass_angle"]]
        compass = angles.compactMap { ($0 as? NSNumber)?.doubleValue }.first
        let flagged = e["is_pano"] as? Bool ?? false, type = e["camera_type"] as? String
        pano = flagged || ["spherical", "equirectangular"].contains(type ?? "")
        camera = type ?? (pano ? "spherical" : "perspective")
        let params = e["camera_parameters"] as? [Double] ?? []
        focal = params.first.map { $0 > 0.1 && $0 < 5 ? $0 : 0.7 } ?? 0.7
        width = (e["width"] as? NSNumber)?.intValue ?? 1920
        height = (e["height"] as? NSNumber)?.intValue ?? 1080
        captured = (e["captured_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        author = (e["creator"] as? [String: Any])?["username"] as? String ?? "unknown"
        sequence = e["sequence"] as? String ?? id
        thumb = (e["thumb_original_url"] as? String) ?? (e["thumb_2048_url"] as? String) ?? (e["thumb_1024_url"] as? String)
        poseDoubt = Self.posesDisagree(e, scene)
        quality = (e["quality_score"] as? NSNumber)?.doubleValue
        hour = captured.map { Int(($0.timeIntervalSince1970 / 3600 + (scene.lon / 15).rounded()).truncatingRemainder(dividingBy: 24)) }
    }

    /// A perspective camera at a place: a kept photo's pose.
    init(id: String, at: P2, compass: Double, focal: Double, width: Int, height: Int) {
        self.id = id
        self.at = at
        self.compass = compass
        pano = false
        camera = "perspective"
        self.focal = focal
        self.width = width
        self.height = height
        captured = nil
        author = ""
        sequence = id
        thumb = nil
        poseDoubt = false
        quality = nil
        fromDevice = false
        hour = nil
    }

    var date: String {
        guard let captured else { return "?" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: captured)
    }
}

/// What a photo shows of the landmark, facade by facade, and how good a
/// look it is.
struct StreetView {
    let photo: StreetPhoto
    /// Metres to the nearest point of a facade it sees.
    let distance: Double
    /// The side of the centre the camera stands on (a compass bearing).
    let from: Double
    /// Degrees between where the camera looks and the centre (0 for a panorama).
    let off: Double
    /// Of each facade of the scene, the part in the frame (0 to 1), and
    /// which of its samples: what two photos show together.
    let seen: [Double]
    let seenSamples: [[Bool]]
    /// Of each facade, how good a look the photo gives of it (0 to 1): the
    /// part seen, how square on, how large in the frame, how near, and the
    /// photo's own worth (its date, pose, quality, daylight).
    let looks: [Double]
    /// The facade it shows best.
    let best: Int
    /// The part of the whole perimeter in the frame.
    let coverage: Double
    /// The frame it takes, as fractions of width and height (0 to 1), in
    /// a panorama the cut taken around it.
    let box: CGRect
    let share: Double
    let hidden: Double
    let score: Double
    /// Where the camera looks (a compass bearing) and how wide (degrees).
    let heading: Double
    let hfov: Double

    /// The camera of the kept picture (a panorama's cut, or the photo as it
    /// is): heading, pitch (up positive) and horizontal field of view, to
    /// render the model from the same place.
    var pose: (heading: Double, pitch: Double, hfov: Double) {
        guard photo.pano else { return (heading, 0, hfov) }
        let (cx0, cx1, cy0, cy1) = StreetMarking.cutBounds(box)
        return (heading + ((cx0 + cx1) / 2 - 0.5) * 360, (0.5 - (cy0 + cy1) / 2) * 180, (cx1 - cx0) * 360)
    }

    static let sides = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    static func side(_ bearing: Double) -> String { sides[Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45) % 8] }

    static func wrap(_ a: Double) -> Double { ((a + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180 }

    /// A look at a facade counts from this much of it in the frame.
    static let enough = 0.2

    /// Why the last photo judged gave no look, for the debug counts.
    nonisolated(unsafe) static var reason = ""

    /// The look a photo gives of the scene's landmark, nil when it shows no
    /// facade (behind the camera, out of the frame, hidden). A quick look
    /// leaves out what hides it, for sorting thousands.
    init?(_ photo: StreetPhoto, in scene: StreetScene, quick: Bool = false) {
        self.photo = photo
        guard !scene.facades.isEmpty, !scene.inside(photo.at) else { Self.reason = "inside the hull"; return nil }
        let toCentre = (atan2(-photo.at.x, -photo.at.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        from = (toCentre + 180).truncatingRemainder(dividingBy: 360)
        // The view's direction: the compass. A panorama looks everywhere, so
        // it is never off, but its picture is still laid out from its compass.
        let look = photo.compass ?? toCentre
        off = photo.pano ? 0 : abs(Self.wrap(look - toCentre))
        let w = Double(photo.width), h = Double(photo.height), l = max(w, h)
        var half = 0.0
        switch photo.pano ? "spherical" : photo.camera {
        case "spherical", "equirectangular": half = 180
        case "fisheye": half = min(90, 0.5 / photo.focal * 180 / .pi)
        default: half = atan(0.5 * w / l / photo.focal) * 180 / .pi
        }
        heading = look
        hfov = min(360, 2 * half)
        // The photo's own worth, the same for every facade.
        let years: Double = photo.captured.map { Date().timeIntervalSince($0) / 31_557_600 } ?? 8
        let fresh = max(0.6, 1 - years * 0.05)
        // Two poses disagreeing cost a little: the agent checks the frame.
        let sure = photo.poseDoubt ? 0.7 : 1.0
        let good = photo.quality.map { 0.5 + 0.5 * $0 } ?? 0.9
        let day = photo.hour.map { $0 >= 7 && $0 <= 19 ? 1.0 : 0.4 } ?? 1
        let worth = fresh * sure * good * day * (photo.pano ? 0.9 : 1) * (photo.fromDevice ? 0.8 : 1)
        // Each facade's samples: facing the camera, not glancing, in the
        // frame, not hidden by another building.
        var seen: [Double] = [], looks: [Double] = [], seenSamples: [[Bool]] = []
        var lo = Double.infinity, hi = -Double.infinity, nearest = Double.infinity
        var rays = 0, blocked = 0
        var perimeter = 0.0, inFrame = 0.0
        // A camera is never really inside a building: a pose that puts it
        // in one (a narrow street, the GPS astray) does not let that
        // building hide the landmark.
        let others = quick ? [] : scene.others.filter { o in
            !(o.bounds.0 <= photo.at.x && o.bounds.2 >= photo.at.x && o.bounds.1 <= photo.at.y && o.bounds.3 >= photo.at.y && o.shape.contains(photo.at))
        }
        for f in scene.facades {
            perimeter += f.length
            var count = 0, rels: [Double] = [], incidence = 0.0, near = Double.infinity, blockedHere = 0
            var flags = [Bool](repeating: false, count: f.samples.count)
            for (i, (s, normal)) in f.samples.enumerated() {
                let d = s - photo.at, dist = simd_length(d)
                guard dist > 2, dist <= 300 else { continue }
                let sine = simd_dot(normal, -d) / dist
                guard sine >= 0.12 else { continue }   // behind the wall's plane, or along it
                let rel = Self.wrap(atan2(d.x, d.y) * 180 / .pi - look)
                guard photo.pano || abs(rel) <= half else { continue }
                if !quick {
                    rays += 1
                    let p0 = photo.at + d * (3 / max(dist, 3)), p1 = photo.at + d * (1 - 1.5 / max(dist, 1.5))
                    let (x0, x1) = (min(p0.x, p1.x), max(p0.x, p1.x)), (y0, y1) = (min(p0.y, p1.y), max(p0.y, p1.y))
                    let ray = Geometry.lineString([p0, p1])
                    if others.contains(where: { o in
                        o.bounds.0 <= x1 && o.bounds.2 >= x0 && o.bounds.1 <= y1 && o.bounds.3 >= y0 && o.shape.intersects(ray) }) {
                        blocked += 1
                        blockedHere += 1
                        continue
                    }
                }
                count += 1
                flags[i] = true
                rels.append(rel)
                incidence += sine
                near = min(near, dist)
            }
            let part = Double(count) / Double(f.samples.count)
            seen.append(part)
            seenSamples.append(flags)
            guard count > 0 else { looks.append(0); continue }
            inFrame += part * f.length
            nearest = min(nearest, near)
            lo = min(lo, rels.min()!)
            hi = max(hi, rels.max()!)
            // Square on from 45°, half as good at 20°; large from 20° of the
            // frame; too near to see it whole (within a fifth of its length),
            // or too far to see its detail.
            let square = min(1, incidence / Double(count) / 0.7)
            let step = f.length / Double(f.samples.count)
            let width = rels.max()! - rels.min()! + atan2(step, near) * 180 / .pi
            let large = min(1, width / 20)
            let close = near < max(8, f.length / 5) ? 0.5 : near > 180 ? 0.5 : 1
            let clear = count + blockedHere > 0 ? Double(count) / Double(count + blockedHere) : 1
            looks.append(part * square * large * close * clear * worth)
        }
        guard let best = looks.indices.max(by: { looks[$0] < looks[$1] }), looks[best] > 0, seen[best] >= Self.enough else {
            Self.reason = rays > 0 && blocked == rays ? "hidden by other buildings" : "no facade in the frame"
            return nil
        }
        self.seen = seen
        self.seenSamples = seenSamples
        self.looks = looks
        self.best = best
        distance = nearest
        guard distance > 5 else { Self.reason = "too near"; return nil }
        coverage = perimeter > 0 ? inFrame / perimeter : 0
        hidden = quick ? 0 : rays == 0 ? 1 : Double(blocked) / Double(rays)
        guard hidden < 0.7 else { Self.reason = "mostly hidden by other buildings"; return nil }
        // The frame: the seen part's bearings across, the top and the foot
        // at the nearest point down.
        let top = atan2(scene.top - 2, max(distance, 1)) * 180 / .pi, bottom = atan2(-2.0, max(distance, 1)) * 180 / .pi
        var x0 = 0.0, x1 = 0.0, y0 = 0.0, y1 = 0.0
        switch photo.pano ? "spherical" : photo.camera {
        case "spherical", "equirectangular":
            // Wide margins: a panorama's compass is often some degrees off.
            x0 = 0.5 + (lo - 20) / 360
            x1 = 0.5 + (hi + 20) / 360
            y0 = 0.5 - min(top + 10, 80) / 180
            y1 = 0.5 - max(bottom - 12, -60) / 180
        case "fisheye":
            func x(_ a: Double) -> Double { 0.5 + photo.focal * l / w * (a * .pi / 180) }
            x0 = x(lo - 2); x1 = x(hi + 2)
            y0 = 0.5 - photo.focal * l / h * (top * .pi / 180); y1 = 0.5 - photo.focal * l / h * (bottom * .pi / 180)
        default:
            func x(_ a: Double) -> Double { 0.5 + photo.focal * l / w * tan(max(-80, min(80, a)) * .pi / 180) }
            x0 = x(lo - 2); x1 = x(hi + 2)
            y0 = 0.5 - photo.focal * l / h * tan(min(top, 80) * .pi / 180); y1 = 0.5 - photo.focal * l / h * tan(bottom * .pi / 180)
        }
        let bx0 = max(0, min(1, x0)), bx1 = max(0, min(1, x1)), by0 = max(0, min(1, y0)), by1 = max(0, min(1, y1))
        box = CGRect(x: bx0, y: by0, width: max(0, bx1 - bx0), height: max(0, by1 - by0))
        share = photo.pano ? min(1, (hi - lo) / 90) : box.width
        guard share > 0.06 else { Self.reason = "a sliver of the frame"; return nil }
        // The photo's worth as a whole: its best look, and what else it shows.
        let mean = perimeter > 0 ? zip(looks, scene.facades).reduce(0.0) { $0 + $1.0 * $1.1.length } / perimeter : 0
        score = 0.6 * looks[best] + 0.4 * mean
    }

    /// The look a Mapillary entry gives: by its computed pose, or by its
    /// device's when the two disagree and the device's shows more (the
    /// frame drawn follows the pose chosen).
    static func best(_ e: [String: Any], in scene: StreetScene, quick: Bool = false) -> StreetView? {
        let computed = StreetPhoto(e, scene).flatMap { StreetView($0, in: scene, quick: quick) }
        guard StreetPhoto.posesDisagree(e, scene), let device = StreetPhoto(e, scene, device: true).flatMap({ StreetView($0, in: scene, quick: quick) }) else { return computed }
        guard let computed else { return device }
        return device.score > computed.score ? device : computed
    }

    /// The facades it shows, best first: "the north facade whole, a third
    /// of the east facade".
    func shows(_ scene: StreetScene) -> String {
        let order = looks.indices.filter { seen[$0] >= Self.enough && looks[$0] > 0 }.sorted { looks[$0] > looks[$1] }
        return order.map { "\(scene.facades[$0].name) \(scene.part($0, seenSamples[$0]))" }.joined(separator: ", ")
    }

    func line(_ scene: StreetScene) -> String {
        let how = photo.pano ? "a panorama, cut to it" : "\(Int(share * 100))% of the frame, \(Int(off))° off"
        let doubts = [photo.poseDoubt ? "its two poses disagree, framed by the \(photo.fromDevice ? "device's" : "computed one")" : nil,
                      photo.fromDevice && !photo.poseDoubt ? "its pose is the device's alone" : nil,
                      (photo.hour ?? 12) < 7 || (photo.hour ?? 12) > 19 ? "at night" : nil]
            .compactMap { $0 }
        return "\(photo.id): \(Int(distance)) m, from the \(Self.side(from)), shows \(shows(scene)), \(how), \(photo.date), by \(photo.author)"
            + (doubts.isEmpty ? "" : " (" + doubts.joined(separator: ", ") + ")")
    }
}

enum StreetPicks {
    /// A look worth a candidate.
    static let worthwhile = 0.05

    /// The candidates, facade by facade: for every facade the photo that
    /// shows it best, then the photos that show what that one does not,
    /// until the facade is seen whole (three at most), or a second look
    /// from another track or from well apart when the first sees it whole,
    /// within `limit` in all, and the facades no photo shows: lines for the
    /// agent, and the picks as they are numbered.
    static func report(_ views: [StreetView], in scene: StreetScene, limit: Int) -> (text: String, picks: [StreetView], firsts: [(facade: Int, view: StreetView)]) {
        guard !views.isEmpty else { return ("", [], []) }
        let facades = scene.facades
        var picks: [StreetView] = []
        var taken: [String: Int] = [:]   // photo id to its number
        var perFacade: [[StreetView]] = Array(repeating: [], count: facades.count)
        var covered: [[Bool]] = facades.map { [Bool](repeating: false, count: $0.samples.count) }
        func fraction(_ f: Int) -> Double { Double(covered[f].filter { $0 }.count) / Double(max(1, covered[f].count)) }
        func gain(_ v: StreetView, _ f: Int) -> Double {
            Double(covered[f].indices.filter { v.seenSamples[f][$0] && !covered[f][$0] }.count) / Double(max(1, covered[f].count))
        }
        func take(_ v: StreetView, for f: Int) {
            if taken[v.photo.id] == nil {
                picks.append(v)
                taken[v.photo.id] = picks.count
            }
            perFacade[f].append(v)
            for i in covered[f].indices where v.seenSamples[f][i] { covered[f][i] = true }
        }
        func pool(_ f: Int) -> [StreetView] {
            views.filter { v in v.looks[f] >= worthwhile && v.seen[f] >= StreetView.enough && !perFacade[f].contains { $0.photo.id == v.photo.id } }
        }
        let order = facades.indices.sorted { facades[$0].length > facades[$1].length }
        // The best look at every facade first, the part of it seen counting
        // twice: a whole facade from a corner before half of it square on.
        for f in order where picks.count < limit {
            if let v = pool(f).max(by: { $0.looks[f] * $0.seen[f] < $1.looks[f] * $1.seen[f] }) { take(v, for: f) }
        }
        // Then the rest of each facade: what shows most of what is not seen
        // yet (a pick made for another facade costs nothing), or a second
        // look at a facade seen whole, at least two fifths as good.
        for f in order where !perFacade[f].isEmpty {
            while picks.count < limit && perFacade[f].count < 3 {
                let rest = pool(f)
                if fraction(f) < 0.85 {
                    guard let v = rest.max(by: { gain($0, f) * (0.5 + $0.looks[f]) < gain($1, f) * (0.5 + $1.looks[f]) }), gain(v, f) >= 0.15 else { break }
                    take(v, for: f)
                } else {
                    guard perFacade[f].count == 1 else { break }
                    let first = perFacade[f][0]
                    guard let v = rest.filter({ $0.looks[f] >= first.looks[f] * 0.4
                        && ($0.photo.sequence != first.photo.sequence || simd_length($0.photo.at - first.photo.at) > 25) })
                        .max(by: { $0.looks[f] * $0.seen[f] < $1.looks[f] * $1.seen[f] }) else { break }
                    take(v, for: f)
                }
            }
        }
        var out: [String] = []
        for f in order {
            let name = facades[f].name.prefix(1).uppercased() + facades[f].name.dropFirst()
            if perFacade[f].isEmpty {
                let any = views.filter { $0.seen[f] >= StreetView.enough }.count
                out.append("\(name) (\(Int(facades[f].length)) m): " + (any == 0 ? "no photo shows it." : "no photo gives a good look at it (\(any) glance at it)."))
                continue
            }
            let whole = fraction(f) > 0.85
            out.append("\(name) (\(Int(facades[f].length)) m), " + (whole ? "seen whole by these:" : "these show \(scene.part(f, covered[f])), no photo the rest:") + "\n"
                       + perFacade[f].map { v in
                           let frames = views.filter { $0.photo.sequence == v.photo.sequence }.count
                           return "  #\(taken[v.photo.id]!) " + v.line(scene) + " (\(frames) frames of its track show the landmark)"
                       }.joined(separator: "\n"))
        }
        return (out.joined(separator: "\n"), picks, order.compactMap { f in perFacade[f].first.map { (f, $0) } })
    }

    /// A contact sheet of the picks: their thumbnails in a grid, the landmark
    /// framed in red on each, numbered as the report numbers them, so the
    /// agent sees at once which really show it.
    static func sheet(_ picks: [StreetView], in scene: StreetScene, thumbs: [URL?], to file: URL) throws {
        let cells = picks.enumerated().map { k, view -> ContactSheet.Cell in
            ContactSheet.Cell(image: thumbs[k], box: view.box, cut: view.photo.pano,
                              label: "#\(k + 1)  \(view.photo.id)  \(Int(view.distance)) m, \(scene.facades[view.best].name)")
        }
        try ContactSheet.draw(cells, to: file)
    }
}

/// A photo and the model from the photo's place, side by side, the same
/// height: what the agent compares.
enum SideBySide {
    static func draw(_ left: URL, _ right: URL, to file: URL, labels: (String, String) = ("photo", "model, from the same place")) throws {
        func read(_ url: URL) -> CGImage? {
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        guard let a = read(left), let b = read(right) else { return }
        let h = 640, gap = 8, label = 24
        let wa = a.width * h / a.height, wb = b.width * h / b.height
        let w = wa + gap + wb
        guard let ctx = CGContext(data: nil, width: w, height: h + label, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h + label))
        ctx.draw(a, in: CGRect(x: 0, y: label, width: wa, height: h))
        ctx.draw(b, in: CGRect(x: wa + gap, y: label, width: wb, height: h))
        for (text, x) in [(labels.0, 4), (labels.1, wa + gap + 4)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 14, nil), .foregroundColor: CGColor(gray: 0.95, alpha: 1)]))
            ctx.textPosition = CGPoint(x: Double(x), y: 6)
            CTLineDraw(line, ctx)
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// A grid of pictures with a label each, and a red frame where one is
/// given: what the user looks at. The agent gets each picture by itself
/// (`one`), larger, since its eyes need the pixels.
enum ContactSheet {
    /// One picture with its frame (the outside dimmed), a panorama cut to
    /// it first, at most `maxSide` across, to a JPEG.
    static func one(_ cell: Cell, maxSide: Int, to file: URL) throws {
        guard let url = cell.image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        var shown = image
        var box = cell.box
        if cell.cut, let b = box, let (part, inner) = StreetMarking.cut(image, b) {
            shown = part
            box = inner
        }
        let scale = min(1, Double(maxSide) / Double(max(shown.width, shown.height)))
        let w = Int(Double(shown.width) * scale), h = Int(Double(shown.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(shown, in: full)
        if let box {
            let frame = CGRect(x: box.minX * Double(w), y: (1 - box.maxY) * Double(h), width: box.width * Double(w), height: box.height * Double(h))
            StreetMarking.mask(ctx, outside: frame, in: full, alpha: 0.55)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
            ctx.setLineWidth(max(3, Double(w) * 0.004))
            ctx.stroke(frame.insetBy(dx: -2, dy: -2))
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    struct Cell {
        let image: URL?
        /// The frame, as fractions of the picture (from the top left).
        let box: CGRect?
        /// Whether to cut the picture to the frame first (a panorama).
        let cut: Bool
        let label: String
    }

    static func draw(_ cells: [Cell], to file: URL) throws {
        let columns = cells.count <= 4 ? 2 : cells.count <= 9 ? 3 : 4, rows = (cells.count + columns - 1) / columns
        let cw = 320, ch = 260, pad = 6
        let w = columns * cw, h = rows * ch
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (k, cell) in cells.enumerated() {
            let col = k % columns, row = k / columns
            // CoreGraphics' y goes up: the first row at the top.
            let area = CGRect(x: col * cw + pad, y: h - (row + 1) * ch + pad + 22, width: cw - 2 * pad, height: ch - 2 * pad - 22)
            if let url = cell.image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                var shown = image
                var box = cell.box
                if cell.cut, let b = box, let (part, inner) = StreetMarking.cut(image, b) {
                    shown = part
                    box = inner
                }
                let scale = min(area.width / Double(shown.width), area.height / Double(shown.height))
                let dw = Double(shown.width) * scale, dh = Double(shown.height) * scale
                let at = CGRect(x: area.midX - dw / 2, y: area.midY - dh / 2, width: dw, height: dh)
                ctx.draw(shown, in: at)
                if let box {
                    let frame = CGRect(x: at.minX + box.minX * dw, y: at.minY + (1 - box.maxY) * dh, width: box.width * dw, height: box.height * dh)
                    // Dimmed, not painted over: the agent judges the pose by what is around.
                    StreetMarking.mask(ctx, outside: frame, in: at, alpha: 0.65)
                    ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
                    ctx.setLineWidth(3)
                    ctx.stroke(frame.insetBy(dx: -1.5, dy: -1.5))
                }
            }
            let text = NSAttributedString(string: cell.label, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 13, nil), .foregroundColor: CGColor(gray: 0.95, alpha: 1)])
            let line = CTLineCreateWithAttributedString(text)
            ctx.textPosition = CGPoint(x: Double(col * cw + pad), y: Double(h - (row + 1) * ch + pad))
            CTLineDraw(line, ctx)
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// A kept photo marked: everything but the landmark painted black and the
/// landmark framed in red, a panorama cut to it first.
enum StreetMarking {
    /// Paints everything outside `rect` black, `alpha` deep.
    static func mask(_ ctx: CGContext, outside rect: CGRect, in full: CGRect, alpha: Double) {
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(rect)
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
        ctx.fill(full)
        ctx.restoreGState()
    }

    /// A panorama cut around the landmark's box: the part, and the box
    /// within it.
    /// The cut around a panorama's box, as fractions: west, east, top, bottom.
    static func cutBounds(_ box: CGRect) -> (Double, Double, Double, Double) {
        (max(0, box.minX - 0.03), min(1, box.maxX + 0.03), max(0, box.minY - 0.04), min(1, box.maxY + 0.03))
    }

    static func cut(_ image: CGImage, _ box: CGRect) -> (CGImage, CGRect)? {
        let w = Double(image.width), h = Double(image.height)
        let (cx0, cx1, cy0, cy1) = cutBounds(box)
        let rect = CGRect(x: cx0 * w, y: cy0 * h, width: (cx1 - cx0) * w, height: (cy1 - cy0) * h).integral
        guard rect.width > 50, rect.height > 50, let part = image.cropping(to: rect) else { return nil }
        return (part, CGRect(x: (box.minX - cx0) / (cx1 - cx0), y: (box.minY - cy0) / (cy1 - cy0),
                             width: box.width / (cx1 - cx0), height: box.height / (cy1 - cy0)))
    }

    static func mark(_ file: URL, _ view: StreetView, maxSide: Int = 1280) throws {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw NSError(domain: "StreetMarking", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read the picture"])
        }
        var shown = image
        var box = view.box
        if view.photo.pano, let (part, inner) = cut(image, box) {
            shown = part
            box = inner
        }
        let scale = min(1, Double(maxSide) / Double(max(shown.width, shown.height)))
        let w = Int(Double(shown.width) * scale), h = Int(Double(shown.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.draw(shown, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics' y goes up: the box's fractions are from the top.
        let rect = CGRect(x: box.minX * Double(w), y: (1 - box.maxY) * Double(h), width: box.width * Double(w), height: box.height * Double(h))
            .insetBy(dx: -3, dy: -3)
        mask(ctx, outside: rect, in: CGRect(x: 0, y: 0, width: w, height: h), alpha: 1)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
        ctx.setLineWidth(max(3, Double(w) * 0.004))
        ctx.stroke(rect)
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// Mapillary's coverage tiles (Mapbox vector tiles, zoom 14, the `image`
/// layer: every photo as a point with its id, compass angle, date, pano
/// flag and sequence): the complete and steady list of what is there,
/// where the Graph API's box search answers with a different sample every
/// time. Only what the points need of the protobuf is read.
enum CoverageTile {
    struct Point {
        let lon: Double, lat: Double
        let props: [String: Any]
    }

    static let zoom = 14

    /// The tile holding a longitude and latitude.
    static func tile(lon: Double, lat: Double) -> (x: Int, y: Int) {
        let n = Double(1 << zoom), r = lat * .pi / 180
        return (Int((lon + 180) / 360 * n), Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n))
    }

    /// The points of a tile's `image` layer, in longitude and latitude.
    static func points(_ data: Data, x: Int, y: Int) -> [Point] {
        var out: [Point] = []
        let n = Double(1 << zoom)
        var tile = Reader(Array(data))
        while let (field, wire) = tile.key() {
            guard field == 3, wire == 2, let layer = tile.bytes() else { tile.skip(wire); continue }
            var r = Reader(layer)
            var name = "", extent = 4096.0
            var keys: [String] = [], values: [Any] = [], features: [[UInt8]] = []
            while let (f, w) = r.key() {
                switch (f, w) {
                case (1, 2): name = r.string() ?? ""
                case (2, 2): if let b = r.bytes() { features.append(b) }
                case (3, 2): keys.append(r.string() ?? "")
                case (4, 2): if let b = r.bytes() { values.append(value(b)) }
                case (5, 0): extent = Double(r.varint())
                default: r.skip(w)
                }
            }
            guard name == "image" else { continue }
            for feature in features {
                var fr = Reader(feature)
                var tags: [UInt64] = [], geometry: [UInt64] = [], type = 0
                while let (f, w) = fr.key() {
                    switch (f, w) {
                    case (2, 2): tags = fr.packed()
                    case (3, 0): type = Int(fr.varint())
                    case (4, 2): geometry = fr.packed()
                    default: fr.skip(w)
                    }
                }
                guard type == 1, geometry.count >= 3, geometry[0] & 7 == 1 else { continue }
                var props: [String: Any] = [:]
                for i in stride(from: 0, to: tags.count - 1, by: 2) where Int(tags[i]) < keys.count && Int(tags[i + 1]) < values.count {
                    props[keys[Int(tags[i])]] = values[Int(tags[i + 1])]
                }
                let px = Double(zigzag(geometry[1])), py = Double(zigzag(geometry[2]))
                let lon = (Double(x) + px / extent) / n * 360 - 180
                let lat = atan(sinh(.pi * (1 - 2 * (Double(y) + py / extent) / n))) * 180 / .pi
                out.append(Point(lon: lon, lat: lat, props: props))
            }
        }
        return out
    }

    static func zigzag(_ v: UInt64) -> Int64 { Int64(v >> 1) ^ -Int64(v & 1) }

    static func value(_ bytes: [UInt8]) -> Any {
        var r = Reader(bytes)
        while let (f, w) = r.key() {
            switch (f, w) {
            case (1, 2): return r.string() ?? ""
            case (2, 5): return Double(Float(bitPattern: UInt32(r.fixed(4))))
            case (3, 1): return Double(bitPattern: r.fixed(8))
            case (4, 0): return Int64(bitPattern: r.varint())
            case (5, 0): return r.varint()
            case (6, 0): return zigzag(r.varint())
            case (7, 0): return r.varint() != 0
            default: r.skip(w)
            }
        }
        return ""
    }

    /// A protobuf reader of the little a tile needs.
    struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func varint() -> UInt64 {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let byte = b[i]
                i += 1
                v |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return v
        }

        mutating func key() -> (Int, Int)? {
            guard i < b.count else { return nil }
            let k = varint()
            return (Int(k >> 3), Int(k & 7))
        }

        mutating func bytes() -> [UInt8]? {
            let n = Int(varint())
            guard i + n <= b.count else { i = b.count; return nil }
            defer { i += n }
            return Array(b[i..<(i + n)])
        }

        mutating func string() -> String? { bytes().flatMap { String(bytes: $0, encoding: .utf8) } }

        mutating func packed() -> [UInt64] {
            guard let inner = bytes() else { return [] }
            var r = Reader(inner), out: [UInt64] = []
            while r.i < inner.count { out.append(r.varint()) }
            return out
        }

        mutating func fixed(_ n: Int) -> UInt64 {
            var v: UInt64 = 0
            for k in 0..<n where i + k < b.count { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
            i += n
            return v
        }

        mutating func skip(_ wire: Int) {
            switch wire {
            case 0: _ = varint()
            case 1: i += 8
            case 2: _ = bytes()
            case 5: i += 4
            default: i = b.count
            }
        }
    }
}
