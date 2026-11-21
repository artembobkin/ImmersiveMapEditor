import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// Mapillary itself: its token, its Graph API, its coverage tiles (the
/// complete list of the photos around, cached a day), and every photo
/// within a radius of the landmark with the tracks they belong to, for
/// the search and the automatic walk alike.
extension LandmarkMCP.Server {
    var mapillaryToken: String {
        get throws {
            guard let t = ProcessInfo.processInfo.environment["MAPILLARY_TOKEN"], !t.isEmpty else {
                throw Failure("no Mapillary token: the user sets it in the editor, Settings > Landmark references")
            }
            return t
        }
    }

    func mapillary(_ path: String, _ query: [String: String]) throws -> [String: Any] {
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "access_token", value: try mapillaryToken))
        var c = URLComponents(string: "https://graph.mapillary.com/" + path)!
        c.queryItems = items
        // An HTTP error's body kept: Mapillary explains an error in its JSON.
        // Twice: the proxy drops a stream now and then.
        var last = ""
        for _ in 0..<2 {
            let answer = Download.text(c.url!.absoluteString, timeout: 60, failing: false)
            let (status, said) = (answer.status, answer.said)
            last = said
            guard status == 0 else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: Data(said.utf8)) as? [String: Any] else {
                throw Failure("Mapillary answered with something else: \(said.prefix(300))")
            }
            return json
        }
        throw Failure("Mapillary did not answer: \(last.prefix(300))")
    }

    /// A coverage tile of Mapillary's, kept for a day.
    func coverage(x: Int, y: Int) throws -> Data {
        let dir = cacheFolder.appendingPathComponent("mapillary")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(CoverageTile.zoom)_\(x)_\(y).mvt")
        if let age = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(age) < 86_400 || offline, let data = try? Data(contentsOf: file), !data.isEmpty { return data }
        let url = "https://tiles.mapillary.com/maps/vtp/mly1_public/2/\(CoverageTile.zoom)/\(x)/\(y)?access_token=\(try mapillaryToken)"
        var last = ""
        for _ in 0..<2 {
            let (status, said) = CacheFile.fetch(url, to: file, timeout: 120)
            last = said
            if status == 0, let data = try? Data(contentsOf: file), !data.isEmpty { return data }
        }
        throw Failure("Mapillary's coverage tile did not come: \(last.prefix(200))")
    }

    /// Without Mapillary (`LANDMARK_STREET_OFFLINE`): the coverage tiles
    /// of the cache however old, the photos as the tiles describe them,
    /// no thumbnails fetched. For checking the choice without the token.
    var offline: Bool { ProcessInfo.processInfo.environment["LANDMARK_STREET_OFFLINE"] != nil }

    /// The time `since` asks for, in Mapillary's milliseconds: only the
    /// photos taken since then, the building as it is now (the user,
    /// 2026-11-21: what was gathered before is not always the newest).
    func sinceTime(_ args: [String: Any]) throws -> Double? {
        try (args["since"] as? String).map { text in
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard (1...3).contains(parts.count), parts[0] > 2000,
                  let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: parts[0], month: parts.count > 1 ? parts[1] : 1, day: parts.count > 2 ? parts[2] : 1))
            else { throw Failure("since is a date: 2023, 2023-06 or 2023-06-15") }
            return date.timeIntervalSince1970 * 1000
        }
    }

    /// Every photo within `radius` metres of the landmark taken since
    /// `since` (milliseconds), from Mapillary's coverage tiles (the complete
    /// list: the Graph API's box search answers with a different sample
    /// every time), as the tiles describe them; the tracks they belong to,
    /// every photo's frames in the order taken, a margin beyond the radius
    /// so a photo at its edge has its neighbours; and how many photos stand
    /// within the radius at all.
    func photosAround(_ scene: StreetScene, radius: Double, since: Double?) throws
        -> (entries: [[String: Any]], tracks: [String: StreetTrack], total: Int) {
        let kx = scene.kx, ky = scene.ky
        let corners = [(scene.lon - radius / kx, scene.lat - radius / ky), (scene.lon + radius / kx, scene.lat - radius / ky),
                       (scene.lon - radius / kx, scene.lat + radius / ky), (scene.lon + radius / kx, scene.lat + radius / ky)]
        var tiles = Set<String>()
        var points: [CoverageTile.Point] = []
        for (lon, lat) in corners {
            let t = CoverageTile.tile(lon: lon, lat: lat)
            guard tiles.insert("\(t.x)/\(t.y)").inserted else { continue }
            points += CoverageTile.points(try coverage(x: t.x, y: t.y), x: t.x, y: t.y)
        }
        // Each photo as the coverage tile describes it, and the tracks:
        // every photo's frames in the order taken, a margin beyond the
        // radius so a photo at its edge has its neighbours.
        var entries: [[String: Any]] = []
        var frames: [String: [StreetTrack.Frame]] = [:]
        for p in points {
            let at = scene.metres(lon: p.lon, lat: p.lat)
            guard simd_length(at) <= radius + 150, let id = p.props["id"].map({ "\($0)" }), !id.isEmpty else { continue }
            var pano = false
            if let b = p.props["is_pano"] as? Bool { pano = b } else if let n = p.props["is_pano"] as? UInt64 { pano = n != 0 }
            let sequence = p.props["sequence_id"].map { "\($0)" } ?? id
            var e: [String: Any] = ["id": id, "computed_geometry": ["coordinates": [p.lon, p.lat]], "is_pano": pano, "sequence": sequence]
            var compass: Double?
            if let a = p.props["compass_angle"] as? Double { compass = a }
            else if let a = p.props["compass_angle"] as? Int64 { compass = Double(a) }
            else if let a = p.props["compass_angle"] as? UInt64 { compass = Double(a) }
            if let compass { e["computed_compass_angle"] = compass }
            var time = 0.0
            if let t = p.props["captured_at"] as? Int64 { time = Double(t) }
            else if let t = p.props["captured_at"] as? UInt64 { time = Double(t) }
            else if let t = p.props["captured_at"] as? Double { time = t }
            e["captured_at"] = time
            frames[sequence, default: []].append(StreetTrack.Frame(id: id, at: at, compass: compass, time: time, pano: pano))
            if simd_length(at) <= radius, time >= (since ?? 0) { entries.append(e) }
        }
        let total = points.filter { simd_length(scene.metres(lon: $0.lon, lat: $0.lat)) <= radius }.count
        return (entries, frames.mapValues { StreetTrack($0) }, total)
    }
}
