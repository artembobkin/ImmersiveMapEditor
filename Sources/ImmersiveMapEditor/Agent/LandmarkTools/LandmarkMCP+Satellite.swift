import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The landmark from above (satellite_view): Esri's imagery with the OSM
/// outlines and a grid in metres, kept in the references.
extension LandmarkMCP.Server {
    func satellite(_ args: [String: Any]) throws -> [[String: Any]] {
        let scene = try StreetScene(folder: folder)
        let reach = scene.corners.map { max(abs($0.x), abs($0.y)) }.max() ?? 60
        let radius = max(40, min(400, (args["radius"] as? NSNumber)?.doubleValue ?? (reach + 25)))
        try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
        let file = references.appendingPathComponent("satellite.jpg")
        let (mpp, missing, roofs) = try SatelliteView.make(folder: folder, radius: radius, to: file,
                                                           cache: cacheFolder.appendingPathComponent("imagery"), run: Self.run)
        let taken = SatelliteView.capture(folder: folder, run: Self.run)
        var list = credited()
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
}
