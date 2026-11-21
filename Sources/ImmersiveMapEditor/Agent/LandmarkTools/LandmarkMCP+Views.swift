import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The model looked at: rendered from around, from a place of the
/// agent's choice, from a kept street photo's own camera beside the photo,
/// and from straight above beside the satellite view.
extension LandmarkMCP.Server {
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
        let list = credited()
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
        let list = credited()
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
}
