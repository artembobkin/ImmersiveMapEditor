import Foundation
import Geometry
import simd
import TileKit

/// The agent's own search of Mapillary (the user, 2026-11-21: the street
/// references are found by the agent, who looks at them and searches again
/// when one shows the wrong building or an old facade, not chosen and kept
/// by fixed rules beforehand, which often took the wrong building).
///
/// search_street_photos lists the photos that look at a facade (or the
/// landmark), a pass a line (of each track its frame with the best look:
/// the newest nine frames would be one pass nine times), the newest pass
/// first or the best look, a page at a time, as a contact
/// sheet with the landmark framed where each photo's pose puts it, and says
/// how sure that pose is; nothing is kept and nothing refused: a photo
/// whose compass points away is shown as if it looked at the building, a
/// guess, and `pass_of` walks along one pass frame by frame. look_at_street_photo shows one
/// large, framed but whole, to judge it; save_street_photo keeps the one
/// chosen into its facade's best/, where every build compares with it.
extension LandmarkMCP.Server {
    func searchStreetPhotos(_ args: [String: Any]) throws -> [[String: Any]] {
        let scene = try StreetScene(folder: folder)
        let radius = max(30, min(400, (args["radius"] as? NSNumber)?.doubleValue ?? 120))
        let count = max(1, min(16, (args["count"] as? NSNumber)?.intValue ?? 9))
        let skip = max(0, (args["skip"] as? NSNumber)?.intValue ?? 0)
        let newest = (args["order"] as? String ?? "newest") != "best"
        let since = try sinceTime(args)
        // The facade asked for, by its name or its folder's.
        var facade: Int?
        if let asked = (args["facade"] as? String)?.lowercased(), !asked.isEmpty {
            facade = scene.facades.firstIndex { $0.name.lowercased() == asked || Self.facadeFolder($0.name) == asked }
            guard facade != nil else {
                throw Failure("no facade \(asked): the landmark's are " + scene.facades.map { Self.facadeFolder($0.name) }.joined(separator: ", "))
            }
        }
        // A page of the search's budget, or what to do in its place.
        let budget = facade.map { Self.facadeFolder(scene.facades[$0].name) } ?? ""
        if let spent = spendPage(budget) { return [text(spent)] }
        let (entries, tracks, total) = try photosAround(scene, radius: radius, since: since)

        // Every photo by its tile's pose (the track's heading where its
        // compass is missing or strays), kept when it looks at the facade
        // asked for, or at any; a pose its track does not bear out is said,
        // not refused: the agent sees the picture.
        //
        // A photo whose compass points away is not left out either (the
        // user, 2026-11-21: a wrong pose may hide the very photo wanted):
        // standing where the facade would be in sight, it is shown as if it
        // looked at the building, its frame and side a guess, and said so.
        typealias Look = (view: StreetView, entry: [String: Any], doubt: String?, guessed: Bool)
        func seen(_ v: StreetView) -> Double { facade.map { v.seen[$0] } ?? v.seen.max() ?? 0 }
        /// A photo judged; with `anywhere`, also one from where the facade
        /// asked for is out of sight (a frame of a pass walked along).
        func judge(_ e: [String: Any], anywhere: Bool = false) -> Look? {
            guard var photo = StreetPhoto(e, scene) else { return nil }
            let track = tracks[photo.sequence]
            if !photo.pano, let t = track, let i = t.index[photo.id], let h = t.heading(at: i, compass: photo.compass).heading {
                photo.compass = h
            }
            if let rough = StreetView(photo, in: scene, quick: true), seen(rough) >= StreetView.enough {
                var doubt: String? = "no track"
                if let t = track {
                    let (confirmed, why) = t.confirm(photo, in: scene)
                    doubt = confirmed != nil ? nil : why
                }
                return (rough, e, doubt.map { "its track does not bear its pose out (\($0))" }, false)
            }
            var turned = photo
            turned.compass = nil
            guard let guess = StreetView(turned, in: scene, quick: true), anywhere || seen(guess) >= StreetView.enough else { return nil }
            return (guess, e, "by its compass it looks away from the building: framed as if it looked at it, the frame and the side a guess", true)
        }
        var looks: [Look] = entries.compactMap { judge($0) }
        /// How good a look: a guessed one after any its pose bears out.
        func score(_ look: Look) -> Double {
            let f = facade ?? look.view.best
            return look.view.looks[f] * look.view.seen[f] * (look.guessed ? 0.3 : 1)
        }
        // A pass a line, not a frame a line: a car takes a frame every few
        // metres, and the newest nine frames would be one pass nine times.
        // Of each track its frame with the best look; or, asked for the
        // pass of one photo, every frame of that track.
        let frames = looks.count
        var along = ""
        if let like = args["pass_of"] as? String, !like.isEmpty {
            // A pass walked along: its frames in the order taken, whatever
            // their compasses say, the one asked for in the middle of the
            // first page; and which side of its way the building is on,
            // since a dashcam looks ahead and the building passes by.
            func sequence(_ e: [String: Any]) -> String { e["sequence"] as? String ?? "" }
            guard let asked = entries.first(where: { $0["id"] as? String == like }) else {
                throw Failure("\(like) is not a photo within \(Int(radius)) m" + (since != nil ? " taken since then" : "") + ": give the id of one search_street_photos listed")
            }
            let pass = entries.filter { sequence($0) == sequence(asked) }
                .sorted { ($0["captured_at"] as? Double ?? 0) < ($1["captured_at"] as? Double ?? 0) }
            let at = pass.firstIndex { $0["id"] as? String == like } ?? 0
            looks = pass.dropFirst(max(0, at - count / 2)).compactMap { judge($0, anywhere: true) }
            if let t = tracks[sequence(asked)], let i = t.index[like], let way = StreetTrack.course(t.frames, i) {
                let here = t.frames[i].at
                let toCentre = (atan2(-here.x, -here.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                let turn = StreetView.wrap(toCentre - way)
                along = " The pass goes \(StreetView.side(way)); at \(like) the building is "
                    + (abs(turn) < 30 ? "ahead of it" : abs(turn) > 150 ? "behind it" : turn > 0 ? "on its right" : "on its left") + "."
            }
        } else {
            var best: [String: Look] = [:]
            for look in looks {
                if let kept = best[look.view.photo.sequence], score(kept) >= score(look) { continue }
                best[look.view.photo.sequence] = look
            }
            looks = best.values.sorted { a, b in
                if newest, let ta = a.view.photo.captured, let tb = b.view.photo.captured, ta != tb { return ta > tb }
                if score(a) != score(b) { return score(a) > score(b) }
                return a.view.photo.id < b.view.photo.id
            }
        }
        let passes = args["pass_of"] == nil
        guard !looks.isEmpty else {
            return [text("Of \(total) street photos within \(Int(radius)) m none looks at " + (facade.map { "the \(scene.facades[$0].name)" } ?? "the landmark")
                         + (since != nil ? " since then" : "") + ". A larger radius, an earlier since, or another facade.")]
        }

        // The page asked for in full (camera, computed pose, quality), each
        // judged again with what stands in the way.
        let page = Array(looks.dropFirst(skip).prefix(count))
        var full: [String: [String: Any]] = [:]
        if !offline {
            let ids = page.map { $0.view.photo.id }
            for chunk in stride(from: 0, to: ids.count, by: 20).map({ Array(ids[$0..<min($0 + 20, ids.count)]) }) {
                let json = try mapillary("", ["ids": chunk.joined(separator: ","), "fields": StreetPhoto.fields + ",thumb_1024_url,thumb_2048_url"])
                if let error = json["error"] as? [String: Any] { throw Failure("Mapillary refused the photos' details: \(error["message"] ?? error)") }
                for (id, e) in json where chunk.contains(id) { if let e = e as? [String: Any] { full[id] = e } }
            }
        }
        let dir = searchFolder.appendingPathComponent("street")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        var cells: [ContactSheet.Cell] = []
        for (k, look) in page.enumerated() {
            var view = look.view
            var doubts = look.doubt.map { [$0] } ?? []
            var guessed = look.guessed
            if let e = full[view.photo.id], let photo = StreetPhoto(e, scene) {
                // Mapillary's computed pose, better than the tile's: a guessed look
                // it bears out is a guess no more.
                let better = StreetView(photo, in: scene)
                if let better, !look.guessed || seen(better) >= StreetView.enough {
                    view = better
                    if look.guessed { doubts = []; guessed = false }
                } else if !look.guessed {
                    doubts.append("by its computed pose another building may stand in the way")
                }
                if photo.poseDoubt { doubts.append("its computed pose and its device's disagree") }
            }
            candidates[view.photo.id] = (view, full[view.photo.id] ?? look.entry, guessed)
            let file = dir.appendingPathComponent("\(view.photo.id).jpg")
            if !FileManager.default.fileExists(atPath: file.path), let e = full[view.photo.id],
               let url = (view.photo.pano ? e["thumb_2048_url"] : e["thumb_1024_url"] ?? e["thumb_2048_url"]) as? String {
                _ = Download.file(url, to: file, timeout: 30)
            }
            let number = skip + k + 1
            cells.append(ContactSheet.Cell(image: FileManager.default.fileExists(atPath: file.path) ? file : nil, box: view.box, cut: view.photo.pano,
                                           label: "#\(number)  \(view.photo.date)  \(Int(view.distance)) m"))
            lines.append("#\(number) " + view.line(scene) + (doubts.isEmpty ? "" : "; " + doubts.joined(separator: "; ")))
        }
        let sheet = dir.appendingPathComponent("search-\(skip + 1)-\(skip + page.count).jpg")
        try ContactSheet.draw(cells, to: sheet)
        let what = facade.map { "the \(scene.facades[$0].name)" } ?? "the landmark"
        var content: [[String: Any]] = [text(
            "\(frames) of \(total) street photos within \(Int(radius)) m look at \(what)" + (since != nil ? " (taken since then)" : "")
            + (passes ? ", in \(looks.count) passes (a car's or a walker's track): of each pass its frame with the best look, \(newest ? "the newest pass" : "the best look") first"
                      : ": the frames of that one pass in the order taken, whatever their compasses say." + along + " Its frames")
            + (passes ? "; " : " ") + "#\(skip + 1) to #\(skip + page.count) below, the landmark framed in red where each one's pose puts it "
            + "(a frame on another building is a wrong pose). look_at_street_photo(id) to see one large, save_street_photo(id, facade, shows) to keep it"
            + (passes ? ", pass_of: id for the other frames of a pass" : "")
            + (skip + page.count < looks.count ? ", skip: \(skip + page.count) for the next ones" : "") + ".\n" + lines.joined(separator: "\n") + "\n" + searchLeft(budget))]
        if let picture = image(sheet) { content.append(picture) }
        return content
    }

    /// One searched photo large, the landmark framed in red where its pose
    /// puts it, nothing painted over: to judge it before keeping it.
    func lookAtStreetPhoto(_ args: [String: Any]) throws -> [[String: Any]] {
        guard let id = args["id"] as? String, let candidate = candidates[id] else {
            throw Failure("give the id of a photo search_street_photos listed in this session")
        }
        guard looked < Self.looksInAll else {
            return [text("The looks at one large are spent (\(Self.looksInAll)): judge by the sheets. " + whatNow())]
        }
        looked += 1
        let scene = try StreetScene(folder: folder)
        let view = candidate.view
        let dir = searchFolder.appendingPathComponent("street")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let large = dir.appendingPathComponent("\(id).large.jpg")
        if !FileManager.default.fileExists(atPath: large.path) {
            var url = candidate.entry["thumb_2048_url"] as? String
            if url == nil, !offline, let json = try? mapillary(id, ["fields": "thumb_2048_url"]) { url = json["thumb_2048_url"] as? String }
            guard let url else { throw Failure("Mapillary has no picture for \(id)") }
            let got = Download.file(url, to: large, timeout: 60)
            guard got.status == 0 else { throw Failure("its picture did not come: \(got.said)") }
        }
        let framed = dir.appendingPathComponent("\(id).look.jpg")
        try ContactSheet.one(ContactSheet.Cell(image: large, box: view.box, cut: view.photo.pano, label: ""), maxSide: 1280, to: framed)
        return [text(view.line(scene) + ". save_street_photo(\"\(id)\", facade, shows) keeps it.")] + (image(framed).map { [$0] } ?? [])
    }
}
