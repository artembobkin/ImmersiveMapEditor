import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// One photo, as Mapillary describes it.
struct StreetPhoto {
    let id: String
    /// Where the camera stands, in the scene's metres.
    let at: P2
    /// Which way it looks, a compass bearing (its track's way when the
    /// compass is missing or strays: `headingNote` says so).
    var compass: Double?
    var headingNote: String? = nil
    /// How many of its neighbouring frames in its track see the facade too.
    var confirmedBy = 0
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
    /// How far the camera is tilted up (degrees, down negative), from the
    /// rotation Mapillary computed; nil when it has none.
    var pitch: Double? = nil

    static let fields = "id,computed_geometry,geometry,computed_compass_angle,compass_angle,captured_at,creator,is_pano,camera_type,camera_parameters,width,height,sequence,quality_score,computed_rotation"

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
        if !pano, let r = (e["computed_rotation"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }), r.count == 3 {
            pitch = Self.pitch(rotation: r, compass: compass)
        }
    }

    /// A perspective camera (or a panorama) at a place: a kept photo's pose,
    /// a neighbouring frame of a track.
    init(id: String, at: P2, compass: Double, focal: Double, width: Int, height: Int, pano: Bool = false) {
        self.id = id
        self.at = at
        self.compass = compass
        self.pano = pano
        camera = pano ? "spherical" : "perspective"
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

    /// The camera's tilt from Mapillary's computed rotation (an angle-axis
    /// vector, OpenSfM's: the world's east, north, up into the camera's
    /// right, down, forward). Its forward axis in the world is the
    /// rotation's third row; the third column is tried too, and whichever
    /// points where the compass does (within 20°) is taken, so a reading of
    /// the convention the other way round is never trusted. nil when
    /// neither agrees.
    static func pitch(rotation r: [Double], compass: Double?) -> Double? {
        let v = SIMD3(r[0], r[1], r[2]), angle = simd_length(v)
        var m = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
        if angle > 1e-9 {
            let k = v / angle, c = cos(angle), s = sin(angle), t = 1 - c
            m = [[c + k.x * k.x * t, k.x * k.y * t - k.z * s, k.x * k.z * t + k.y * s],
                 [k.y * k.x * t + k.z * s, c + k.y * k.y * t, k.y * k.z * t - k.x * s],
                 [k.z * k.x * t - k.y * s, k.z * k.y * t + k.x * s, c + k.z * k.z * t]]
        }
        for d in [SIMD3(m[2][0], m[2][1], m[2][2]), SIMD3(m[0][2], m[1][2], m[2][2])] {
            let heading = (atan2(d.x, d.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            if let compass, abs(StreetView.wrap(heading - compass)) > 20 { continue }
            return asin(max(-1, min(1, d.z))) * 180 / .pi
        }
        return nil
    }

    var date: String {
        guard let captured else { return "?" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: captured)
    }
}
