import Foundation
import Geometry

/// A marking of the road document, by its parameters (RoadDocument.swift
/// has the format). Coordinates in whatever frame the caller works in: lon
/// and lat in the file, local metres in the build.
public struct Mark {
    public var id = ""
    public var kind: String              // line, zebra, zigzag, letter
    public var style = "dashed"          // line: solid, dashed, double
    public var colour = "white"          // line: white, yellow
    public var points: [P2] = []         // line, zigzag (its baseline)
    public var centre: P2?               // zebra, letter
    public var heading = 0.0             // zebra, letter: degrees counter-clockwise from east
    public var span = 0.0                // zebra: kerb to kerb
    public var bar = Markings.zebraBar
    public var length = Markings.zebraWidth
    public var side = 1                  // zigzag: the roadway on the left (1) or right (-1)
    public var step = Markings.zigzagStep
    public var depth = Markings.zigzagDepth
    public var text = "A"                // letter

    public init(kind: String) { self.kind = kind }
}

/// Road markings, in two halves. The road document keeps every marking as
/// a few parameters, so the editor can move and reshape it:
///
/// - seeding, from OSM (none taken from osm2streets: its stop lines step
///   from lane to lane and its lines stray from the smoothed roadway):
///   `zebras`, `laneLines`, `busStops` and `busLetters` give the markings'
///   parameters, in local metres;
/// - building, from the parameters: `zebraBars`, `linePaint`, `zigzagPaint`
///   and `letterPaint` give polygons in local metres, laid on the roadway by
///   Ground. The editor draws them the same way.
///
/// The markings:
///
/// - Lane lines: a centre line on a two-way road, a double solid from four
///   lanes, broken lines between lanes, by the road's width and `lanes`,
///   stopping `meetClear` short of where roads meet. A line is its points
///   and a style: solid, dashed (`dash`, from its first point) or double
///   (two solids `double` either side of its points).
/// - Zebras: every `footway=crossing` way over the roadway and every
///   `highway=crossing` node on a road, merged where they mark one place. A
///   zebra is its centre, its heading (the way its bars run, along the
///   road), its span across the road from kerb to kerb, the bar's width and
///   length. Its bars are `bar` wide with gaps as wide, clear of each kerb
///   by `zebraKerb`, laid where the roadway is crossed shortest (within
///   `zebraTurn` of square to the centre line). A bar the roadway cannot
///   hold whole is left out, never cut. Other markings are wiped from the
///   zebra's zone.
/// - Bus stops: from each `highway=bus_stop` or `public_transport=platform`,
///   the nearest kerb takes a zigzag `zigzagLength` long inside the roadway.
///   A zigzag is its baseline along the kerb (two points), the side of it
///   the roadway lies on (1: left of the baseline's direction, -1: right),
///   its step and depth.
/// - Bus lanes: the letter A every `busLetterStep` along each bus lane,
///   upright along the lane. A letter is its centre and heading (the way its
///   top points).
///
/// Headings are degrees counter-clockwise from east, in local metres (the
/// Mercator projection keeps angles).
public enum Markings {
    public static let zebraBar = 0.5
    public static let zebraWidth = 4.0
    static let zigzagLength = 20.0
    public static let zigzagStep = 2.0
    public static let zigzagDepth = 0.9
    public static let zigzagInset = 0.4      // the zigzag's near points, off the kerb
    public static let zigzagLine = 0.15
    static let busLetterStep = 45.0
    public static let busLetterSize = (1.4, 2.6)
    /// The letter A in a unit box, its crossbar's hole cut out.
    public static let letterA: [[P2]] = [
        [P2(0, 0), P2(0.36, 1), P2(0.64, 1), P2(1, 0), P2(0.77, 0), P2(0.68, 0.28), P2(0.32, 0.28), P2(0.23, 0)],
        [P2(0.38, 0.43), P2(0.5, 0.78), P2(0.62, 0.43)],
    ]

    static let vehicle: Set<String> = ["primary", "secondary", "tertiary", "unclassified", "residential",
                                       "living_street", "service", "primary_link", "secondary_link", "tertiary_link"]
    public static let zebraKerb = 0.4      // kept clear of each kerb
    static let zebraMerge = 6.0     // crossings closer than this are one
    static let zebraTurn = 25.0     // degrees a zebra may turn from the centre line to cross the roadway shortest
    static let zebraTurnSteps = 10
    static let stopMerge = 15.0     // bus stops closer than this (a platform and its stop) are one

    // MARK: Zebras

