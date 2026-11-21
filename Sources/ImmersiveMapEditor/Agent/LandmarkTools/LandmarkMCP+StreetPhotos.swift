import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The street photos kept: kept from a search or the walk into a facade's
/// folder, framed and credited with their camera's pose, the facades'
/// folders and their best photos, and a facade reviewed beside its best
/// photo (review_facade).
extension LandmarkMCP.Server {
    /// The kept street photos as looks at the landmark, from their poses.
    func keptViews(_ scene: StreetScene) -> [(file: String, view: StreetView)] {
        let list = credited()
        return list.compactMap { e in
            guard let file = e["file"] as? String, let pose = e["pose"] as? [String: Any],
                  let x = pose["x"] as? Double, let y = pose["y"] as? Double,
                  let heading = pose["heading"] as? Double, let hfov = pose["hfov"] as? Double else { return nil }
            let width = pose["width"] as? Int ?? 1280, height = pose["height"] as? Int ?? 720
            return scene.view(x: x, y: y, heading: heading, hfov: hfov, width: width, height: height).map { (file, $0) }
        }
    }


    func saveStreetPhoto(_ args: [String: Any]) throws -> [[String: Any]] {
        guard let id = args["id"] as? String, !id.isEmpty, id.allSatisfy(\.isNumber) else { throw Failure("give the photo's id from search_street_photos") }
        guard let shows = args["shows"] as? String, !shows.isEmpty else { throw Failure("say what it shows") }
        guard let view = candidates[id]?.view ?? confirmed[id] else {
            throw Failure("\(id) is not one search_street_photos or find_street_photos listed in this session")
        }
        let scene = try StreetScene(folder: folder)
        // The facade it is kept for: the one asked, else the one it shows best.
        // Into its best/: the agent chose it, and every build compares with it.
        var facade = view.best
        if let asked = (args["facade"] as? String)?.lowercased(), !asked.isEmpty {
            guard let f = scene.facades.firstIndex(where: { $0.name.lowercased() == asked || Self.facadeFolder($0.name) == asked }) else {
                throw Failure("no facade \(asked): the landmark's are " + scene.facades.map { Self.facadeFolder($0.name) }.joined(separator: ", "))
            }
            // A photo is kept for a side its camera sees: kept for another, every
            // build would compare that side with a picture of a different one.
            guard view.seen[f] >= StreetView.enough else {
                throw Failure("by its camera's pose \(id) does not show the \(scene.facades[f].name): it shows \(view.shows(scene)). Keep it for that side, or search this facade for another")
            }
            facade = f
        }
        let kept = try keepStreet(view, shows: shows, into: Self.facadeFolder(scene.facades[facade].name) + "/best")
        // A guessed pose is said: the comparisons from it may stand elsewhere.
        guard candidates[id]?.guessed == true else { return kept }
        return [text("Its pose is a guess (its compass pointed away): the red frame and compare_with_photo from it may be off. Trust the photo itself.")] + kept
    }

