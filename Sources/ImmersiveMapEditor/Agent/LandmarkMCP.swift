import Foundation
import Geometry
import ImageIO
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
        // The data folder's palette: tiles/z/x/y/landmarks/<id> is six below the root.
        var root = folder.standardizedFileURL
        for _ in 0..<6 { root = root.deletingLastPathComponent() }
        Palette.load(WorkspacePaths(root: root))
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
        /// The data folder, for the caches every landmark shares.
        var root: URL { (0..<6).reduce(folder) { url, _ in url.deletingLastPathComponent() } }
        var cacheFolder: URL { root.appendingPathComponent("cache") }
        /// What the agent searched through: the candidates it was shown.
        var searchFolder: URL { folder.appendingPathComponent("search") }
        /// The rounds of the work: one a set_recipe, each with its recipe,
        /// its model and every picture made of that model. Before the first
        /// recipe, round 00.
        var roundsFolder: URL { folder.appendingPathComponent("rounds") }
        var currentRound: URL {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: roundsFolder.path)) ?? []).filter { Int($0) != nil }.sorted()
            return roundsFolder.appendingPathComponent(names.last ?? "00")
        }
        func nextRound() -> URL {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: roundsFolder.path)) ?? []).compactMap { Int($0) }
            return roundsFolder.appendingPathComponent(String(format: "%02d", (names.max() ?? 0) + 1))
        }

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
            // A screenshot can be large: shrunk to what the agent needs.
            if data.count > 900_000, url.pathExtension.lowercased() == "png" {
                let small = url.deletingPathExtension().appendingPathExtension("small.jpg")
                _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "1400", "-s", "format", "jpeg", url.path, "--out", small.path])
                if let d = try? Data(contentsOf: small) { return ["type": "image", "data": d.base64EncodedString(), "mimeType": "image/jpeg"] }
            }
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
            ["name": "satellite_view",
             "description": "The landmark from above, from the satellite imagery (Esri World Imagery): one picture centred on it, north up, its OSM outlines in red, a grid every 20 m in metres east and north of its centre (the recipe's x and y), kept in the references. The roofs: their shapes, ridges, domes, lanterns, courtyards, and where things stand, to place shapes by the grid.",
             "inputSchema": ["type": "object", "properties": ["radius": ["type": "number", "description": "Metres around the centre; the landmark and 25 m by default."]]]],
            ["name": "compare_with_photo",
             "description": "A kept street photo beside the model rendered from the very place and with the very lens the photo was taken (its camera's pose): the photo left, the model right, one picture. The way to see what differs, facade by facade. Street photos only (Commons photos have no pose).",
             "inputSchema": ["type": "object", "properties": ["file": ["type": "string", "description": "The kept photo, photo-NN.jpg"]], "required": ["file"]]],
            ["name": "compare_with_satellite",
             "description": "The satellite view beside the model rendered from straight above, north up, over the same ground: the masses, roofs and courtyards against the imagery. Needs satellite_view first.",
             "inputSchema": ["type": "object", "properties": [:]]],
            ["name": "render_from",
             "description": "The model as seen from a place of your choice: x and y metres east and north of the landmark's centre, height metres up (2 by default: eye level), heading (a compass bearing: 0 north, 90 east), pitch (degrees, up positive, 0 by default), hfov (degrees wide, 65 by default). For a look from where a Commons photo was taken, or from the square before the entrance.",
             "inputSchema": ["type": "object", "properties": ["x": ["type": "number"], "y": ["type": "number"], "height": ["type": "number"],
                                                              "heading": ["type": "number"], "pitch": ["type": "number"], "hfov": ["type": "number"]],
                             "required": ["x", "y", "heading"]]],
            ["name": "save_reference_photo",
             "description": "Downloads a photo of the landmark into its references and returns it to look at. Only freely licensed photos (Wikimedia Commons: CC BY, CC BY-SA, CC0, public domain) or the user's own: give the direct image URL (upload.wikimedia.org, a thumbnail of about 1280 px is enough), its page, author and licence, and what it shows (which side, from where).",
             "inputSchema": ["type": "object", "properties": [
                "url": ["type": "string"], "page": ["type": "string"], "author": ["type": "string"],
                "licence": ["type": "string"], "shows": ["type": "string"]],
                             "required": ["url", "page", "author", "licence", "shows"]]],
            ["name": "find_street_photos",
             "description": "Street-level photos of the landmark from Mapillary (CC BY-SA 4.0, credited when kept), judged by their camera poses against the landmark's facades (the sides of its outline): a walk around it, facade by facade and station by station along each (from beyond one end, its thirds, from beyond the other end), at each the photos standing there that show the facade best, each from another track (five at most), each with its id, distance, which facades it shows and how much of each, how much of the frame it fills, date and author, and the facades no photo shows. Every station's photos are kept into the references at once, each into the folder of its facade (north-facade/ and so on), framed in red, the rest painted black. Needs the Mapillary token of Settings.",
             "inputSchema": ["type": "object", "properties": [
                "radius": ["type": "number", "description": "Metres around the centre, 150 by default."],
                "limit": ["type": "integer", "description": "How many at most, 100 by default: up to five stations a facade, five photos a station."]]]],
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
            ["name": "show_user_picture",
             "description": "A picture the user attached to a request (a screenshot of the model or of the building, to show what to change), by its file name.",
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
            case "set_recipe":
                let said = try setRecipe(args["recipe"])
                guard said.hasPrefix("Built") else { return [text(said)] }
                // The build, and at once the model beside every kept street
                // photo from that photo's place (the best one of each facade,
                // six at most): what to judge the round by.
                var content: [[String: Any]] = [text(said)]
                var picked: [String] = []
                if let scene = try? StreetScene(folder: folder) {
                    let kept = keptViews(scene)
                    for f in scene.facades.indices.sorted(by: { scene.facades[$0].length > scene.facades[$1].length }) {
                        guard let best = kept.filter({ $0.view.seen[f] >= StreetView.enough && $0.view.looks[f] > 0 })
                            .max(by: { $0.view.looks[f] < $1.view.looks[f] }), !picked.contains(best.file) else { continue }
                        picked.append(best.file)
                    }
                }
                for file in picked.prefix(6) {
                    if let shown = try? compare(["file": file]) { content += shown }
                }
                if picked.isEmpty { content.append(text("No street photo with a camera pose is kept yet: save some with save_street_photo, and every build will come back beside them.")) }
                if let above = try? compareSatellite() { content += above }
                return content
            case "render_views": return try render(args)
            case "save_reference_photo": return try savePhoto(args)
            case "find_street_photos": return try streetPhotos(args)
            case "compare_with_photo": return try compare(args)
            case "compare_with_satellite": return try compareSatellite()
            case "satellite_view": return try satellite(args)
            case "render_from": return try renderFrom(args)
            case "find_commons_photos": return try commonsPhotos(args)
            case "save_commons_photo": return try saveCommonsPhoto(args)
            case "drop_reference": return [text(try dropReference(args["file"] as? String ?? ""))]
            case "save_street_photo": return try saveStreetPhoto(args)
            case "list_references": return [text((String(data: (try? Data(contentsOf: credits)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]") + "\n" + coverage())]
            case "show_user_picture":
                let file = (args["file"] as? String ?? "") as NSString
                let url = folder.appendingPathComponent("requests").appendingPathComponent(file.lastPathComponent)
                guard let shown = image(url) else { throw Failure("no picture \(file) in the requests") }
                return [text("The user's picture \(file.lastPathComponent)"), shown]
            case "show_reference":
                let file = args["file"] as? String ?? ""
                guard let found = reference(file), let shown = image(found.url) else { throw Failure("no reference \(file)") }
                return [shown]
            default: throw Failure("no tool \(name)")
            }
        }

        /// The landmark in short, a line a building: its outlines whole would
        /// pass what a tool may return, so they come by get_outlines.
        func landmark() throws -> String {
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            func f(_ v: Double) -> String { String(format: "%.1f", v) }
            // The building's main axis: the long side of the smallest rectangle
            // around its hull, as a compass bearing.
            var axis = ""
            let all = source.buildings.flatMap { $0.polygons.flatMap { $0.first ?? [] } }
            let rect = Geometry.collection(all.map { Geometry.point($0) }).convexHull.minimumRotatedRectangle.exterior
            if rect.count >= 4 {
                let u = rect[1] - rect[0], v = rect[2] - rect[1]
                let long = simd_length(u) >= simd_length(v) ? u : v
                let bearing = (atan2(long.x, long.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 180)
                axis = String(format: " Its long axis runs at a bearing of %.0f° (so its walls face %.0f°, %.0f°, %.0f° and %.0f°): give boxes, colonnades and pediments these headings and lines, parallel to the walls, never to north when the building is not.",
                              bearing, bearing, (bearing + 90).truncatingRemainder(dividingBy: 360), (bearing + 180).truncatingRemainder(dividingBy: 360), (bearing + 270).truncatingRemainder(dividingBy: 360))
            }
            var lines = ["Landmark: \(source.name), centre lon/lat \(source.centre.0), \(source.centre.1)." + axis,
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
            var guide = LandmarkRecipe.guide
            if ProcessInfo.processInfo.environment["LANDMARK_PHYSICAL_CHECKS"] != "1" {
                guide = guide.replacingOccurrences(of: " set_recipe says what floats or leads nowhere: fix it before going on.", with: "")
            }
            return lines.joined(separator: "\n") + "\n\n" + guide
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
            // The physical checks, when the user has them on.
            let warnings = ProcessInfo.processInfo.environment["LANDMARK_PHYSICAL_CHECKS"] == "1" ? LandmarkGenerator.warnings(recipe, source) : []
            let said = "Built model.glb: \(model.summary)" + (warnings.isEmpty ? "" : "\nNOT PHYSICAL, fix before going on:\n" + warnings.joined(separator: "\n"))
            // A round of the work: this recipe and model, and the pictures made of them after.
            let round = nextRound()
            try FileManager.default.createDirectory(at: round, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: recipeURL, to: round.appendingPathComponent("recipe.json"))
            try? FileManager.default.copyItem(at: folder.appendingPathComponent("model.glb"), to: round.appendingPathComponent("model.glb"))
            try? (said + "\n").write(to: round.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
            return said + " (round \(round.lastPathComponent))"
        }

        func render(_ args: [String: Any]) throws -> [[String: Any]] {
            let all = ["from-south", "from-east", "from-north", "from-west", "from-south-west", "from-north-east", "from-above"]
            let asked = (args["views"] as? [String])?.filter(all.contains) ?? ["from-south-west", "from-north-east", "from-south", "from-above"]
            // No model yet (none built, or a new attempt): its OSM boxes, and say so.
            let hasModel = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(".glb") }
            let boxes = (args["boxes"] as? Bool ?? false) || !hasModel
            let out = currentRound.appendingPathComponent(boxes ? "boxes" : "views")
            var command = ["--landmark-views", folder.path, out.path]
            if boxes { command.append("--boxes") }
            let (status, said) = Self.run(URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL, command)
            guard status == 0 else { throw Failure("cannot render: \(said)") }
            var content: [[String: Any]] = []
            if boxes, !(args["boxes"] as? Bool ?? false) { content.append(text("No model yet: these are the OSM boxes. set_recipe builds the model.")) }
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
            let dir = cacheFolder.appendingPathComponent("mapillary")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(CoverageTile.zoom)_\(x)_\(y).mvt")
            if let age = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
               Date().timeIntervalSince(age) < 86_400 || offline, let data = try? Data(contentsOf: file), !data.isEmpty { return data }
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
            let limit = max(1, min(200, (args["limit"] as? NSNumber)?.intValue ?? 100))
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
                if simd_length(at) <= radius { entries.append(e) }
            }
            let tracks = frames.mapValues { StreetTrack($0) }
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
            let total = points.filter { simd_length(scene.metres(lon: $0.lon, lat: $0.lat)) <= radius }.count
            // Facade by facade, so a facade seen only in passing keeps its
            // candidates: the best thousand looks at each judged with
            // what hides them, then the best twenty-five at every station of each
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
            // The best twenty-five at every station of every facade asked for in
            // full, so each station keeps candidates from several tracks.
            var askedIds = Set<String>()
            var asked: [String] = []
            for f in scene.facades.indices {
                for k in 0..<StreetScene.stations {
                    for (_, e) in judged.filter({ $0.0.seen[f] >= StreetView.enough && scene.station(f, of: $0.0.photo.at) == k })
                        .sorted(by: { $0.0.looks[f] * $0.0.seen[f] > $1.0.looks[f] * $1.0.seen[f] }).prefix(25)
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
                    let json = try mapillary("", ["ids": chunk.joined(separator: ","), "fields": StreetPhoto.fields])
                    if let error = json["error"] as? [String: Any] { throw Failure("Mapillary refused the photos' details: \(error["message"] ?? error)") }
                    for (id, e) in json where chunk.contains(id) { if let e = e as? [String: Any] { photos[id] = e } }
                }
                // A photo a chunk's answer leaves out is asked for alone.
                for id in asked where photos[id] == nil {
                    if let e = try? mapillary(id, ["fields": StreetPhoto.fields]), e["error"] == nil, e["id"] != nil { photos[id] = e }
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
                return [text("Of \(photosCount) street photos within \(Int(radius)) m none shows the landmark well. Try a larger radius.")]
            }
            let (report, picks, stations) = StreetPicks.report(views, in: scene, limit: limit)
            guard !picks.isEmpty else { return [text("Of \(photosCount) street photos within \(Int(radius)) m none gives a good look at the landmark.")] }
            // The contact sheet: a small thumbnail of each pick, framed.
            let dir = searchFolder.appendingPathComponent("street")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Each pick at a size its eyes can read, framed; the sheet of them
            // all for the user's panel.
            let thumbs: [URL?] = picks.map { pick in
                let file = dir.appendingPathComponent("\(pick.photo.id).jpg")
                if FileManager.default.fileExists(atPath: file.path) { return file }
                guard !offline, let json = try? mapillary(pick.photo.id, ["fields": pick.photo.pano ? "thumb_2048_url" : "thumb_1024_url"]),
                      let url = (json["thumb_2048_url"] ?? json["thumb_1024_url"]) as? String else { return nil }
                let (status, _) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"), ["-fsSL", "--max-time", "30", "-o", file.path, url])
                return status == 0 ? file : nil
            }
            let sheet = dir.appendingPathComponent("sheet.jpg")
            try StreetPicks.sheet(picks, in: scene, thumbs: thumbs, to: sheet)
            // Every station's photos are kept at once, each into the folder
            // of the facade it was taken for, so every side a photo stands at
            // gets its references whatever the agent makes of the list; the
            // agent drops one whose frame is wrong. Only the first of each
            // station comes back as a picture, the others by name.
            var keptNow: [String: [[String: Any]]] = [:]
            var shown = Set<String>()
            var stationsSeen = Set<String>()
            let already = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? [])
                .compactMap { $0["page"] as? String }
            for (f, k, view) in stations where keptNow[view.photo.id] == nil && !already.contains("https://www.mapillary.com/app/?pKey=\(view.photo.id)") && !offline {
                if let kept = try? keepStreet(view, shows: "\(scene.facades[f].name) \(scene.stationName(f, k)): \(view.shows(scene)), kept by find_street_photos",
                                              into: Self.facadeFolder(scene.facades[f].name)) {
                    keptNow[view.photo.id] = kept
                    if stationsSeen.insert("\(f) \(k)").inserted { shown.insert(view.photo.id) }
                }
            }
            var content: [[String: Any]] = [text(
                "\(photosCount) street photos within \(Int(radius)) m; only those borne out by their tracks count (the place smooth with the neighbouring frames, the track clear of buildings, a dashcam's heading the way it went, the facade seen from two neighbouring frames too). Of the \(asked.count) best of them asked for in full, \(photos.count) came back and \(views.count) are borne out again by Mapillary's computed pose. A walk around it, facade by facade (the sides of its outline, the longest first) and station by station along each (from beyond one end, its thirds, from beyond the other end), at each the photos standing there that show the facade best, each from another track:\n"
                + report
                + "\nEvery station's photos are kept already, each in the folder of its facade (north-facade/, ...), framed in red, the rest painted black. The first of each station follows as a picture, the others by name: show_reference(name) to look at one. Mapillary's camera pose is sometimes wrong: if a frame holds another building, drop_reference it. Licence CC BY-SA 4.0, credited to Mapillary and its author.")]
            for (k, pick) in picks.enumerated() {
                if let kept = keptNow[pick.photo.id] {
                    content.append(text("#\(k + 1) " + (kept.first?["text"] as? String ?? "")))
                    if shown.contains(pick.photo.id) { content += kept.dropFirst() }
                    continue
                }
                let framed = dir.appendingPathComponent("\(pick.photo.id).framed.jpg")
                try ContactSheet.one(ContactSheet.Cell(image: thumbs[k], box: pick.box, cut: pick.photo.pano, label: ""), maxSide: 720, to: framed)
                content.append(text("#\(k + 1) " + pick.line(scene)))
                if let img = image(framed) { content.append(img) }
            }
            return content
        }

        /// Without Mapillary (`LANDMARK_STREET_OFFLINE`): the coverage tiles
        /// of the cache however old, the photos as the tiles describe them,
        /// no thumbnails fetched. For checking the choice without the token.
        var offline: Bool { ProcessInfo.processInfo.environment["LANDMARK_STREET_OFFLINE"] != nil }

        /// The kept street photos as looks at the landmark, from their poses.
        func keptViews(_ scene: StreetScene) -> [(file: String, view: StreetView)] {
            let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            return list.compactMap { e in
                guard let file = e["file"] as? String, let pose = e["pose"] as? [String: Any],
                      let x = pose["x"] as? Double, let y = pose["y"] as? Double,
                      let heading = pose["heading"] as? Double, let hfov = pose["hfov"] as? Double else { return nil }
                let width = pose["width"] as? Int ?? 1280, height = pose["height"] as? Int ?? 720
                return scene.view(x: x, y: y, heading: heading, hfov: hfov, width: width, height: height).map { (file, $0) }
            }
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
            let dir = searchFolder.appendingPathComponent("commons")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let cells = picks.enumerated().map { k, p -> ContactSheet.Cell in
                let file = dir.appendingPathComponent("\(k + 1).jpg")
                var image: URL? = nil
                if let thumb = p.thumb {
                    let (status, _) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"), ["-fsSL", "--http1.1", "--max-time", "60", "-A", CommonsPhotos.agent, "-o", file.path, thumb])
                    _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "640", "-s", "format", "jpeg", file.path, "--out", file.path])
                    if status == 0 { image = file }
                }
                return ContactSheet.Cell(image: image, box: nil, cut: false, label: "#\(k + 1)  \(String(p.title.dropFirst("File:".count).prefix(40)))")
            }
            let sheet = dir.appendingPathComponent("sheet.jpg")
            try ContactSheet.draw(cells, to: sheet)
            var content: [[String: Any]] = [text("Commons: \(photos.count) freely licensed photos in \(where_)within \(Int(radius)) m; the \(picks.count) best follow, numbered. Keep one with save_commons_photo(file, shows).")]
            for (k, p) in picks.enumerated() {
                content.append(text("#\(k + 1) " + p.line))
                if let file = cells[k].image, let img = image(file) { content.append(img) }
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

        /// What the references cover so far: the street photos by the
        /// facades their cameras see, the Commons photos and the satellite
        /// apart, and the facades with nothing yet. Told after every keep,
        /// so the agent sees the gaps.
        func coverage() -> String {
            let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
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
            var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            list.removeAll { $0["file"] as? String == relative }
            try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
            return "Dropped \(relative)"
        }

        func saveStreetPhoto(_ args: [String: Any]) throws -> [[String: Any]] {
            guard let id = args["id"] as? String, !id.isEmpty, id.allSatisfy(\.isNumber) else { throw Failure("give the photo's id from find_street_photos") }
            guard let shows = args["shows"] as? String, !shows.isEmpty else { throw Failure("say what it shows") }
            guard let view = confirmed[id] else {
                throw Failure("\(id) is not one find_street_photos bore out by its track in this session: only those are kept")
            }
            let scene = try StreetScene(folder: folder)
            return try keepStreet(view, shows: shows, into: Self.facadeFolder(scene.facades[view.best].name))
        }

        /// The folder of a facade's street photos: "the south facade, east
        /// end" is south-facade-east-end.
        static func facadeFolder(_ name: String) -> String {
            let words = name.replacingOccurrences(of: "the ", with: "").replacingOccurrences(of: ",", with: "")
            return words.split(separator: " ").joined(separator: "-")
        }

        /// The street photos find_street_photos bore out by their tracks in
        /// this session, by id, with the pose they were judged by.
        var confirmed: [String: StreetView] = [:]

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

        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

        static func size(of file: URL) -> (Int, Int)? {
            guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
                  let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
            return (w, h)
        }

        /// Adds a field to a kept photo's credit.
        func credit(_ file: String, set key: String, to value: Any) throws {
            var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            guard let k = list.firstIndex(where: { $0["file"] as? String == file }) else { return }
            list[k][key] = value
            try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
        }

        // MARK: From above

        func satellite(_ args: [String: Any]) throws -> [[String: Any]] {
            let scene = try StreetScene(folder: folder)
            let reach = scene.corners.map { max(abs($0.x), abs($0.y)) }.max() ?? 60
            let radius = max(40, min(400, (args["radius"] as? NSNumber)?.doubleValue ?? (reach + 25)))
            try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
            let file = references.appendingPathComponent("satellite.jpg")
            let (mpp, missing, roofs) = try SatelliteView.make(folder: folder, radius: radius, to: file,
                                                               cache: cacheFolder.appendingPathComponent("imagery"), run: Self.run)
            let taken = SatelliteView.capture(folder: folder, run: Self.run)
            var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            list.removeAll { $0["file"] as? String == "satellite.jpg" }
            list.append(["file": "satellite.jpg", "radius": radius, "url": "https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9",
                         "page": "https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9",
                         "author": SatelliteView.source.attribution, "licence": "Esri World Imagery terms, a reference",
                         "shows": "from above, north up, " + (taken.map { "taken \($0), " } ?? "") + "\(Int(radius)) m around the centre"])
            try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: credits)
            let small = searchFolder.appendingPathComponent("satellite/view.jpg")
            try FileManager.default.createDirectory(at: small.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "1280", "-s", "format", "jpeg", file.path, "--out", small.path])
            var content: [[String: Any]] = [text("satellite.jpg: the landmark from above, north up, \(Int(radius)) m around its centre, \(String(format: "%.2f", mpp)) m a pixel"
                + (taken.map { ", imagery taken \($0)" } ?? "") + (missing > 0 ? " (\(missing) tiles did not come)" : "")
                + ". Red: its OSM outlines. The grid: every 20 m, metres east (x) and north (y) of the centre, the recipe's coordinates."
                + (roofs.isEmpty ? "" : "\nThe roofs' colours, read off the imagery inside each large part's outline (the roof leans a little off its outline in the picture, so trust the large parts): use these in the recipe.\n" + roofs.joined(separator: "\n")))]
            if let img = image(FileManager.default.fileExists(atPath: small.path) ? small : file) { content.append(img) }
            return content
        }

        // MARK: The model from a camera's place

        /// The model as a camera at `eye` (metres east, north, up of the
        /// centre) sees it, to a PNG.
        func look(eye: (Double, Double, Double), heading: Double, pitch: Double, hfov: Double, width: Int, height: Int, to out: URL) throws {
            let args = ["--landmark-look", folder.path, out.path] + [eye.0, eye.1, eye.2, heading, pitch, hfov, Double(width), Double(height)].map { "\($0)" }
            let (status, said) = Self.run(URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL, args)
            guard status == 0 else { throw Failure("cannot render: \(said)") }
        }

        /// A kept street photo beside the model from its camera's place.
        func compare(_ args: [String: Any]) throws -> [[String: Any]] {
            let given = args["file"] as? String ?? ""
            guard let (photo, name) = reference(given) else { throw Failure("no reference \(given)") }
            let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            guard let entry = list.first(where: { $0["file"] as? String == name }) else { throw Failure("no reference \(name)") }
            guard let pose = entry["pose"] as? [String: Any], let x = pose["x"] as? Double, let y = pose["y"] as? Double,
                  let heading = pose["heading"] as? Double, let hfov = pose["hfov"] as? Double else {
                throw Failure("\(name) has no camera pose (only street photos have one): render_from a place of your choice instead")
            }
            let size = Self.size(of: photo) ?? (1024, 768)
            let scale = min(1, 1024.0 / Double(size.0))
            let w = Int(Double(size.0) * scale), h = Int(Double(size.1) * scale)
            let dir = currentRound.appendingPathComponent("compare")
            let render = dir.appendingPathComponent(((name as NSString).lastPathComponent as NSString).deletingPathExtension + ".render.png")
            try look(eye: (x, y, pose["z"] as? Double ?? 2), heading: heading, pitch: pose["pitch"] as? Double ?? 0, hfov: hfov,
                     width: w, height: h, to: render)
            let both = dir.appendingPathComponent(((name as NSString).lastPathComponent as NSString).deletingPathExtension + ".compare.jpg")
            try SideBySide.draw(photo, render, to: both)
            var content: [[String: Any]] = [text("\(name) and the model from its camera's place (\(Int(x)) m east, \(Int(y)) m north of the centre, looking \(Int(heading))°, \(Int(hfov))° wide): the photo on the left, the model on the right. Mapillary's pose can be some metres and degrees off, and a panorama's cut is not a perspective picture, so judge the shapes and the counts (columns, windows, storeys), not the exact overlap or size.")]
            if let img = image(both) { content.append(img) }
            return content
        }

        /// The satellite view beside the model from straight above, north
        /// up, over the same ground: the masses and the roofs against the
        /// imagery (and the OSM outlines drawn on it).
        func compareSatellite() throws -> [[String: Any]] {
            let photo = references.appendingPathComponent("satellite.jpg")
            let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            guard FileManager.default.fileExists(atPath: photo.path), let entry = list.first(where: { $0["file"] as? String == "satellite.jpg" }) else {
                throw Failure("no satellite view kept yet: satellite_view first")
            }
            let radius = entry["radius"] as? Double ?? 110
            // From 600 m up, as narrow as it takes to cover the same ground;
            // not quite straight down, so the camera keeps its north.
            let size = 1024
            let render = currentRound.appendingPathComponent("compare/satellite.render.png")
            try look(eye: (0, 0, 600), heading: 0, pitch: -89.9, hfov: 2 * atan(radius / 600) * 180 / .pi, width: size, height: size, to: render)
            let both = currentRound.appendingPathComponent("compare/satellite.compare.jpg")
            try SideBySide.draw(photo, render, to: both, labels: ("satellite, north up, the OSM outlines in red", "model from above, north up, the same ground"))
            var content: [[String: Any]] = [text("The satellite view (\(Int(radius)) m around the centre) beside the model from straight above, north up, over the same ground: the masses, the roofs' shapes and ridges, the courtyards. The imagery leans a little (a tall roof sits a few metres off its outline), so judge the shapes, not the exact overlap.")]
            if let img = image(both) { content.append(img) }
            return content
        }

        func renderFrom(_ args: [String: Any]) throws -> [[String: Any]] {
            func num(_ k: String, _ d: Double) -> Double { (args[k] as? NSNumber)?.doubleValue ?? d }
            guard args["x"] != nil, args["y"] != nil, args["heading"] != nil else { throw Failure("give x, y (metres east and north of the centre) and heading (a compass bearing)") }
            let dir = currentRound.appendingPathComponent("look")
            let n = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") }.count + 1
            let out = dir.appendingPathComponent("look-\(n).png")
            try look(eye: (num("x", 0), num("y", 0), num("height", 2)), heading: num("heading", 0), pitch: num("pitch", 0),
                     hfov: max(20, min(120, num("hfov", 65))), width: 1024, height: 768, to: out)
            let small = dir.appendingPathComponent("look-\(n).small.jpg")
            _ = Self.run(URL(fileURLWithPath: "/usr/bin/sips"), ["-Z", "900", "-s", "format", "jpeg", out.path, "--out", small.path])
            return [text("The model from \(Int(num("x", 0))) m east, \(Int(num("y", 0))) m north, \(num("height", 2)) m up, looking \(Int(num("heading", 0)))°")]
                + (image(FileManager.default.fileExists(atPath: small.path) ? small : out).map { [$0] } ?? [])
        }

        /// Downloads a photo into the references (into `sub`, a folder of
        /// them, when given) with its credit, its file in the credits by its
        /// path within the references.
        func keep(_ url: String, page: String, author: String, licence: String, shows: String, maxSide: Int = 1280,
                  into sub: String? = nil) throws -> [[String: Any]] {
            let dir = sub.map { references.appendingPathComponent($0) } ?? references
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
                let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
                guard let found = list.compactMap({ $0["file"] as? String }).first(where: { ($0 as NSString).lastPathComponent == (path as NSString).lastPathComponent }) else { return nil }
                path = found
            }
            let url = references.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: url.path) ? (url, path) : nil
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
