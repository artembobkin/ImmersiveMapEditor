import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The automatic gathering (gather_references): every reference at once
/// by fixed rules, the walk round the facades, the satellite view and the
/// best of Commons. Kept as the automatic way: the agent searches for its
/// references itself.
extension LandmarkMCP.Server {
    /// Every reference gathered at once, with no choice for the agent
    /// (the user, 2026-10-28): the street photos of every facade, the
    /// satellite view, and from Commons the best classic view of the
    /// whole and the best view from above, each kept only when the
    /// scene classifier sees a building in it. What was gathered, as
    /// text; the pictures come with list_references.
    func gather() throws -> [[String: Any]] {
        var lines: [String] = []
        let had = credited()
        if had.contains(where: { $0["pose"] != nil }) {
            lines.append("Street photos are kept already (\(had.filter { $0["pose"] != nil }.count)): not gathered again.")
        } else {
            do {
                let said = try streetPhotos([:])
                lines.append((said.first?["text"] as? String ?? "").components(separatedBy: "\nEvery station's photos").first ?? "")
            } catch {
                lines.append("Street photos: \(error)")
            }
        }
        if had.contains(where: { $0["file"] as? String == "satellite.jpg" }) {
            lines.append("The satellite view is kept already.")
        } else {
            do {
                let said = try satellite([:])
                lines.append(said.first?["text"] as? String ?? "")
            } catch {
                lines.append("The satellite view: \(error)")
            }
        }
        if had.contains(where: { $0["pose"] == nil && $0["file"] as? String != "satellite.jpg" }) {
            lines.append("Commons photos are kept already.")
        } else {
            lines += commonsAuto()
        }
        lines.append(coverage())
        return [text(lines.joined(separator: "\n"))]
    }

    /// From Commons, with no one choosing: the best classic view of the
    /// whole (not from above) and the best view from above, each the
    /// first of its candidates in which the scene classifier sees a
    /// building (0.4 at least); the rest dropped as they come.
    func commonsAuto() -> [String] {
        guard let source = try? LandmarkSource(folder.appendingPathComponent("landmark.json")),
              let (category, photos) = try? CommonsPhotos.find(tags: source.buildings.map(\.tags), lon: source.centre.0, lat: source.centre.1, radius: 150, run: Self.run) else {
            return ["Commons did not answer."]
        }
        guard !photos.isEmpty else { return ["Commons has no freely licensed photos " + (category.map { "in \"\($0)\" or " } ?? "") + "within 150 m."] }
        var out: [String] = []
        for (what, candidates) in [("the whole", photos.filter { !$0.aerial }), ("from above", photos.filter(\.aerial))] {
            var kept = false
            for p in candidates.prefix(4) {
                guard let photo = try? CommonsPhotos.file(p.title, width: 1600, run: Self.run), let url = photo.thumb else { continue }
                let licence = photo.licence
                guard licence.hasPrefix("CC") && !licence.contains("NC") && !licence.contains("ND") || licence.contains("Public domain") || licence == "CC0" else { continue }
                guard let said = try? keep(url, page: photo.page, author: photo.author.isEmpty ? "unknown (Wikimedia Commons)" : "\(photo.author) (Wikimedia Commons)",
                                           licence: licence, shows: "Commons, \(what == "the whole" ? "a view of the whole" : "a view from above"): \(String(p.description.prefix(120)))"),
                      let name = (said.first?["text"] as? String)?.split(separator: " ").last.map(String.init),
                      let found = reference(name) else { continue }
                // A building in it, or it goes.
                if let src = CGImageSourceCreateWithURL(found.url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
                   FrameCheck.classify(img).building < 0.4 {
                    _ = try? dropReference(name)
                    continue
                }
                out.append("Commons, \(what): kept \(name), \(p.line)")
                kept = true
                break
            }
            if !kept { out.append("Commons, \(what): nothing fit among \(min(4, candidates.count)) candidates.") }
        }
        return out
    }
}
