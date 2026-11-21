import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// Wikimedia Commons' photos of the landmark found and kept
/// (find_commons_photos, save_commons_photo).
extension LandmarkMCP.Server {
    func commonsPhotos(_ args: [String: Any]) throws -> [[String: Any]] {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        let radius = (args["radius"] as? NSNumber)?.doubleValue ?? 150
        let limit = max(1, min(5, (args["limit"] as? NSNumber)?.intValue ?? 5))
        let pictures = args["pictures"] as? Bool ?? false
        let (category, photos) = try CommonsPhotos.find(tags: source.buildings.map(\.tags), lon: source.centre.0, lat: source.centre.1,
                                                        radius: radius, run: Self.run)
        let where_ = category.map { "its category \"\($0)\" and " } ?? "no category of its own (no wikimedia_commons or wikidata tag): "
        guard !photos.isEmpty else { return [text("Commons has no freely licensed photos in \(where_)within \(Int(radius)) m.")] }
        let picks = Array(photos.prefix(limit))
        let dir = searchFolder.appendingPathComponent("commons")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cells = picks.enumerated().map { k, p -> ContactSheet.Cell in
            let file = dir.appendingPathComponent("\(k + 1).jpg")
            var image: URL? = nil
            if let thumb = p.thumb {
                let status = Download.file(thumb, to: file, timeout: 60, agent: CommonsPhotos.agent).status
                _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "640", "-s", "format", "jpeg", file.path, "--out", file.path])
                if status == 0 { image = file }
            }
            return ContactSheet.Cell(image: image, box: nil, cut: false, label: "#\(k + 1)  \(String(p.title.dropFirst("File:".count).prefix(40)))")
        }
        let sheet = dir.appendingPathComponent("sheet.jpg")
        try ContactSheet.draw(cells, to: sheet)
        var content: [[String: Any]] = [text("Commons: \(photos.count) freely licensed photos in \(where_)within \(Int(radius)) m; the \(picks.count) best follow, numbered" + (pictures ? "." : " (their descriptions; pictures: true for their pictures). Keep one with save_commons_photo(file, shows): it comes back to look at, and drop_reference it if it is not what you need."))]
        for (k, p) in picks.enumerated() {
            content.append(text("#\(k + 1) " + p.line))
            if pictures, let file = cells[k].image, let img = image(file) { content.append(img) }
        }
        return content
    }

    func saveCommonsPhoto(_ args: [String: Any]) throws -> [[String: Any]] {
        guard var title = args["file"] as? String, !title.isEmpty else { throw Failure("give the file's name from find_commons_photos") }
        guard let shows = args["shows"] as? String, !shows.isEmpty else { throw Failure("say what it shows") }
        if !title.hasPrefix("File:") { title = "File:" + title }
        guard let photo = try CommonsPhotos.file(title, width: 1600, run: Self.run), let url = photo.thumb else { throw Failure("Commons has no \(title)") }
        let licence = photo.licence
        guard licence.hasPrefix("CC") && !licence.contains("NC") && !licence.contains("ND") || licence.contains("Public domain") || licence == "CC0" else {
            throw Failure("\(title) is not freely licensed (\(licence)): not kept")
        }
        let kept = try keep(url, page: photo.page, author: photo.author.isEmpty ? "unknown (Wikimedia Commons)" : "\(photo.author) (Wikimedia Commons)",
                            licence: licence, shows: shows)
        return kept.enumerated().map { k, item in k == 0 ? text((item["text"] as? String ?? "") + ". " + coverage()) : item }
    }
}
