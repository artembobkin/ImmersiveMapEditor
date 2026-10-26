import Foundation
import Geometry
import simd
import TileKit

/// The landmarks' agent's modelling tools: an MCP server on standard input
/// and output (JSON-RPC, a message a line), run by Claude Code as
/// `ImmersiveMapEditor landmark-mcp FOLDER` for one landmark's folder. Its
/// tools read the landmark's OSM, write and build its recipe, render the
/// model from around, and keep reference photos with their credits. They
/// touch nothing outside the folder. Downloads go through curl, which takes
/// the proxy from the environment Claude Code runs in.
enum LandmarkMCP {
    static func run(folder: URL) -> Never {
        let server = Server(folder: folder.standardizedFileURL)
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let reply = server.handle(message),
               let out = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]) {
                FileHandle.standardOutput.write(out + Data("\n".utf8))
            }
        }
        exit(0)
    }

    final class Server {
        let folder: URL
        var references: URL { folder.appendingPathComponent("references") }
        var viewsFolder: URL { folder.appendingPathComponent("views") }

        init(folder: URL) { self.folder = folder }

        /// The reply to a message, nil for a notification.
        func handle(_ m: [String: Any]) -> [String: Any]? {
            guard let id = m["id"] else { return nil }
            let params = m["params"] as? [String: Any] ?? [:]
            switch m["method"] as? String ?? "" {
            case "initialize":
                return ok(id, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                               "capabilities": ["tools": [:]],
                               "serverInfo": ["name": "landmark", "version": "1"]])
            case "ping":
                return ok(id, [:])
            case "tools/list":
                return ok(id, ["tools": Self.tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                do {
                    return ok(id, ["content": try call(name, args), "isError": false])
                } catch {
                    return ok(id, ["content": [text("\(error)")], "isError": true])
                }
            default:
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "no method \(m["method"] ?? "")"]]
            }
        }

        func ok(_ id: Any, _ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }
        func image(_ url: URL) -> [String: Any]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            return ["type": "image", "data": data.base64EncodedString(), "mimeType": mime]
        }

        struct Failure: Error, CustomStringConvertible {
            let description: String
            init(_ d: String) { description = d }
        }

        // MARK: The tools

        static let tools: [[String: Any]] = [
            ["name": "get_landmark",
             "description": "The landmark: its name, centre, and every OSM building and building:part it is made of, a line each (id, part or outline, base and height, plan size and middle in metres east and north of the centre, area, the tags that shape it). Then the recipe format and the palette's colours. Read it first.",
             "inputSchema": ["type": "object", "properties": [:]]],
            ["name": "get_outlines",
             "description": "The outline rings of some of the landmark's OSM buildings (up to 40 ids a call), in metres east and north of the centre, simplified to 0.3 m: to place features (colonnades, pediments) on the right lines, or to draw a polygon of your own.",
             "inputSchema": ["type": "object", "properties": ["ids": ["type": "array", "items": ["type": "string"]]], "required": ["ids"]]],
            ["name": "get_recipe",
             "description": "The landmark's current recipe (recipe.json), or a starter recipe made from OSM's tags when it has none yet.",
             "inputSchema": ["type": "object", "properties": [:]]],
            ["name": "set_recipe",
             "description": "Writes the recipe and builds the model from it (model.glb). Returns the problems when it cannot build (nothing is written then), else what was built. The editor shows the model as soon as it is built.",
             "inputSchema": ["type": "object", "properties": ["recipe": ["type": "object", "description": "The whole recipe, in the format get_landmark describes."]],
                             "required": ["recipe"]]],
            ["name": "render_views",
             "description": "Renders the model (or the OSM boxes, with boxes: true) and returns the pictures, to compare with the photos. Views: from-south, from-east, from-north, from-west (eye level), from-south-west, from-north-east (a slant), from-above (north up).",
             "inputSchema": ["type": "object", "properties": [
                "views": ["type": "array", "items": ["type": "string"], "description": "Which views; four by default: from-south-west, from-north-east, from-south, from-above."],
                "boxes": ["type": "boolean", "description": "The OSM buildings as boxes instead of the model."]]]],
            ["name": "save_reference_photo",
             "description": "Downloads a photo of the landmark into its references and returns it to look at. Only freely licensed photos (Wikimedia Commons: CC BY, CC BY-SA, CC0, public domain) or the user's own: give the direct image URL (upload.wikimedia.org, a thumbnail of about 1280 px is enough), its page, author and licence, and what it shows (which side, from where).",
             "inputSchema": ["type": "object", "properties": [
                "url": ["type": "string"], "page": ["type": "string"], "author": ["type": "string"],
                "licence": ["type": "string"], "shows": ["type": "string"]],
                             "required": ["url", "page", "author", "licence", "shows"]]],
            ["name": "find_street_photos",
             "description": "Street-level photos of the landmark from Mapillary (CC BY-SA 4.0, credited when kept), judged by their camera poses against the landmark's outlines: the best looks, a track (one pass) at a time, for every side it is seen from, each with its id, distance, side, how much of it and of the frame it fills, date and author; and a contact sheet of them, the landmark framed in red on each, to see which really show it. Keep one with save_street_photo. Needs the Mapillary token of Settings.",
             "inputSchema": ["type": "object", "properties": [
                "radius": ["type": "number", "description": "Metres around the centre, 150 by default."],
                "limit": ["type": "integer", "description": "How many, 15 by default."]]]],
            ["name": "save_street_photo",
             "description": "Downloads one of find_street_photos' pictures by its id into the references, credited (Mapillary, its author, CC BY-SA 4.0), and returns it to look at.",
             "inputSchema": ["type": "object", "properties": ["id": ["type": "string"], "shows": ["type": "string", "description": "What it shows: which side, from where."]],
                             "required": ["id", "shows"]]],
            ["name": "find_commons_photos",
             "description": "Photos of the landmark on Wikimedia Commons (freely licensed only: CC0, CC BY, CC BY-SA, public domain): the files of its category (from OSM's wikimedia_commons or wikidata tag) and the files geotagged around it, the best first (views from above and recent large ones), each with its name, size, date, author, licence and description, and a contact sheet of them. The whole from afar, the roofs from above, the details the street does not show. Keep one with save_commons_photo.",
             "inputSchema": ["type": "object", "properties": [
                "radius": ["type": "number", "description": "Metres around the centre for geotagged files, 150 by default."],
                "limit": ["type": "integer", "description": "How many, 16 by default."]]]],
            ["name": "save_commons_photo",
             "description": "Downloads one of find_commons_photos' files by its name (File:...) into the references, credited (its author and licence), and returns it to look at.",
             "inputSchema": ["type": "object", "properties": ["file": ["type": "string"], "shows": ["type": "string", "description": "What it shows: which side, from where."]],
                             "required": ["file", "shows"]]],
            ["name": "drop_reference",
             "description": "Removes a kept reference photo that turned out not to show the landmark (its credit too).",
             "inputSchema": ["type": "object", "properties": ["file": ["type": "string"]], "required": ["file"]]],
            ["name": "list_references",
             "description": "The reference photos kept, with their credits and what they show.",
             "inputSchema": ["type": "object", "properties": [:]]],
            ["name": "show_reference",
             "description": "Returns one kept reference photo to look at again.",
             "inputSchema": ["type": "object", "properties": ["file": ["type": "string"]], "required": ["file"]]],
        ]

        func call(_ name: String, _ args: [String: Any]) throws -> [[String: Any]] {
            switch name {
            case "get_landmark": return [text(try landmark())]
            case "get_outlines": return [text(try outlines(args["ids"] as? [String] ?? []))]
            case "get_recipe": return [text(try recipeText())]
            case "set_recipe": return [text(try setRecipe(args["recipe"]))]
            case "render_views": return try render(args)
            case "save_reference_photo": return try savePhoto(args)
            case "find_street_photos": return try streetPhotos(args)
            case "find_commons_photos": return try commonsPhotos(args)
            case "save_commons_photo": return try saveCommonsPhoto(args)
            case "drop_reference": return [text(try dropReference(args["file"] as? String ?? ""))]
            case "save_street_photo": return try saveStreetPhoto(args)
            case "list_references": return [text(String(data: (try? Data(contentsOf: credits)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]")]
            case "show_reference":
                let file = (args["file"] as? String ?? "") as NSString
                guard let shown = image(references.appendingPathComponent(file.lastPathComponent)) else { throw Failure("no reference \(file)") }
                return [shown]
            default: throw Failure("no tool \(name)")
            }
        }

        /// The landmark in short, a line a building: its outlines whole would
        /// pass what a tool may return, so they come by get_outlines.
        func landmark() throws -> String {
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            func f(_ v: Double) -> String { String(format: "%.1f", v) }
            var lines = ["Landmark: \(source.name), centre lon/lat \(source.centre.0), \(source.centre.1).",
                         "Its OSM buildings (\(source.buildings.count)): id, part or outline, base..height m, plan size and middle (x east, y north, m), area, the tags that shape it.",
                         "Outlines come by get_outlines (ids), simplified to 0.3 m."]
            for b in source.buildings {
                let pts = b.polygons.flatMap { $0.first ?? [] }
                guard let first = pts.first else { continue }
                let lo = pts.reduce(first) { simd_min($0, $1) }, hi = pts.reduce(first) { simd_max($0, $1) }
                let area = b.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) }
                let tags = b.tags.filter { Self.shapeTag($0.key) }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                lines.append("\(b.osm) \(b.part ? "part" : "outline") \(f(b.base))..\(b.height.map(f) ?? "?") m, "
                             + "\(f(hi.x - lo.x))×\(f(hi.y - lo.y)) at (\(f((lo.x + hi.x) / 2)), \(f((lo.y + hi.y) / 2))), \(Int(area)) m²"
                             + (tags.isEmpty ? "" : ", " + tags.joined(separator: " ")))
            }
            return lines.joined(separator: "\n") + "\n\n" + LandmarkRecipe.guide
        }

        /// Tags that say how a building looks, not where it is or who mapped it.
        static func shapeTag(_ key: String) -> Bool {
            key.hasPrefix("roof:") || key.hasPrefix("building") || ["name", "height", "min_height", "min_level",
                "architecture", "start_date", "colour", "material", "historic", "amenity", "layer"].contains(key)
        }

        /// Outer rings (and holes) of some of the landmark's buildings, in
        /// metres, simplified.
        func outlines(_ ids: [String]) throws -> String {
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            var out: [String] = []
            for id in ids.prefix(40) {
                guard let b = source.buildings.first(where: { $0.osm == id }) else { out.append("\(id): not one of the landmark's"); continue }
                let rings = b.polygons.map { poly -> String in
                    poly.map { ring -> String in
                        let g = Geometry.lineString(ring + [ring[0]]).simplify(0.3).coords
                        return "[" + g.dropLast().map { String(format: "[%.1f, %.1f]", $0.x, $0.y) }.joined(separator: ", ") + "]"
                    }.joined(separator: " hole ")
                }
                out.append("\(id): " + rings.joined(separator: " | "))
            }
            return out.joined(separator: "\n")
        }

        var recipeURL: URL { folder.appendingPathComponent("recipe.json") }
        var credits: URL { references.appendingPathComponent("credits.json") }

        func recipeText() throws -> String {
            // Compact, a mass a line, so a recipe of many parts fits.
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys]
            func lines(_ r: LandmarkRecipe) throws -> String {
                let masses = try r.masses.map { String(data: try e.encode($0), encoding: .utf8)! }
                let features = try r.features.map { String(data: try e.encode($0), encoding: .utf8)! }
                let shapes = try r.shapes.map { String(data: try e.encode($0), encoding: .utf8)! }
                return "{\"version\": 1,\n \"masses\": [\n" + masses.joined(separator: ",\n") + "],\n \"features\": [\n"
                    + features.joined(separator: ",\n") + "],\n \"shapes\": [\n" + shapes.joined(separator: ",\n") + "]}"
            }
            if let recipe = try? LandmarkRecipe.read(recipeURL) { return try lines(recipe) }
            let starter = try LandmarkSource(folder.appendingPathComponent("landmark.json")).starterRecipe()
            return "(no recipe yet: a starter from OSM's tags)\n" + (try lines(starter))
        }

        func setRecipe(_ value: Any?) throws -> String {
            guard let value else { throw Failure("no recipe given") }
            let data = try JSONSerialization.data(withJSONObject: value)
            let recipe: LandmarkRecipe
            do {
                recipe = try JSONDecoder().decode(LandmarkRecipe.self, from: data)
            } catch {
                throw Failure("the recipe does not read: \(error)")
            }
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            let problems = LandmarkGenerator.check(recipe, source)
            guard problems.isEmpty else { return "Not built, the recipe has problems:\n" + problems.joined(separator: "\n") }
            try recipe.write(recipeURL)
            let model = LandmarkGenerator.build(recipe, source)
            try model.write(folder.appendingPathComponent("model.glb"), name: source.name)
            return "Built model.glb: \(model.summary)"
        }

        func render(_ args: [String: Any]) throws -> [[String: Any]] {
            let all = ["from-south", "from-east", "from-north", "from-west", "from-south-west", "from-north-east", "from-above"]
            let asked = (args["views"] as? [String])?.filter(all.contains) ?? ["from-south-west", "from-north-east", "from-south", "from-above"]
            let boxes = args["boxes"] as? Bool ?? false
            let out = viewsFolder.appendingPathComponent(boxes ? "boxes" : "model")
            var command = ["--landmark-views", folder.path, out.path]
            if boxes { command.append("--boxes") }
            let (status, said) = Self.run(URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL, command)
            guard status == 0 else { throw Failure("cannot render: \(said)") }
            var content: [[String: Any]] = []
            for v in asked {
                let png = out.appendingPathComponent("\(v).png")
                let small = out.appendingPathComponent("\(v).small.jpg")
                _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "800", "-s", "format", "jpeg", png.path, "--out", small.path])
                content.append(text(v))
                if let i = image(FileManager.default.fileExists(atPath: small.path) ? small : png) { content.append(i) }
            }
            return content
        }

        func savePhoto(_ args: [String: Any]) throws -> [[String: Any]] {
            guard let url = args["url"] as? String, url.hasPrefix("https://") else { throw Failure("give the photo's https URL") }
            for key in ["page", "author", "licence", "shows"] where (args[key] as? String ?? "").isEmpty {
                throw Failure("give its \(key): only freely licensed photos are kept, credited")
            }
            return try keep(url, page: args["page"] as! String, author: args["author"] as! String,
                            licence: args["licence"] as! String, shows: args["shows"] as! String)
        }

        // MARK: Mapillary

        var mapillaryToken: String {
            get throws {
                guard let t = ProcessInfo.processInfo.environment["MAPILLARY_TOKEN"], !t.isEmpty else {
                    throw Failure("no Mapillary token: the user sets it in Settings > Claude")
                }
                return t
            }
        }

        func mapillary(_ path: String, _ query: [String: String]) throws -> [String: Any] {
            var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            items.append(URLQueryItem(name: "access_token", value: try mapillaryToken))
            var c = URLComponents(string: "https://graph.mapillary.com/" + path)!
            c.queryItems = items
            // Without -f: Mapillary explains an error in its JSON body. Over
            // HTTP/1.1, and twice: the proxy drops an HTTP/2 stream now and then.
            var last = ""
            for _ in 0..<2 {
                let (status, said) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"), ["-sSL", "--http1.1", "--max-time", "60", c.url!.absoluteString])
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
            let dir = viewsFolder.appendingPathComponent("street/tiles")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(CoverageTile.zoom)_\(x)_\(y).mvt")
            if let age = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
               Date().timeIntervalSince(age) < 86_400, let data = try? Data(contentsOf: file), !data.isEmpty { return data }
            let url = "https://tiles.mapillary.com/maps/vtp/mly1_public/2/\(CoverageTile.zoom)/\(x)/\(y)?access_token=\(try mapillaryToken)"
            var last = ""
            for _ in 0..<2 {
                let (status, said) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"),
                                              ["-fsSL", "--http1.1", "--compressed", "--max-time", "120", "-o", file.path, url])
                last = said
                if status == 0, let data = try? Data(contentsOf: file), !data.isEmpty { return data }
            }
            throw Failure("Mapillary's coverage tile did not come: \(last.prefix(200))")
        }

        /// The photos around the landmark that look at it, judged by
        /// geometry (StreetView), the best track by track (StreetPicks).
        func streetPhotos(_ args: [String: Any]) throws -> [[String: Any]] {
            let scene = try StreetScene(folder: folder)
            let radius = max(30, min(400, (args["radius"] as? NSNumber)?.doubleValue ?? 150))
            let limit = max(1, min(40, (args["limit"] as? NSNumber)?.intValue ?? 16))
            // Every photo around, from Mapillary's coverage tiles (the Graph
            // API's box search answers with a different sample every time),
            // judged first by its raw pose, then the best few dozen asked for
            // in full (camera, computed pose, quality) and judged again.
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
            var rough: [(Double, [String: Any])] = []
            for p in points {
                let at = scene.metres(lon: p.lon, lat: p.lat)
                guard simd_length(at) <= radius, let id = p.props["id"].map({ "\($0)" }), !id.isEmpty else { continue }
                var e: [String: Any] = ["id": id, "computed_geometry": ["coordinates": [p.lon, p.lat]],
                                        "is_pano": (p.props["is_pano"] as? Bool) ?? ((p.props["is_pano"] as? UInt64).map { $0 != 0 } ?? false),
                                        "sequence": p.props["sequence_id"].map { "\($0)" } ?? id]
                if let a = p.props["compass_angle"] as? Double { e["computed_compass_angle"] = a }
                else if let a = p.props["compass_angle"] as? Int64 { e["computed_compass_angle"] = Double(a) }
                else if let a = p.props["compass_angle"] as? UInt64 { e["computed_compass_angle"] = Double(a) }
                if let t = p.props["captured_at"] as? Int64 { e["captured_at"] = Double(t) }
                else if let t = p.props["captured_at"] as? UInt64 { e["captured_at"] = Double(t) }
                else if let t = p.props["captured_at"] as? Double { e["captured_at"] = t }
                guard let photo = StreetPhoto(e, scene), let view = StreetView(photo, in: scene, quick: true) else { continue }
                rough.append((view.score, e))
            }
            let total = points.filter { simd_length(scene.metres(lon: $0.lon, lat: $0.lat)) <= radius }.count
            // The best few hundred judged with what hides them, then the best
            // of every side, a hundred in all, asked for in full, thirty ids
            // a call.
            var judged: [(Double, String, [String: Any])] = []
            for (_, e) in rough.sorted(by: { $0.0 > $1.0 }).prefix(500) {
                guard let photo = StreetPhoto(e, scene), let view = StreetView(photo, in: scene) else { continue }
                judged.append((view.score, StreetView.side(view.from), e))
            }
            var perSide: [String: Int] = [:]
            var asked: [String] = []
            for (_, side, e) in judged.sorted(by: { $0.0 > $1.0 }) where asked.count < 100 && perSide[side, default: 0] < 16 {
                perSide[side, default: 0] += 1
                asked.append(e["id"] as! String)
            }
            var photos: [String: [String: Any]] = [:]
            for chunk in stride(from: 0, to: asked.count, by: 30).map({ Array(asked[$0..<min($0 + 30, asked.count)]) }) {
                let json = try mapillary("", ["ids": chunk.joined(separator: ","), "fields": StreetPhoto.fields])
                for (id, e) in json where chunk.contains(id) { if let e = e as? [String: Any] { photos[id] = e } }
            }
            func text(_ s: String) -> [String: Any] { self.text(s) }
            let photosCount = total
            let views = photos.values.compactMap { StreetPhoto($0, scene) }.filter { simd_length($0.at) <= radius }
                .compactMap { StreetView($0, in: scene) }
            guard !views.isEmpty else {
                return [text("Of \(photosCount) street photos within \(Int(radius)) m none shows the landmark well. Try a larger radius.")]
            }
            let (report, picks) = StreetPicks.report(views, limit: limit)
            guard !picks.isEmpty else { return [text("Of \(photosCount) street photos within \(Int(radius)) m none gives a good look at the landmark.")] }
            // The contact sheet: a small thumbnail of each pick, framed.
            let dir = viewsFolder.appendingPathComponent("street")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let thumbs: [URL?] = picks.map { pick in
                let file = dir.appendingPathComponent("\(pick.photo.id).jpg")
                if FileManager.default.fileExists(atPath: file.path) { return file }
                guard let json = try? mapillary(pick.photo.id, ["fields": pick.photo.pano ? "thumb_1024_url" : "thumb_256_url"]),
                      let url = (json["thumb_1024_url"] ?? json["thumb_256_url"]) as? String else { return nil }
                let (status, _) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"), ["-fsSL", "--max-time", "30", "-o", file.path, url])
                return status == 0 ? file : nil
            }
            let sheet = dir.appendingPathComponent("sheet.jpg")
            try StreetPicks.sheet(picks, thumbs: thumbs, to: sheet)
            var content: [[String: Any]] = [text(
                "\(photosCount) street photos within \(Int(radius)) m, \(views.count) show the landmark. The best, a track (one pass of a car or a walker) at a time:\n"
                + report
                + "\nThe contact sheet shows them, numbered, the landmark framed in red by Mapillary's camera poses, which are sometimes wrong: look, and keep only the ones whose red frame really holds the landmark (compare with the photos you know), with save_street_photo(id, shows). A kept photo comes back framed (a panorama cut to it): if the frame is on the wrong building, drop_reference it. Licence CC BY-SA 4.0, credited to Mapillary and its author.")]
            if let img = image(sheet) { content.append(img) }
            return content
        }

        // MARK: Wikimedia Commons

        func commonsPhotos(_ args: [String: Any]) throws -> [[String: Any]] {
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            let radius = (args["radius"] as? NSNumber)?.doubleValue ?? 150
            let limit = max(1, min(30, (args["limit"] as? NSNumber)?.intValue ?? 16))
            let (category, photos) = try CommonsPhotos.find(tags: source.buildings.map(\.tags), lon: source.centre.0, lat: source.centre.1,
                                                            radius: radius, run: Self.run)
            let where_ = category.map { "its category \"\($0)\" and " } ?? "no category of its own (no wikimedia_commons or wikidata tag): "
            guard !photos.isEmpty else { return [text("Commons has no freely licensed photos in \(where_)within \(Int(radius)) m.")] }
            let picks = Array(photos.prefix(limit))
            let dir = viewsFolder.appendingPathComponent("commons")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let cells = picks.enumerated().map { k, p -> ContactSheet.Cell in
                let file = dir.appendingPathComponent("\(k + 1).jpg")
                var image: URL? = nil
                if let thumb = p.thumb {
                    let (status, _) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"), ["-fsSL", "--http1.1", "--max-time", "60", "-A", CommonsPhotos.agent, "-o", file.path, thumb])
                    _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "400", "-s", "format", "jpeg", file.path, "--out", file.path])
                    if status == 0 { image = file }
                }
                return ContactSheet.Cell(image: image, box: nil, cut: false, label: "#\(k + 1)  \(String(p.title.dropFirst("File:".count).prefix(40)))")
            }
            let sheet = dir.appendingPathComponent("sheet.jpg")
            try ContactSheet.draw(cells, to: sheet)
            var content: [[String: Any]] = [text("Commons: \(photos.count) freely licensed photos in \(where_)within \(Int(radius)) m; the \(picks.count) best:\n"
                + picks.enumerated().map { "#\($0 + 1) " + $1.line }.joined(separator: "\n")
                + "\nThe contact sheet shows them numbered. Keep one with save_commons_photo(file, shows).")]
            if let img = image(sheet) { content.append(img) }
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
            return try keep(url, page: photo.page, author: photo.author.isEmpty ? "unknown (Wikimedia Commons)" : "\(photo.author) (Wikimedia Commons)",
                            licence: licence, shows: shows)
        }

        /// A kept photo that turned out not to show the landmark: gone, with
        /// its credit.
        func dropReference(_ name: String) throws -> String {
            let file = references.appendingPathComponent((name as NSString).lastPathComponent)
            guard file.pathExtension == "jpg", FileManager.default.fileExists(atPath: file.path) else { throw Failure("no reference \(name)") }
            try FileManager.default.removeItem(at: file)
            var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            list.removeAll { $0["file"] as? String == file.lastPathComponent }
            try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
            return "Dropped \(file.lastPathComponent)"
        }

        func saveStreetPhoto(_ args: [String: Any]) throws -> [[String: Any]] {
            guard let id = args["id"] as? String, !id.isEmpty, id.allSatisfy(\.isNumber) else { throw Failure("give the photo's id from find_street_photos") }
            guard let shows = args["shows"] as? String, !shows.isEmpty else { throw Failure("say what it shows") }
            let scene = try StreetScene(folder: folder)
            let json = try mapillary(id, ["fields": StreetPhoto.fields + ",thumb_2048_url,thumb_original_url"])
            if let error = json["error"] as? [String: Any] { throw Failure("Mapillary: \(error["message"] ?? error)") }
            guard let photo = StreetPhoto(json, scene), let url = photo.thumb else { throw Failure("Mapillary has no picture for \(id)") }
            guard let view = StreetView(photo, in: scene) else { throw Failure("that photo does not show the landmark") }
            let kept = try keep(photo.pano ? url : (json["thumb_2048_url"] as? String ?? url),
                                page: "https://www.mapillary.com/app/?pKey=\(id)", author: "\(photo.author) (Mapillary)",
                                licence: "CC BY-SA 4.0", shows: shows + " (the landmark is the building framed in red)")
            if let name = (kept.first?["text"] as? String)?.split(separator: " ").last {
                let file = references.appendingPathComponent(String(name))
                try StreetMarking.mark(file, view)
                return [text("Kept as \(name): the landmark is framed in red, \(view.line)")] + (image(file).map { [$0] } ?? [])
            }
            return kept
        }

        /// Downloads a photo into the references with its credit.
        func keep(_ url: String, page: String, author: String, licence: String, shows: String) throws -> [[String: Any]] {
            try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
            var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            let raw = references.appendingPathComponent("download.tmp")
            let (status, said) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"),
                                          ["-fsSL", "--http1.1", "--max-filesize", "30000000", "-A", CommonsPhotos.agent, "-o", raw.path, url])
            guard status == 0 else { throw Failure("cannot download it: \(said)") }
            let head = (try? FileHandle(forReadingFrom: raw).readData(ofLength: 12)) ?? Data()
            let isImage = head.starts(with: [0xFF, 0xD8]) || head.starts(with: [0x89, 0x50, 0x4E, 0x47])
                || (head.count >= 12 && head[8...11] == Data("WEBP".utf8))
            guard isImage else {
                try? FileManager.default.removeItem(at: raw)
                throw Failure("that is not a JPEG, PNG or WebP image: give the direct image URL")
            }
            let file = references.appendingPathComponent(String(format: "photo-%02d.jpg", list.count + 1))
            _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "1280", "-s", "format", "jpeg", raw.path, "--out", file.path])
            try? FileManager.default.removeItem(at: raw)
            guard FileManager.default.fileExists(atPath: file.path) else { throw Failure("cannot read the image") }
            list.append(["file": file.lastPathComponent, "url": url, "page": page, "author": author, "licence": licence, "shows": shows])
            try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
            return [text("Kept as \(file.lastPathComponent)")] + (image(file).map { [$0] } ?? [])
        }

        /// Runs a program, its output and errors together.
        static func run(_ exe: URL, _ args: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return (-1, "\(error)") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