    /// The zebra at `point` laid square to the road: its bars run with the
    /// road's centre line `road`, side by side across the whole roadway.
    /// nil if the roadway holds fewer than three bars.
    static func zebra(_ point: Geometry, _ road: Geometry, _ roadway: Geometry) -> Mark? {
        let s = road.project(point)
        let a = road.interpolate(max(0, s - 2)).xy, c = road.interpolate(min(road.length, s + 2)).xy
        if simd_length(c - a) < 1e-6 { return nil }
        let heading = atan2(c.y - a.y, c.x - a.x)
        // The centre line only hints at the road's direction: the zebra is
        // laid where the roadway itself is crossed shortest, turning up to
        // zebraTurn either way from the centre line.
        var best: (Geometry, Double)?
        let p = point.xy
        for k in -zebraTurnSteps...zebraTurnSteps {
            let h = heading + zebraTurn * .pi / 180 * Double(k) / Double(zebraTurnSteps)
            let q = P2(-sin(h), cos(h))
            let across = Geometry.lineString([p - q * 40, p + q * 40])
            let pieces = across.intersection(roadway).lines.filter { $0.length > 2 }
            if let piece = pieces.min(by: { $0.distance(point) < $1.distance(point) }) {
                if best == nil || piece.length < best!.0.length - 0.05 { best = (piece, h) }
            }
        }
        guard let (section, h) = best else { return nil }
        var z = Mark(kind: "zebra")
        z.centre = section.interpolate(0.5, normalized: true).xy
        z.heading = h * 180 / .pi
        z.span = section.length
        return zebraBars(z, roadway) != nil ? z : nil
    }

