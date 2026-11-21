import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The automatic walk round the landmark (find_street_photos): the photos
/// judged by fixed rules, their poses, tracks and pictures, the best of
/// each station of each facade kept at once. Kept as the automatic way,
/// which often picks the wrong building: the agent's own search is
/// `LandmarkMCP+StreetSearch`.
extension LandmarkMCP.Server {
    /// The photos around the landmark that look at it, judged by
    /// geometry (StreetView), the best track by track (StreetPicks).
    func streetPhotos(_ args: [String: Any]) throws -> [[String: Any]] {
        let scene = try StreetScene(folder: folder)
        let radius = max(30, min(400, (args["radius"] as? NSNumber)?.doubleValue ?? 150))
        let limit = max(1, min(300, (args["limit"] as? NSNumber)?.intValue ?? 140))
        let since = try sinceTime(args)
        // Every photo around, judged first by its raw pose, then the best
        // few dozen asked for in full (camera, computed pose, quality) and
        // judged again.
        let (entries, tracks, total) = try photosAround(scene, radius: radius, since: since)
        func track(_ e: [String: Any]) -> StreetTrack? { tracks[(e["sequence"] as? String) ?? ((e["sequence"] as? [String: Any])?["id"] as? String) ?? ""] }
        // Judged first by the tile's pose, its heading the track's when
        // its compass is missing or strays.
        var rough: [(StreetView, [String: Any])] = []
        for e in entries {
            guard var photo = StreetPhoto(e, scene) else { continue }
            if !photo.pano, let t = track(e), let i = t.index[photo.id] {
                guard let h = t.heading(at: i, compass: photo.compass).heading else { continue }
                photo.compass = h
            }
            guard let view = StreetView(photo, in: scene, quick: true) else { continue }
            rough.append((view, e))
        }
        // Facade by facade, so a facade seen only in passing keeps its
        // candidates: the best thousand looks at each judged with
        // what hides them, then the best forty at every station of each
        // asked for in full (camera, computed pose, quality), twenty ids
        // a call.
        func bestOfEachFacade(_ list: [(StreetView, [String: Any])], _ n: Int) -> [[String: Any]] {
            var ids = Set<String>()
            var out: [[String: Any]] = []
            for f in scene.facades.indices {
                for (_, e) in list.filter({ $0.0.seen[f] >= StreetView.enough }).sorted(by: { $0.0.looks[f] > $1.0.looks[f] }).prefix(n)
                where ids.insert(e["id"] as! String).inserted { out.append(e) }
            }
            return out
        }
        // Then judged with what hides them, and borne out by their tracks
        // (the tile's pose for now): only those are asked for in full.
        var judged: [(StreetView, [String: Any])] = []
        var refused: [String: Int] = [:]
        for e in bestOfEachFacade(rough, 1000) {
            guard let photo = StreetPhoto(e, scene) else { continue }
            guard let t = track(e) else { refused["no track", default: 0] += 1; continue }
            let (confirmed, why) = t.confirm(photo, in: scene)
            guard let confirmed else { refused[why.components(separatedBy: ":").first ?? why, default: 0] += 1; continue }
            guard let view = StreetView(confirmed, in: scene) else { continue }
            judged.append((view, e))
        }
        // The best forty at every station of every facade asked for in
        // full, so each station keeps candidates from several tracks.
        var askedIds = Set<String>()
        var asked: [String] = []
        for f in scene.facades.indices {
            for k in 0..<StreetScene.stations {
                for (_, e) in judged.filter({ $0.0.seen[f] >= StreetView.enough && scene.station(f, of: $0.0.photo.at) == k })
                    .sorted(by: { $0.0.looks[f] * $0.0.seen[f] > $1.0.looks[f] * $1.0.seen[f] }).prefix(40)
                where askedIds.insert(e["id"] as! String).inserted { asked.append(e["id"] as! String) }
            }
        }
        if ProcessInfo.processInfo.environment["LANDMARK_STREET_DEBUG"] != nil {
            for (f, facade) in scene.facades.enumerated() {
                let glanced = rough.filter { $0.0.seen[f] >= StreetView.enough }.count
                let clear = judged.filter { $0.0.seen[f] >= StreetView.enough && $0.0.looks[f] > 0 }.count
                let worth = judged.filter { $0.0.looks[f] >= StreetPicks.worthwhile }.count
                FileHandle.standardError.write("\(facade.name) (\(Int(facade.length)) m): \(glanced) rough looks, \(clear) judged clear and borne out by their tracks, \(worth) worthwhile\n".data(using: .utf8)!)
            }
            for (why, n) in refused.sorted(by: { $0.value > $1.value }) {
                FileHandle.standardError.write("not borne out by its track: \(n) × \(why)\n".data(using: .utf8)!)
            }
        }
        var photos: [String: [String: Any]] = [:]
        if offline {
            for (_, e) in judged where asked.contains(e["id"] as! String) { photos[e["id"] as! String] = e }
        } else {
            for chunk in stride(from: 0, to: asked.count, by: 20).map({ Array(asked[$0..<min($0 + 20, asked.count)]) }) {
                let json = try mapillary("", ["ids": chunk.joined(separator: ","), "fields": StreetPhoto.fields + ",thumb_1024_url,thumb_2048_url"])
                if let error = json["error"] as? [String: Any] { throw Failure("Mapillary refused the photos' details: \(error["message"] ?? error)") }
                for (id, e) in json where chunk.contains(id) { if let e = e as? [String: Any] { photos[id] = e } }
            }
            // A photo a chunk's answer leaves out is asked for alone.
            for id in asked where photos[id] == nil {
                if let e = try? mapillary(id, ["fields": StreetPhoto.fields + ",thumb_1024_url,thumb_2048_url"]), e["error"] == nil, e["id"] != nil { photos[id] = e }
            }
        }
        func text(_ s: String) -> [String: Any] { self.text(s) }
        let photosCount = total
        // Judged again by the full answer: the pose Mapillary computed
        // (one whose device's pose disagrees is a mistake of one or the
        // other), borne out by its track again.
        var final: [String: String] = [:]   // why a photo asked for is not shown
        var views: [StreetView] = []
        for (id, e) in photos {
            guard let photo = StreetPhoto(e, scene) else { final[id] = "no pose at all"; continue }
            guard simd_length(photo.at) <= radius else { final[id] = "beyond the radius"; continue }
            guard !photo.poseDoubt else { final[id] = "its computed pose and its device's disagree"; continue }
            guard let t = tracks[photo.sequence] ?? tracks[(e["sequence"] as? String) ?? ""] else { final[id] = "no track"; continue }
            let (confirmed, why) = t.confirm(photo, in: scene)
            guard let confirmed else { final[id] = why; continue }
            guard let view = StreetView(confirmed, in: scene) else { final[id] = StreetView.reason; continue }
            views.append(view)
        }
        // Then by their pictures: each one's thumbnail, the inside of its
        // red frame read for a building and set beside its facade's
        // others (FrameCheck). The dropped never reach the walk.
        let dir = searchFolder.appendingPathComponent("street")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let thumbFiles: [URL?] = {
            var out = [URL?](repeating: nil, count: views.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: views.count) { k in
                let v = views[k]
                let file = dir.appendingPathComponent("\(v.photo.id).jpg")
                var got: URL? = FileManager.default.fileExists(atPath: file.path) ? file : nil
                if got == nil, !offline, let e = photos[v.photo.id],
                   let url = (v.photo.pano ? e["thumb_2048_url"] : e["thumb_1024_url"] ?? e["thumb_2048_url"]) as? String {
                    let status = Download.file(url, to: file, timeout: 30).status
                    if status == 0 { got = file }
                }
                lock.lock(); out[k] = got; lock.unlock()
            }
            return out
        }()
        let pictures: [CGImage?] = zip(views, thumbFiles).map { v, file in
            guard let file, let src = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            return FrameCheck.crop(image, box: v.box)
        }
        let verdicts = FrameCheck.judge(pictures, groups: views.map(\.best))
        var buildingOf: [String: Double] = [:]
        for (v, verdict) in zip(views, verdicts) { buildingOf[v.photo.id] = verdict.building }
        var droppedByPicture: [(StreetView, String)] = []
        views = zip(views, verdicts).compactMap { v, verdict in
            if verdict.keep { return v }
            droppedByPicture.append((v, verdict.note))
            return nil
        }
        if ProcessInfo.processInfo.environment["LANDMARK_STREET_DEBUG"] != nil {
            for (v, why) in droppedByPicture {
                FileHandle.standardError.write("\(v.photo.id): dropped by its picture: \(why)\n".data(using: .utf8)!)
            }
        }
        for v in views { confirmed[v.photo.id] = v }
        if ProcessInfo.processInfo.environment["LANDMARK_STREET_DEBUG"] != nil {
            for (f, facade) in scene.facades.enumerated() {
                let top = views.filter { $0.seen[f] >= StreetView.enough }.sorted { $0.looks[f] > $1.looks[f] }.prefix(6)
                FileHandle.standardError.write("\(facade.name): the best looks\n".data(using: .utf8)!)
                for v in top {
                    FileHandle.standardError.write(String(format: "  %@: look %.2f, seen %.2f, score %.2f, %@\n", v.photo.id, v.looks[f], v.seen[f], v.score, v.line(scene)).data(using: .utf8)!)
                }
            }
            for id in asked where !views.contains(where: { $0.photo.id == id }) {
                FileHandle.standardError.write("\(id): not shown: \(final[id] ?? "not returned by Mapillary")\n".data(using: .utf8)!)
            }
        }
        guard !views.isEmpty else {
            return [text("Of \(photosCount) street photos within \(Int(radius)) m none shows the landmark well. Try a larger radius." + (since != nil ? " Only those taken since the date asked count: an earlier one gives more." : ""))]
        }
        let (report, picks, stations) = StreetPicks.report(views, in: scene, limit: limit)
        guard !picks.isEmpty else { return [text("Of \(photosCount) street photos within \(Int(radius)) m none gives a good look at the landmark.")] }
        // The contact sheet: a small thumbnail of each pick, framed.
        // Each pick at a size its eyes can read, framed; the sheet of them
        // all for the user's panel.
        let thumbs: [URL?] = picks.map { pick in
            let file = dir.appendingPathComponent("\(pick.photo.id).jpg")
            if FileManager.default.fileExists(atPath: file.path) { return file }
            guard !offline, let json = try? mapillary(pick.photo.id, ["fields": pick.photo.pano ? "thumb_2048_url" : "thumb_1024_url"]),
                  let url = (json["thumb_2048_url"] ?? json["thumb_1024_url"]) as? String else { return nil }
            let status = Download.file(url, to: file, timeout: 30).status
            return status == 0 ? file : nil
        }
        let sheet = dir.appendingPathComponent("sheet.jpg")
        try StreetPicks.sheet(picks, in: scene, thumbs: thumbs, to: sheet)
        // Every station's photos are kept at once, each into the folder
        // of the facade it was taken for: the best one to three of each
        // facade (StreetPicks.best) into its best/, the others into its
        // other/, so every side a photo stands at gets its references
        // whatever the agent makes of the list, and the choice is seen in
        // the folders. The agent drops one whose frame is wrong. Only the
        // best come back as pictures, the others by name.
        let best = StreetPicks.best(stations, in: scene, building: buildingOf)
        var bestOf: [String: Int] = [:]   // photo id to the facade it is a best of
        var first = Set<String>()         // the one of each facade that comes back as a picture
        for (f, views) in best {
            for v in views { bestOf[v.photo.id] = f }
            if let v = views.first { first.insert(v.photo.id) }
        }
        var keptNow: [String: [[String: Any]]] = [:]
        let already = (credited())
            .compactMap { $0["page"] as? String }
        for (f, k, view) in stations where keptNow[view.photo.id] == nil && !already.contains("https://www.mapillary.com/app/?pKey=\(view.photo.id)") && !offline {
            let facade = bestOf[view.photo.id] ?? f
            let into = Self.facadeFolder(scene.facades[facade].name) + (bestOf[view.photo.id] != nil ? "/best" : "/other")
            if let kept = try? keepStreet(view, shows: "\(scene.facades[f].name) \(scene.stationName(f, k)): \(view.shows(scene)), kept by find_street_photos"
                                              + (bestOf[view.photo.id] != nil ? ", one of the best of \(scene.facades[facade].name)" : ""),
                                          into: into) {
                keptNow[view.photo.id] = kept
            }
        }
        var content: [[String: Any]] = [text(
            "\(photosCount) street photos within \(Int(radius)) m; only those borne out by their tracks count (the place smooth with the neighbouring frames, the track clear of buildings, a dashcam's heading the way it went, the facade seen from two neighbouring frames too). Of the \(asked.count) best of them asked for in full, \(photos.count) came back and \(views.count + droppedByPicture.count) are borne out again by Mapillary's computed pose; of those, \(droppedByPicture.count) dropped by their pictures (no building in the red frame, or a blank: the Mac's scene classifier and the facade's other photos). A walk around it, facade by facade (the sides of its outline, the longest first) and station by station along each (from beyond one end, its thirds, from beyond the other end), at each the photos standing there that show the facade best, each from another track:\n"
            + report
            + "\nEvery station's photos are kept already, framed in red, the rest painted black, each in the folder of its facade: the best one to three of each facade in its best/ (north-facade/best/, chosen by how much of the facade they show, how square on and large, daylight, and how sure the Mac is of a building in them), the others in its other/. The very best of each facade follows as a picture, the rest by name: show_reference(name) to look at one, when a detail needs it. Mapillary's camera pose is sometimes wrong: if a frame holds another building, drop_reference it. Licence CC BY-SA 4.0, credited to Mapillary and its author.")]
        for (k, pick) in picks.enumerated() {
            if let kept = keptNow[pick.photo.id] {
                content.append(text("#\(k + 1) " + (kept.first?["text"] as? String ?? "")))
                if first.contains(pick.photo.id) { content += kept.dropFirst() }
                continue
            }
            let framed = dir.appendingPathComponent("\(pick.photo.id).framed.jpg")
            try ContactSheet.one(ContactSheet.Cell(image: thumbs[k], box: pick.box, cut: pick.photo.pano, label: ""), maxSide: 720, to: framed)
            content.append(text("#\(k + 1) " + pick.line(scene)))
            if let img = image(framed) { content.append(img) }
        }
        return content
    }
}
