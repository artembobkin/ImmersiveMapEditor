import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The references kept in the landmark's references/ with their credits:
/// listed (list_references), a photo saved from a URL, dropped or shown
/// again, and how much of each facade they cover.
extension LandmarkMCP.Server {
    var credits: URL { references.appendingPathComponent("credits.json") }

    /// The credits of the photos still there: one the user deleted in the
    /// Finder (or the editor) is gone from the credits too, so it counts
    /// for nothing and its number is free again.
    func credited() -> [[String: Any]] {
        let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
        let kept = list.filter { e in
            guard let file = e["file"] as? String else { return true }
            return FileManager.default.fileExists(atPath: references.appendingPathComponent(file).path)
        }
        if kept.count != list.count,
           let data = try? JSONSerialization.data(withJSONObject: kept, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? data.write(to: credits)
        }
        return kept
    }


    func savePhoto(_ args: [String: Any]) throws -> [[String: Any]] {
        guard let url = args["url"] as? String, url.hasPrefix("https://") else { throw Failure("give the photo's https URL") }
        for key in ["page", "author", "licence", "shows"] where (args[key] as? String ?? "").isEmpty {
            throw Failure("give its \(key): only freely licensed photos are kept, credited")
        }
        return try keep(url, page: args["page"] as! String, author: args["author"] as! String,
                        licence: args["licence"] as! String, shows: args["shows"] as! String)
    }


    /// The references kept, as text and as the pictures the agent works
    /// from: the best street photo of each facade, the satellite view,
    /// the Commons photos.
    func listReferences() throws -> [[String: Any]] {
        // Nothing gathered for the agent beforehand: it searches for its
        // references itself (the user, 2026-11-21: the fixed rules of the
        // gathering often took the wrong building).
        let list = credited()
        // What the gathering kept beforehand (gather_references, or the editor's
        // Gather References before 2026-11-21) is a start, never
        // the answer: said, so the agent checks it against its own search.
        let automatic = list.contains { ($0["shows"] as? String ?? "").contains("kept by find_street_photos") }
        let gathered = list.isEmpty
            ? "No reference is kept yet: find them yourself, satellite_view for the roofs, search_street_photos facade by facade, find_commons_photos for the whole.\n\n"
            : automatic ? "Some street photos here were kept beforehand by fixed rules (\"kept by find_street_photos\"), which often take the wrong building or an old photo: check each, search_street_photos for newer and better ones, and drop_reference what is wrong.\n\n" : ""
        let json = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        var content: [[String: Any]] = [text(gathered + (String(data: json, encoding: .utf8) ?? "[]") + "\n" + coverage())]
        if let scene = try? StreetScene(folder: folder) {
            for f in scene.facades.indices.sorted(by: { scene.facades[$0].length > scene.facades[$1].length }) {
                guard let file = bestPhotos(Self.facadeFolder(scene.facades[f].name)).first, let found = reference(file), let img = image(found.url) else { continue }
                content.append(text("\(file), the best photo of \(scene.facades[f].name):"))
                content.append(img)
            }
        }
        for e in list {
            guard let file = e["file"] as? String, e["pose"] == nil, let found = reference(file) else { continue }
            let small = file == "satellite.jpg" ? searchFolder.appendingPathComponent("satellite/view.jpg") : found.url
            guard let img = image(FileManager.default.fileExists(atPath: small.path) ? small : found.url) else { continue }
            content.append(text("\(file): \(e["shows"] as? String ?? "")"))
            content.append(img)
        }
        return content
    }

    /// What the references cover so far: the street photos by the
    /// facades their cameras see, the Commons photos and the satellite
    /// apart, and the facades with nothing yet. Told after every keep,
    /// so the agent sees the gaps.
    func coverage() -> String {
        let list = credited()
        var street = 0, commons = 0, satellite = 0
        for e in list {
            if e["pose"] != nil { street += 1 } else if e["file"] as? String == "satellite.jpg" { satellite += 1 } else { commons += 1 }
        }
        guard let scene = try? StreetScene(folder: folder) else { return "" }
        // What the kept photos show of each facade together.
        var covered: [[Bool]] = scene.facades.map { [Bool](repeating: false, count: $0.samples.count) }
        for (_, view) in keptViews(scene) {
            for f in covered.indices where view.seen[f] >= StreetView.enough && view.looks[f] > 0 {
                for i in covered[f].indices where view.seenSamples[f][i] { covered[f][i] = true }
            }
        }
        let order = scene.facades.indices.sorted { scene.facades[$0].length > scene.facades[$1].length }
        func fraction(_ f: Int) -> Double { Double(covered[f].filter { $0 }.count) / Double(max(1, covered[f].count)) }
        let have = order.filter { fraction($0) > 0 }.map { "\(scene.facades[$0].name) \(scene.part($0, covered[$0]))" }
        let missing = order.filter { fraction($0) <= 0.85 }.map { f -> String in
            "\(scene.facades[f].name) (\(Int(scene.facades[f].length)) m" + (fraction(f) > 0 ? ", the rest of it)" : ")")
        }
        return "Kept so far: " + (street == 0 ? "no street photo" : "street photos showing " + have.joined(separator: ", "))
            + ", \(commons) from Commons (their side unknown)" + (satellite > 0 ? ", the satellite view" : "")
            + (missing.isEmpty ? ". Every facade is seen whole." : ". Not seen yet: \(missing.joined(separator: ", ")). A candidate that shows it is worth keeping, even a dashcam's glancing look.")
    }

