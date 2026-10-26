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
             "description": "Street-level photos of the landmark from Mapillary (CC BY-SA 4.0, credited when kept): the ones within `radius` metres of its centre that look at it, nearest first, each with its id, where it stands (metres and the side), which way it looks, its date and author. Keep one with save_street_photo. Needs the Mapillary token of Settings.",
             "inputSchema": ["type": "object", "properties": [
                "radius": ["type": "number", "description": "Metres around the centre, 150 by default."],
                "limit": ["type": "integer", "description": "How many, 15 by default."]]]],
            ["name": "save_street_photo",
             "description": "Downloads one of find_street_photos' pictures by its id into the references, credited (Mapillary, its author, CC BY-SA 4.0), and returns it to look at.",
             "inputSchema": ["type": "object", "properties": ["id": ["type": "string"], "shows": ["type": "string", "description": "What it shows: which side, from where."]],
                             "required": ["id", "shows"]]],
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
            case "find_street_photos": return [text(try streetPhotos(args))]
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
            // Without -f: Mapillary explains an error in its JSON body.
            let (status, said) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"), ["-sSL", "--max-time", "60", c.url!.absoluteString])
            guard status == 0 else { throw Failure("Mapillary did not answer: \(said.prefix(300))") }
            guard let json = try? JSONSerialization.jsonObject(with: Data(said.utf8)) as? [String: Any] else {
                throw Failure("Mapillary answered with something else: \(said.prefix(300))")
            }
            return json
        }

        /// The photos around the landmark's centre that look at it.
        func streetPhotos(_ args: [String: Any]) throws -> String {
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            let (lon, lat) = source.centre
            let radius = max(30, min(400, (args["radius"] as? NSNumber)?.doubleValue ?? 150))
            let limit = max(1, min(40, (args["limit"] as? NSNumber)?.intValue ?? 15))
            let kx = cos(lat * .pi / 180) * 111_320.0, ky = 110_574.0
            // Mapillary refuses a box with too many photos in it (central
            // Moscow: anything over about 80 m around), so the area is asked
            // for in cells of 150 m, the answers merged by id.
            let cell = 75.0, n = Int((radius / cell).rounded(.up))
            var photos: [String: [String: Any]] = [:]
            for i in 0..<n {
                for j in 0..<n {
                    let cx = lon + (Double(i) * 2 + 1 - Double(n)) * cell / kx, cy = lat + (Double(j) * 2 + 1 - Double(n)) * cell / ky
                    let bbox = [cx - cell / kx, cy - cell / ky, cx + cell / kx, cy + cell / ky].map { String(format: "%.6f", $0) }
                    let json = try mapillary("images", ["fields": "id,computed_geometry,computed_compass_angle,captured_at,creator,is_pano",
                                                        "bbox": bbox.joined(separator: ","), "limit": "100"])
                    if let error = json["error"] as? [String: Any] { throw Failure("Mapillary: \(error["message"] ?? error)") }
                    for e in json["data"] as? [[String: Any]] ?? [] { if let id = e["id"] as? String { photos[id] = e } }
                }
            }
            var found: [(Double, String)] = []
            let sides = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
            for e in photos.values {
                guard let id = e["id"] as? String,
                      let c = (e["computed_geometry"] as? [String: Any])?["coordinates"] as? [Double], c.count == 2 else { continue }
                let dx = (c[0] - lon) * kx, dy = (c[1] - lat) * ky, dist = hypot(dx, dy)
                guard dist <= radius, dist > 8 else { continue }
                // Where the camera stands from the centre, and whether it looks back at it.
                let from = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                let toCentre = (from + 180).truncatingRemainder(dividingBy: 360)
                let pano = e["is_pano"] as? Bool ?? false
                let looks = (e["computed_compass_angle"] as? NSNumber)?.doubleValue
                var away = 0.0
                if let looks, !pano {
                    away = abs((looks - toCentre + 540).truncatingRemainder(dividingBy: 360) - 180)
                    guard away <= 55 else { continue }
                }
                let side = sides[Int((from + 22.5) / 45) % 8]
                var date = "?"
                if let ms = (e["captured_at"] as? NSNumber)?.doubleValue {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM"
                    date = f.string(from: Date(timeIntervalSince1970: ms / 1000))
                }
                let author = (e["creator"] as? [String: Any])?["username"] as? String ?? "?"
                let line = "\(id): \(Int(dist)) m to the \(side) of the centre, "
                    + (pano ? "a panorama" : "looking \(sides[Int((toCentre + 22.5) / 45) % 8]) at it (\(Int(away))° off)")
                    + ", \(date), by \(author)"
                found.append((dist + away * 0.5, line))
            }
            guard !found.isEmpty else { return "No street photos within \(Int(radius)) m look at it. Try a larger radius." }
            let lines = found.sorted { $0.0 < $1.0 }.prefix(limit).map(\.1)
            return "\(found.count) photos look at it; the \(lines.count) best:\n" + lines.joined(separator: "\n")
                + "\nKeep one with save_street_photo(id, shows). Licence CC BY-SA 4.0, credited to Mapillary and its author."
        }

        func saveStreetPhoto(_ args: [String: Any]) throws -> [[String: Any]] {
            guard let id = args["id"] as? String, !id.isEmpty, id.allSatisfy(\.isNumber) else { throw Failure("give the photo's id from find_street_photos") }
            guard let shows = args["shows"] as? String, !shows.isEmpty else { throw Failure("say what it shows") }
            let json = try mapillary(id, ["fields": "thumb_1024_url,creator"])
            guard let url = json["thumb_1024_url"] as? String else { throw Failure("Mapillary has no picture for \(id)") }
            let author = (json["creator"] as? [String: Any])?["username"] as? String ?? "unknown"
            return try keep(url, page: "https://www.mapillary.com/app/?pKey=\(id)", author: "\(author) (Mapillary)",
                            licence: "CC BY-SA 4.0", shows: shows)
        }

        /// Downloads a photo into the references with its credit.
        func keep(_ url: String, page: String, author: String, licence: String, shows: String) throws -> [[String: Any]] {
            try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
            var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: credits))) as? [[String: Any]] ?? []
            let raw = references.appendingPathComponent("download.tmp")
            let (status, said) = Self.run(URL(fileURLWithPath: "/usr/bin/curl"),
                                          ["-fsSL", "--max-filesize", "30000000", "-A", "ImmersiveMapEditor/1 (landmark references)", "-o", raw.path, url])
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