    /// The folder of a facade's street photos: "the south facade, east
    /// end" is south-facade-east-end.
    static func facadeFolder(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "the ", with: "").replacingOccurrences(of: ",", with: "")
        return words.split(separator: " ").joined(separator: "-")
    }

    /// A facade's best photos, by their paths in the references.
    func bestPhotos(_ facade: String) -> [String] {
        credited().compactMap { $0["file"] as? String }.filter { $0.hasPrefix("\(facade)/best/") }.sorted()
    }

    /// The facades with best photos not reviewed on the current model.
    func facadesToReview() -> [String] {
        Self.facadesToReview(folder)
    }

    /// How many facades the landmark has (its hull's sides), for the
    /// agent's budget of turns.
    static func facadeCount(_ folder: URL) -> Int {
        StreetScene.facadeCount(folder: folder) ?? 4
    }

    /// The facades of a landmark's folder with best photos that its
    /// latest round has no review of: what the editor asks the agent
    /// for before it ends.
    static func facadesToReview(_ folder: URL) -> [String] {
        let references = folder.appendingPathComponent("references")
        let facades = ((try? FileManager.default.contentsOfDirectory(atPath: references.path)) ?? []).filter { name in
            let best = references.appendingPathComponent(name).appendingPathComponent("best")
            return ((try? FileManager.default.contentsOfDirectory(atPath: best.path)) ?? []).contains { $0.hasSuffix(".jpg") }
        }.sorted()
        let rounds = folder.appendingPathComponent("rounds")
        let latest = ((try? FileManager.default.contentsOfDirectory(atPath: rounds.path)) ?? []).filter { Int($0) != nil }.sorted().last
        guard let latest else { return facades }
        let file = rounds.appendingPathComponent(latest).appendingPathComponent("reviews.json")
        let done = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any]) ?? [:]
        return facades.filter { done[$0] == nil }
    }

    /// The model beside every best photo of a facade, and the review
    /// recorded for the current round.
    func reviewFacade(_ facade: String) throws -> [[String: Any]] {
        let best = bestPhotos(facade)
        guard !best.isEmpty else {
            let known = ((try? FileManager.default.contentsOfDirectory(atPath: references.path)) ?? []).filter { !$0.hasSuffix(".json") && !$0.hasSuffix(".jpg") }.sorted()
            throw Failure("\(facade) has no best photos; the facades are: \(known.joined(separator: ", "))")
        }
        var content: [[String: Any]] = [text("\(facade): the model beside its best photo, \(best[0]). Count what the photo shows against the model (arches, windows, storeys, entrances, the cornice, the relief, the colours) and fix what differs."
            + (best.count > 1 ? " Its other best photos, by name: \(best.dropFirst().joined(separator: ", ")); show_reference one when a detail needs it." : ""))]
        content += (try? compare(["file": best[0]])) ?? []
        let round = currentRound
        try FileManager.default.createDirectory(at: round, withIntermediateDirectories: true)
        let file = round.appendingPathComponent("reviews.json")
        var done = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any]) ?? [:]
        done[facade] = ISO8601DateFormatter().string(from: Date())
        try JSONSerialization.data(withJSONObject: done, options: [.prettyPrinted, .sortedKeys]).write(to: file)
        let due = facadesToReview()
        content.append(text(due.isEmpty ? "Every facade is reviewed on this model." : "Still to review on this model: \(due.joined(separator: ", "))."))
        return content
    }


    /// A Mapillary photo kept by its id: downloaded, the landmark framed
    /// in red and the rest painted black, credited with its camera's
    /// pose; the text says what it shows and what the references cover.
    func keepStreet(_ view: StreetView, shows: String, into sub: String) throws -> [[String: Any]] {
        let scene = try StreetScene(folder: folder)
        let id = view.photo.id
        let json = try mapillary(id, ["fields": "id,thumb_2048_url,thumb_original_url"])
        if let error = json["error"] as? [String: Any] { throw Failure("Mapillary: \(error["message"] ?? error)") }
        guard let url = (json["thumb_original_url"] ?? json["thumb_2048_url"]) as? String else { throw Failure("Mapillary has no picture for \(id)") }
        let photo = view.photo
        // A panorama is kept whole until it is cut to the landmark.
        let kept = try keep(photo.pano ? url : (json["thumb_2048_url"] as? String ?? url),
                            page: "https://www.mapillary.com/app/?pKey=\(id)", author: "\(photo.author) (Mapillary)",
                            licence: "CC BY-SA 4.0", shows: shows + " (the landmark is the building framed in red, the rest painted black)",
                            maxSide: photo.pano ? 8192 : 1280, into: sub)
        if let name = (kept.first?["text"] as? String)?.split(separator: " ").last {
            let file = references.appendingPathComponent(String(name))
            try StreetMarking.mark(file, view)
            // The camera's place and look, for a render from the same place.
            let pose = view.pose
            var entry: [String: Any] = ["x": r1(photo.at.x), "y": r1(photo.at.y), "z": 2.0, "heading": r1(pose.heading),
                                        "pitch": r1(pose.pitch), "hfov": r1(pose.hfov)]
            if let size = Self.size(of: file) { entry["width"] = size.0; entry["height"] = size.1 }
            try credit(String(name), set: "pose", to: entry)
            return [text("Kept as \(name): the landmark is framed in red, everything else painted black, \(view.line(scene)). compare_with_photo(\"\(name)\") shows the model from the same place. " + coverage())]
                + (image(file).map { [$0] } ?? [])
        }
        return kept
    }
}
