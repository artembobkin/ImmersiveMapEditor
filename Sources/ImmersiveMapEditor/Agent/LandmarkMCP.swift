import Foundation
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
             "description": "The landmark: its name, centre, and every OSM building and building:part it is made of (osm id, part or not, all tags, base and height in metres, outline rings in metres east and north of the centre). Then the recipe format and the palette's colours. Read it first.",
             "inputSchema": ["type": "object", "properties": [:]]],
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
            case "get_recipe": return [text(try recipeText())]
            case "set_recipe": return [text(try setRecipe(args["recipe"]))]
            case "render_views": return try render(args)
            case "save_reference_photo": return try savePhoto(args)
            case "list_references": return [text(String(data: (try? Data(contentsOf: credits)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]")]
            case "show_reference":
                let file = (args["file"] as? String ?? "") as NSString
                guard let shown = image(references.appendingPathComponent(file.lastPathComponent)) else { throw Failure("no reference \(file)") }
                return [shown]
            default: throw Failure("no tool \(name)")
            }
        }

        func landmark() throws -> String {
            let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
            func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
            let buildings: [[String: Any]] = source.buildings.map { b in
                var e: [String: Any] = ["osm": b.osm, "part": b.part, "tags": b.tags, "base": r(b.base),
                                        "outline": b.polygons.map { $0.map { $0.map { [r($0.x), r($0.y)] } } }]
                if let h = b.height { e["height"] = r(h) }
                return e
            }
            let json: [String: Any] = ["name": source.name, "centre_lon_lat": [source.centre.0, source.centre.1], "buildings": buildings]
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)! + "\n\n" + LandmarkRecipe.guide
        }

        var recipeURL: URL { folder.appendingPathComponent("recipe.json") }
        var credits: URL { references.appendingPathComponent("credits.json") }

        func recipeText() throws -> String {
            if let data = try? Data(contentsOf: recipeURL) { return String(data: data, encoding: .utf8) ?? "" }
            let starter = try LandmarkSource(folder.appendingPathComponent("landmark.json")).starterRecipe()
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return "(no recipe yet: a starter from OSM's tags)\n" + String(data: try e.encode(starter), encoding: .utf8)!
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
            list.append(["file": file.lastPathComponent, "url": url, "page": args["page"]!, "author": args["author"]!,
                         "licence": args["licence"]!, "shows": args["shows"]!])
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
