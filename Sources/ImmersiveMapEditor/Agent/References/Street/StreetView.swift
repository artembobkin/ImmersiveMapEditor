import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

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
        guard photo.pano else { return (heading, photo.pitch ?? 0, hfov) }
        let (cx0, cx1, cy0, cy1) = StreetMarking.cutBounds(box)
        return (heading + ((cx0 + cx1) / 2 - 0.5) * 360, (0.5 - (cy0 + cy1) / 2) * 180, (cx1 - cx0) * 360)
    }

    static let sides = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    static func side(_ bearing: Double) -> String { sides[Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45) % 8] }

    static func wrap(_ a: Double) -> Double { ((a + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180 }

    /// A look at a facade counts from this much of it in the frame.
    static let enough = 0.2

    /// Degrees a compass may be off: a candidate keeps the landmark inside
    /// the frame by this much.
    static let edgeMargin = 12.0

    /// Why the last photo judged gave no look, for the debug counts.
    nonisolated(unsafe) static var reason = ""

    /// The look a photo gives of the scene's landmark, nil when it shows no
    /// facade (behind the camera, out of the frame, hidden). A quick look
    /// leaves out what hides it, for sorting thousands. A `central` look
    /// has the landmark well inside the frame (`edgeMargin`): a candidate's,
    /// not a neighbouring frame's or a kept photo's.
    init?(_ photo: StreetPhoto, in scene: StreetScene, quick: Bool = false, central: Bool = true) {
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
        // Up and down in the frame by the camera's tilt, when known.
        let tilt = photo.pano ? 0 : photo.pitch ?? 0
        let up = top - tilt, down = bottom - tilt
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
            y0 = 0.5 - photo.focal * l / h * (up * .pi / 180); y1 = 0.5 - photo.focal * l / h * (down * .pi / 180)
        default:
            func x(_ a: Double) -> Double { 0.5 + photo.focal * l / w * tan(max(-80, min(80, a)) * .pi / 180) }
            x0 = x(lo - 2); x1 = x(hi + 2)
            y0 = 0.5 - photo.focal * l / h * tan(max(-80, min(up, 80)) * .pi / 180); y1 = 0.5 - photo.focal * l / h * tan(max(-80, min(down, 80)) * .pi / 180)
        }
        let bx0 = max(0, min(1, x0)), bx1 = max(0, min(1, x1)), by0 = max(0, min(1, y0)), by1 = max(0, min(1, y1))
        box = CGRect(x: bx0, y: by0, width: max(0, bx1 - bx0), height: max(0, by1 - by0))
        share = photo.pano ? min(1, (hi - lo) / 90) : box.width
        guard share > 0.06 else { Self.reason = "a sliver of the frame"; return nil }
        // Well inside the frame: with its compass a little off either way
        // (`edgeMargin`), a quarter of the frame's width still holds the
        // landmark. One at the frame's edge is a sliver in the picture, or
        // out of it (the user, 2026-10-27).
        if central && !photo.pano {
            let margin = min(Self.edgeMargin, half * 0.35)
            let inner = max(0, min(hi, half - margin) - max(lo, -half + margin))
            guard inner >= 0.25 * 2 * half else { Self.reason = "at the frame's edge"; return nil }
            // Up and down the same, by its tilt: a camera turned to the sky
            // or the pavement holds the landmark in a strip at the frame's
            // edge, or not at all (the user, 2026-10-27). A quarter of the
            // frame's height must hold it.
            if photo.pitch != nil {
                let vhalf = (photo.camera == "fisheye" ? 0.5 * h / l / photo.focal * 180 / .pi : atan(0.5 * h / l / photo.focal) * 180 / .pi)
                let held = max(0, min(up, vhalf) - max(down, -vhalf))
                guard held >= 0.25 * 2 * vhalf else { Self.reason = "tilted away from it"; return nil }
            }
        }
        // The photo's worth as a whole: its best look, and what else it shows.
        let mean = perimeter > 0 ? zip(looks, scene.facades).reduce(0.0) { $0 + $1.0 * $1.1.length } / perimeter : 0
        score = 0.6 * looks[best] + 0.4 * mean
    }

    /// The facades it shows, best first: "the north facade whole, a third
    /// of the east facade".
    func shows(_ scene: StreetScene) -> String {
        let order = looks.indices.filter { seen[$0] >= Self.enough && looks[$0] > 0 }.sorted { looks[$0] > looks[$1] }
        return order.map { "\(scene.facades[$0].name) \(scene.part($0, seenSamples[$0]))" }.joined(separator: ", ")
    }

    func line(_ scene: StreetScene) -> String {
        let how = photo.pano ? "a panorama, cut to it" : "\(Int(share * 100))% of the frame, \(Int(off))° off"
        let doubts = [photo.confirmedBy > 0 ? "borne out by \(photo.confirmedBy) neighbouring frames of its track" : nil,
                      photo.headingNote, photo.fromDevice ? "its pose is the device's alone" : nil,
                      (photo.hour ?? 12) < 7 || (photo.hour ?? 12) > 19 ? "at night" : nil]
            .compactMap { $0 }
        return "\(photo.id): \(Int(distance)) m, from the \(Self.side(from)), shows \(shows(scene)), \(how), \(photo.date), by \(photo.author)"
            + (doubts.isEmpty ? "" : " (" + doubts.joined(separator: ", ") + ")")
    }
}