    /// A kept photo that turned out not to show the landmark: gone, with
    /// its credit.
    func dropReference(_ name: String) throws -> String {
        guard let (file, relative) = reference(name), file.pathExtension == "jpg" else { throw Failure("no reference \(name)") }
        try FileManager.default.removeItem(at: file)
        // A folder of a facade left empty goes too.
        let dir = file.deletingLastPathComponent()
        if dir.standardizedFileURL != references.standardizedFileURL, (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: dir)
        }
        var list = credited()
        list.removeAll { $0["file"] as? String == relative }
        try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
        return "Dropped \(relative)"
    }


    func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    static func size(of file: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        return (w, h)
    }

    /// Adds a field to a kept photo's credit.
    func credit(_ file: String, set key: String, to value: Any) throws {
        var list = credited()
        guard let k = list.firstIndex(where: { $0["file"] as? String == file }) else { return }
        list[k][key] = value
        try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
    }

    /// Downloads a photo into the references (into `sub`, a folder of
    /// them, when given) with its credit, its file in the credits by its
    /// path within the references.
    func keep(_ url: String, page: String, author: String, licence: String, shows: String, maxSide: Int = 1280,
              into sub: String? = nil) throws -> [[String: Any]] {
        let dir = sub.map { references.appendingPathComponent($0) } ?? references
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var list = credited()
        let raw = references.appendingPathComponent("download.tmp")
        let answer = Download.file(url, to: raw, timeout: 300, agent: CommonsPhotos.agent, maximum: 30_000_000)
        let (status, said) = (answer.status, answer.said)
        guard status == 0 else { throw Failure("cannot download it: \(said)") }
        let head = (try? FileHandle(forReadingFrom: raw).readData(ofLength: 12)) ?? Data()
        let isImage = head.starts(with: [0xFF, 0xD8]) || head.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || (head.count >= 12 && head[8...11] == Data("WEBP".utf8))
        guard isImage else {
            try? FileManager.default.removeItem(at: raw)
            throw Failure("that is not a JPEG, PNG or WebP image: give the direct image URL")
        }
        // The first number free in every folder: after a drop_reference
        // the count of the credits would name a photo still there, and a
        // name stays one photo whatever folder it is in.
        let taken = Set(list.compactMap { ($0["file"] as? String).map { ($0 as NSString).lastPathComponent } })
            .union(FileManager.default.enumerator(atPath: references.path)?.compactMap { ($0 as? NSString)?.lastPathComponent } ?? [])
        let number = (1...).first { !taken.contains(String(format: "photo-%02d.jpg", $0)) }!
        let name = String(format: "photo-%02d.jpg", number)
        let relative = sub.map { "\($0)/\(name)" } ?? name
        let file = references.appendingPathComponent(relative)
        _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "\(maxSide)", "-s", "format", "jpeg", raw.path, "--out", file.path])
        try? FileManager.default.removeItem(at: raw)
        guard FileManager.default.fileExists(atPath: file.path) else { throw Failure("cannot read the image") }
        list.append(["file": relative, "url": url, "page": page, "author": author, "licence": licence, "shows": shows])
        try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
        return [text("Kept as \(relative)")] + (image(file).map { [$0] } ?? [])
    }

    /// A kept reference by the name the agent gives: its path within the
    /// references ("north-facade/photo-03.jpg"), or its file name alone,
    /// found by the credits. Never outside the references.
    func reference(_ name: String) -> (url: URL, relative: String)? {
        var path = name.hasPrefix("references/") ? String(name.dropFirst("references/".count)) : name
        guard !path.split(separator: "/").contains("..") else { return nil }
        if !FileManager.default.fileExists(atPath: references.appendingPathComponent(path).path) {
            let list = credited()
            guard let found = list.compactMap({ $0["file"] as? String }).first(where: { ($0 as NSString).lastPathComponent == (path as NSString).lastPathComponent }) else { return nil }
            path = found
        }
        let url = references.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? (url, path) : nil
    }
}