    /// A zebra's bars and the zone it wipes other markings from, or nil
    /// when fewer than three bars are whole on `roadway` (with no roadway,
    /// all of them).
    public static func zebraBars(_ z: Mark, _ roadway: Geometry?) -> (Geometry, Geometry)? {
        let h = z.heading * .pi / 180
        let u = P2(cos(h), sin(h))          // along the road
        let q = P2(-u.y, u.x)               // across it
        let c = z.centre ?? .zero
        let usable = z.span - 2 * zebraKerb
        let count = Int(((usable + z.bar) / (2 * z.bar)).rounded(.down))
        if count < 3 { return nil }
        func rect(_ t: Double, _ halfAcross: Double, _ halfAlong: Double) -> Geometry {
            let m = c + q * t
            return .polygon([(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sa, sl in
                m + q * (sa * halfAcross) + u * (sl * halfAlong)
            })
        }
        let first = -Double(count * 2 - 1) * z.bar / 2 + z.bar / 2
        var bars = (0..<count).map { rect(first + Double($0) * 2 * z.bar, z.bar / 2, z.length / 2) }
        if let roadway {
            bars = bars.filter { roadway.intersection($0).area >= 0.97 * $0.area }
        }
        if bars.count < 3 { return nil }
        return (.unaryUnion(bars), rect(0, z.span / 2 + 0.5, z.length / 2 + 0.8))
    }

    /// One zebra for every crossing: `footway=crossing` ways over the
    /// roadway and `highway=crossing` nodes on a road, merged where they mark
    /// the same place.
    static func zebras(_ osm: Osm, _ roadway: Geometry, _ work: Geometry) -> [Mark] {
        let roads = osm.lines().filter { vehicle.contains($0.tags["highway"] ?? "") && $0.tags["tunnel"] == nil
            && $0.line.intersects(work) }.map(\.line)
        if roads.isEmpty { return [] }
        let tree = STRtree(roads)
        var spots: [Geometry] = []
        for (_, tags, line) in osm.lines() {
            if tags["footway"] != "crossing" || !line.intersects(roadway) || !line.intersects(work) { continue }
            for piece in line.intersection(roadway).lines where piece.length >= 1 {
                spots.append(piece.interpolate(0.5, normalized: true))
            }
        }
        let near = roadway.buffer(0.5)
        for id in osm.nodeOrder {
            let tags = osm.nodes[id]!.tags
            if tags["highway"] == "crossing" && tags["crossing"] != "no" {
                let p = Geometry.point(osm.point(id))
                if work.contains(p) && near.contains(p) { spots.append(p) }
            }
        }
        var made: [Mark] = [], placed: [Geometry] = []
        for p in spots {
            if placed.contains(where: { p.distance($0) < zebraMerge }) { continue }
            guard let i = tree.nearest(p) else { continue }
            let road = roads[i]
            if road.distance(p) > 12 { continue }
            if let z = zebra(p, road, roadway) {
                made.append(z)
                placed.append(p)
            }
        }
        return made
    }

    // MARK: Lane lines

    public static let line = 0.15              // a painted line's width
    public static let dash = (3.0, 6.0)        // a broken line: dash and gap
    public static let double = 0.2             // half the space between the two lines of a double solid
    static let laneWidth = 3.3          // when OSM gives lanes but no width
    static let meetClear = 1.5          // lane lines stop this short of where roads meet

    /// The line moved d to its left (negative: to its right).
    static func offsetLine(_ line: Geometry, _ d: Double) -> Geometry? {
        let pieces = line.offsetCurve(d, quadSegs: 2, join: .round).lines.filter { !$0.isEmpty }
        return pieces.max { $0.length < $1.length }
    }

    /// A line marking as polygons: solid, dashed from its first point, or
    /// double (two solids either side of its points).
    public static func linePaint(_ m: Mark) -> [Geometry] {
        if m.points.count < 2 { return [] }
        let l = Geometry.lineString(m.points)
        if m.style == "double" {
            return [double, -double].flatMap { stroke(offsetLine(l, $0), broken: false) }
        }
        return stroke(l, broken: m.style == "dashed")
    }

    static func stroke(_ l: Geometry?, broken: Bool) -> [Geometry] {
        guard let l, l.length >= 1 else { return [] }
        if !broken { return [l.buffer(line / 2, cap: .flat)] }
        var out: [Geometry] = []
        var at = 0.0
        while at < l.length {
            let piece = l.substring(at, min(l.length, at + dash.0))
            if piece.length > 0.5 { out.append(piece.buffer(line / 2, cap: .flat)) }
            at += dash.0 + dash.1
        }
        return out
    }

    /// The lengthwise markings of every vehicle road, drawn from its OSM
    /// tags rather than taken from osm2streets: a centre line on a two-way
    /// road (a double solid from four lanes, broken below), broken lines
    /// between the lanes of each direction, laid on the road's centre line by
    /// its width and `lanes`. They stop meetClear short of where roads meet
    /// and stay on the roadway. A road with no `lanes` gets a centre line only
    /// if it is two-way and wide enough. One line marking per piece left.
    static func laneLines(_ osm: Osm, _ roadway: Geometry, _ meets: Geometry?, _ work: Geometry) -> [Mark] {
        var made: [(Geometry?, String)] = []
        for (_, tags, l) in osm.lines() {
            let kind = tags["highway"] ?? ""
            if !vehicle.contains(kind) || tags["tunnel"] != nil || tags["area"] == "yes" || !l.intersects(work) { continue }
            if kind == "service" && tags["lanes"] == nil { continue }
            let lanes = length(tags["lanes"]).flatMap { $0 != 0 ? Int($0) : nil }
            let oneway = ["yes", "1", "-1"].contains(tags["oneway"] ?? "") || tags["junction"] == "roundabout"
            var width = length(tags["width"]).flatMap { $0 != 0 ? $0 : nil } ?? lanes.map { Double($0) * laneWidth }
            if !oneway && (lanes == nil || lanes == 1) && (width ?? 0) < 5.5 { continue }
            if width == nil { width = 7 }
            let w = width!
            let lane = lanes.map { w / Double($0) } ?? w / 2
            if oneway {
                for k in stride(from: 1, to: lanes ?? 1, by: 1) {
                    made.append((offsetLine(l, -w / 2 + Double(k) * lane), "dashed"))
                }
            } else {
                let all = lanes ?? 2
                let forward = length(tags["lanes:forward"]).flatMap { $0 != 0 ? Int($0) : nil } ?? (all + 1) / 2
                let backward = all - forward
                made.append((l, all >= 4 ? "double" : "dashed"))
                // Forward lanes lie to the right of the way's direction.
                for k in stride(from: 1, to: forward, by: 1) { made.append((offsetLine(l, -Double(k) * lane), "dashed")) }
                for k in stride(from: 1, to: backward, by: 1) { made.append((offsetLine(l, Double(k) * lane), "dashed")) }
            }
        }
        var keep = roadway.buffer(-0.3)
        if let meets, !meets.isEmpty { keep = keep.difference(meets.buffer(meetClear)) }
        var out: [Mark] = []
        for (l, style) in made {
            guard let l else { continue }
            for piece in l.intersection(keep).lines where piece.length >= 1 {
                var m = Mark(kind: "line")
                m.style = style
                m.points = piece.coords
                out.append(m)
            }
        }
        return out
    }

    // MARK: Bus stops

    /// Where each bus stop meets the kerb: from every `highway=bus_stop` or
    /// `public_transport=platform` node within 12 m of the roadway, the
    /// nearest point of the kerb, the kerb's direction there and the normal
    /// into the roadway, both unit. Stops closer than stopMerge are one.
    static func stopKerbs(_ osm: Osm, _ roadway: Geometry, _ work: Geometry) -> [(P2, P2, P2)] {
        let edge = roadway.boundary
        var found: [(P2, P2, P2)] = []
        for id in osm.nodeOrder {
            let tags = osm.nodes[id]!.tags
            if tags["highway"] != "bus_stop" && tags["public_transport"] != "platform" { continue }
            let p = Geometry.point(osm.point(id))
            if !work.contains(p) || roadway.distance(p) > 12 { continue }
            let onKerb = edge.nearestPoints(p).0
            if found.contains(where: { simd_length($0.0 - onKerb) < stopMerge }) { continue }
            let s = edge.project(.point(onKerb))
            let a = edge.interpolate(s - zigzagLength / 2).xy, b = edge.interpolate(s + zigzagLength / 2).xy
            let n = simd_length(b - a)
            if n < zigzagLength * 0.6 { continue }
            let u = (b - a) / n
            var normal = P2(-u.y, u.x)
            if !roadway.contains(onKerb + normal) { normal = -normal }
            found.append((onKerb, u, normal))
        }
        return found
    }

    /// The zigzag of every stop of `stopKerbs`, its baseline along the kerb,
    /// the roadway on its left.
    static func busStops(_ stops: [(P2, P2, P2)]) -> [Mark] {
        stops.map { onKerb, dir, n in
            var u = dir
            if u.x * n.y - u.y * n.x < 0 { u = -u }
            let h = zigzagLength / 2
            var m = Mark(kind: "zigzag")
            m.points = [onKerb - u * h, onKerb + u * h]
            return m
        }
    }

    /// A zigzag as a polygon: from its baseline, zigzagInset into the
    /// roadway, out to the depth and back every step.
    public static func zigzagPaint(_ m: Mark) -> Geometry? {
        guard m.points.count >= 2 else { return nil }
        let a = m.points[0], b = m.points[1]
        let run = simd_length(b - a)
        if run < 1 { return nil }
        let u = (b - a) / run
        let n = P2(-u.y, u.x) * Double(m.side)
        let steps = max(1, Int((run / m.step).rounded(.toNearestOrEven)))
        let pts = (0...steps).map { k -> P2 in
            let t = Double(k) * run / Double(steps)
            return a + u * t + n * (zigzagInset + (k % 2 == 1 ? m.depth : 0))
        }
        return Geometry.lineString(pts).buffer(zigzagLine / 2, cap: .flat, join: .mitre)
    }

    // MARK: Bus lanes

    /// Where the letters A of the bus lanes go: centres and headings.
    static func busLetters(_ busLanes: [Geometry]) -> [Mark] {
        var made: [Mark] = []
        for lane in busLanes {
            for poly in lane.polygons {
                let c = poly.minimumRotatedRectangle.exterior
                guard c.count >= 3 else { continue }
                let sides = (0..<2).map { (simd_length(c[$0 + 1] - c[$0]), $0) }
                let (run, i) = sides.max { $0.0 < $1.0 }!
                if run < busLetterStep * 0.6 { continue }
                let angle = atan2(c[i + 1].y - c[i].y, c[i + 1].x - c[i].x) * 180 / .pi
                let u = P2(cos(angle * .pi / 180), sin(angle * .pi / 180))
                let centre = poly.minimumRotatedRectangle.centroid.xy
                let count = max(1, Int((run / busLetterStep).rounded(.down)))
                let inner = poly.buffer(-0.3)
                for k in 0..<count {
                    let t = (Double(k) + 0.5) * run / Double(count) - run / 2
                    let p = centre + u * t
                    if inner.contains(p) {
                        var m = Mark(kind: "letter")
                        m.centre = p
                        m.heading = angle
                        made.append(m)
                    }
                }
            }
        }
        return made
    }

    /// The letter A, its top pointing along its heading.
    public static func letterPaint(_ m: Mark) -> Geometry {
        let (w, h) = busLetterSize
        let letter = Geometry.polygon(letterA[0], holes: [letterA[1]])
        return letter.scale(w, h, origin: .zero).translate(-w / 2, -h / 2)
            .rotate(m.heading - 90, origin: .zero).translate((m.centre ?? .zero).x, (m.centre ?? .zero).y)
    }
}

import simd
