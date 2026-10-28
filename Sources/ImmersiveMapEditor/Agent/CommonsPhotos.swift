import Foundation

/// Photos of a landmark on Wikimedia Commons, through its API: the files
/// of the landmark's category (OSM's wikimedia_commons tag, or the
/// category of its wikidata item) and the files geotagged around it, each
/// with its licence, author, date, size and description. Only freely
/// licensed ones are offered (CC0, CC BY, CC BY-SA, public domain). The
/// street shows the facades; Commons shows the whole from afar, the roofs
/// from above (aerial and drone photos), and the details.
enum CommonsPhotos {
    struct Photo {
        let title: String
        let page: String
        let thumb: String?
        let width: Int, height: Int
        let licence: String
        let author: String
        let date: String
        let description: String
        let score: Double
        /// From above (aerial, drone, the roofs), by its words.
        var aerial = false

        var line: String {
            let what = description.isEmpty ? "" : ": " + String(description.prefix(110))
            return "\(title) (\(width)×\(height), \(date), \(author), \(licence))\(what)"
        }
    }

    static let agent = "ImmersiveMapEditor/1 (landmark references; https://github.com/artembobkin/ImmersiveMapEditor)"

    static func api(_ host: String, _ query: [String: String], run: (URL, [String]) -> (Int32, String)) throws -> [String: Any] {
        var c = URLComponents(string: "https://\(host)/w/api.php")!
        c.queryItems = (query.merging(["format": "json"]) { a, _ in a }).map { URLQueryItem(name: $0.key, value: $0.value) }
        let (status, said) = run(URL(fileURLWithPath: "/usr/bin/curl"), ["-sSL", "--http1.1", "--max-time", "60", "-A", agent, c.url!.absoluteString])
        guard status == 0, let json = try? JSONSerialization.jsonObject(with: Data(said.utf8)) as? [String: Any] else {
            throw NSError(domain: "Commons", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(host) did not answer: \(said.prefix(200))"])
        }
        return json
    }

    /// The landmark's Commons category: OSM's tag, else its wikidata item's.
    static func category(tags: [[String: String]], run: (URL, [String]) -> (Int32, String)) -> String? {
        for t in tags {
            if let c = t["wikimedia_commons"], c.hasPrefix("Category:") { return String(c.dropFirst("Category:".count)) }
        }
        for t in tags {
            guard let q = t["wikidata"], q.hasPrefix("Q"),
                  let json = try? api("www.wikidata.org", ["action": "wbgetclaims", "entity": q, "property": "P373"], run: run),
                  let claims = (json["claims"] as? [String: Any])?["P373"] as? [[String: Any]],
                  let value = ((claims.first?["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] as? String else { continue }
            return value
        }
        return nil
    }

    /// The photos of the category (and its subcategories, one level down)
    /// and around the place, the best first.
    static func find(tags: [[String: String]], lon: Double, lat: Double, radius: Double, run: (URL, [String]) -> (Int32, String)) throws -> (category: String?, photos: [Photo]) {
        var pages: [String: [String: Any]] = [:]
        var inCategory = Set<String>()
        // The landmark's names, to tell a geotagged photo of it from one of
        // the square it stands on.
        let names = Set(tags.flatMap { t in ["name", "name:en", "name:ru", "alt_name", "old_name"].compactMap { t[$0]?.lowercased() } })
        let props = ["prop": "imageinfo", "iiprop": "url|size|extmetadata", "iiurlwidth": "1024"]
        let category = category(tags: tags, run: run)
        if let category {
            var categories = [category]
            if let sub = try? api("commons.wikimedia.org", ["action": "query", "list": "categorymembers", "cmtitle": "Category:" + category,
                                                              "cmtype": "subcat", "cmlimit": "20"], run: run),
               let members = (sub["query"] as? [String: Any])?["categorymembers"] as? [[String: Any]] {
                // The outside first; what happens inside is not for a model.
                let inside = ["interior", "inside", "performance", "people", "event", "ticket", "plaque", "stage", "hall", "foyer", "ballet", "opera", "concert", "night"]
                let subs = members.compactMap { ($0["title"] as? String).map { String($0.dropFirst("Category:".count)) } }
                    .filter { name in !inside.contains { name.lowercased().contains($0) } }
                    .sorted { a, _ in ["exterior", "facade", "aerial", "view"].contains { a.lowercased().contains($0) } }
                categories += subs
            }
            for c in categories.prefix(8) {
                let json = try api("commons.wikimedia.org", props.merging(["action": "query", "generator": "categorymembers", "gcmtitle": "Category:" + c,
                                                                           "gcmtype": "file", "gcmlimit": "100"]) { a, _ in a }, run: run)
                for (id, p) in (json["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] ?? [:] {
                    pages[id] = p
                    inCategory.insert(id)
                }
            }
        }
        let geo = try api("commons.wikimedia.org", props.merging(["action": "query", "generator": "geosearch", "ggscoord": "\(lat)|\(lon)",
                                                                   "ggsradius": "\(Int(max(50, min(500, radius))))", "ggsnamespace": "6", "ggslimit": "100"]) { a, _ in a }, run: run)
        for (id, p) in (geo["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] ?? [:] { pages[id] = p }
        var photos: [Photo] = []
        for (id, p) in pages {
            guard let title = p["title"] as? String, let info = (p["imageinfo"] as? [[String: Any]])?.first else { continue }
            let meta = (info["extmetadata"] as? [String: [String: Any]]) ?? [:]
            func m(_ key: String) -> String { strip((meta[key]?["value"] as? String) ?? "") }
            let licence = m("LicenseShortName")
            let free = licence.hasPrefix("CC") && !licence.contains("NC") && !licence.contains("ND") || licence.contains("Public domain") || licence == "CC0"
            guard free else { continue }
            let ext = (title as NSString).pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "webp"].contains(ext) else { continue }
            let width = (info["width"] as? NSNumber)?.intValue ?? 0, height = (info["height"] as? NSNumber)?.intValue ?? 0
            guard width >= 600 else { continue }
            let description = m("ImageDescription")
            let text = (title + " " + description).lowercased()
            let aerial = ["aerial", "drone", "from above", "bird", "roof", "сверху", "с высоты", "аэро", "крыш"].contains { text.contains($0) }
            let inside = ["interior", "inside", "внутри", "зал", "ложа", "ложи", "сцен", "seat", "балкон", "ярус", "auditorium", "foyer", "фойе",
                          "chandelier", "люстр", "stage", "performance", "спектакл", "balcony", "orchestra", "оркестр", "concert", "ceiling", "потол",
                          "ballet", "state opera", "production", "premiere", "премьер", "artist", "актёр", "актер", "dancer", "singer", "rehearsal"]
                .contains { text.contains($0) }
            let named = inCategory.contains(id) || names.contains { text.contains($0) } || text.contains("bolshoi") || text.contains("большой")
            let date = String(m("DateTimeOriginal").prefix(7))
            let year = Double(date.prefix(4)) ?? 2005
            // Newer, larger, the views from above the street cannot give,
            // the outside over the inside, the landmark over its surroundings.
            let score = (aerial ? 2.0 : 1.0) * (inside ? 0.15 : 1) * (named ? 1 : 0.3) * min(1, Double(width) / 2500) * max(0.5, 1 - (2026 - year) * 0.04)
            photos.append(Photo(title: title, page: info["descriptionurl"] as? String ?? "https://commons.wikimedia.org/wiki/" + title,
                                thumb: info["thumburl"] as? String ?? info["url"] as? String, width: width, height: height,
                                licence: licence, author: String(m("Artist").prefix(60)), date: date, description: description, score: score, aerial: aerial))
        }
        // The same author's photos of the same day are one series: the
        // second and the rest come down, so the list spans more.
        var seen: [String: Int] = [:]
        let spread = photos.sorted { $0.score > $1.score }.map { p -> Photo in
            let key = p.author + "|" + p.date
            let k = seen[key, default: 0]
            seen[key] = k + 1
            return Photo(title: p.title, page: p.page, thumb: p.thumb, width: p.width, height: p.height, licence: p.licence, author: p.author,
                         date: p.date, description: p.description, score: p.score * pow(0.5, Double(k)), aerial: p.aerial)
        }
        return (category, spread.sorted { $0.score > $1.score })
    }

    /// One file's picture at a width, its page, author and licence.
    static func file(_ title: String, width: Int, run: (URL, [String]) -> (Int32, String)) throws -> Photo? {
        let json = try api("commons.wikimedia.org", ["action": "query", "titles": title, "prop": "imageinfo", "iiprop": "url|size|extmetadata",
                                                     "iiurlwidth": "\(width)"], run: run)
        guard let p = ((json["query"] as? [String: Any])?["pages"] as? [String: [String: Any]])?.values.first,
              let info = (p["imageinfo"] as? [[String: Any]])?.first else { return nil }
        let meta = (info["extmetadata"] as? [String: [String: Any]]) ?? [:]
        func m(_ key: String) -> String { strip((meta[key]?["value"] as? String) ?? "") }
        return Photo(title: p["title"] as? String ?? title, page: info["descriptionurl"] as? String ?? "",
                     thumb: info["thumburl"] as? String ?? info["url"] as? String,
                     width: (info["width"] as? NSNumber)?.intValue ?? 0, height: (info["height"] as? NSNumber)?.intValue ?? 0,
                     licence: m("LicenseShortName"), author: String(m("Artist").prefix(60)), date: String(m("DateTimeOriginal").prefix(7)),
                     description: m("ImageDescription"), score: 0)
    }

    /// Text without its HTML tags and entities, on one line.
    static func strip(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (e, c) in [("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { s = s.replacingOccurrences(of: e, with: c) }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
