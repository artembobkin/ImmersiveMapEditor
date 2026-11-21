import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// A Mapillary track (a sequence: one car's or walker's pass) read off the
/// coverage tiles, its frames in the order taken: what tells a photo's pose
/// from a mistake (the user's design, 2026-10-27, after a third of the
/// photos kept showed another building). A photo's place must run smoothly
/// with its neighbours', its track must keep to the street (not cross a
/// building), a dashcam's look follows the way it goes (a missing or stray
/// compass is replaced by it), and the facade the photo shows must be seen
/// from its neighbouring frames too: one frame alone that sees it is a
/// mistake of its pose more often than not.
struct StreetTrack {
    struct Frame {
        let id: String
        let at: P2
        let compass: Double?
        let time: Double
        let pano: Bool
    }
    let frames: [Frame]
    let index: [String: Int]
    /// Its camera looks the way it goes (a dashcam's): of its frames with a
    /// way and a compass, three in four have the compass within 30° of it.
    let forward: Bool
    /// It has no compass: every angle missing or 0.
    let compassless: Bool

    init(_ frames: [Frame]) {
        // A photo by a tile's edge comes in both tiles: once.
        var ids = Set<String>()
        let sorted = frames.filter { ids.insert($0.id).inserted }.sorted { $0.time < $1.time }
        self.frames = sorted
        index = Dictionary(sorted.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        compassless = sorted.allSatisfy { ($0.compass ?? 0) == 0 }
        var agree = 0, total = 0
        for i in sorted.indices {
            guard let c = Self.course(sorted, i), let a = sorted[i].compass, a != 0 else { continue }
            total += 1
            if abs(StreetView.wrap(a - c)) < 30 { agree += 1 }
        }
        forward = total >= 3 && Double(agree) >= 0.75 * Double(total)
    }

    /// Which way it went at a frame, from the frame before to the frame
    /// after; nil standing still (under 3 m).
    static func course(_ f: [Frame], _ i: Int) -> Double? {
        let d = f[min(f.count - 1, i + 1)].at - f[max(0, i - 1)].at
        guard simd_length(d) >= 3 else { return nil }
        return (atan2(d.x, d.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The heading to judge a frame by: its compass; the way it went when
    /// it has none (0 is none); the way a dashcam went when its compass
    /// strays from it by more than 30°. nil and why when there is none.
    func heading(at i: Int, compass: Double?) -> (heading: Double?, note: String?) {
        let way = Self.course(frames, i)
        guard let compass, compass != 0, !compassless else {
            guard let way else { return (nil, "no compass, standing still") }
            return (way, "no compass: looking the way it went")
        }
        if forward, let way, abs(StreetView.wrap(compass - way)) > 30 {
            return (way, "its compass strays from the way its dashcam went: looking the way it went")
        }
        return (compass, nil)
    }

    /// Whether a photo of the track is borne out by it: its place smooth
    /// with its neighbours', its path clear of buildings, its heading, and
    /// its best facade seen from two of its four nearest frames too. The
    /// photo to judge by (heading corrected, the neighbours counted), or
    /// why not.
    func confirm(_ photo: StreetPhoto, in scene: StreetScene) -> (photo: StreetPhoto?, why: String) {
        guard let i = index[photo.id] else { return (nil, "not in its track") }
        guard i > 0, i < frames.count - 1 else { return (nil, frames.count < 3 ? "its track is too short to bear it out" : "at its track's end, nothing to bear it out on one side") }
        // Its place on the line between the frames before and after it, at
        // the time it was taken.
        let before = frames[i - 1], after = frames[i + 1]
        let span = after.time - before.time
        let t = span > 0 ? max(0, min(1, (frames[i].time - before.time) / span)) : 0.5
        let expected = before.at + (after.at - before.at) * t
        let off = simd_length(photo.at - expected), allowed = 6 + 0.3 * simd_length(after.at - before.at)
        guard off <= allowed else { return (nil, "its place jumps \(Int(off)) m off its track") }
        // The street: the path through it and two frames each side.
        var path = frames[max(0, i - 2)...min(frames.count - 1, i + 2)].map(\.at)
        path[i - max(0, i - 2)] = photo.at
        guard !scene.throughBuilding(path) else { return (nil, "its track runs through a building: its GPS strayed") }
        var judged = photo
        if !photo.pano {
            let (h, note) = heading(at: i, compass: photo.compass)
            guard let h else { return (nil, note ?? "no heading") }
            judged.compass = h
            judged.headingNote = note
        } else if (photo.compass ?? 0) == 0 {
            return (nil, "a panorama without a compass: where it is cut is unknown")
        }
        guard let view = StreetView(judged, in: scene, quick: true) else { return (nil, "no facade in the frame by its corrected heading") }
        // Its neighbours, each by its own place and heading, must see the
        // same facade.
        var seen = 0
        for j in max(0, i - 2)...min(frames.count - 1, i + 2) where j != i {
            let n = frames[j]
            let h = n.pano ? (n.compass ?? 0) : heading(at: j, compass: n.compass).heading
            guard let h else { continue }
            let other = StreetPhoto(id: n.id, at: n.at, compass: h, focal: photo.focal, width: photo.width, height: photo.height, pano: n.pano)
            if let v = StreetView(other, in: scene, quick: true, central: false), v.seen[view.best] >= StreetView.enough { seen += 1 }
        }
        guard seen >= 2 else { return (nil, "\(seen == 0 ? "none" : "only one") of its neighbouring frames sees \(scene.facades[view.best].name): one frame alone is a mistake of its pose") }
        judged.confirmedBy = seen
        return (judged, "")
    }
}
