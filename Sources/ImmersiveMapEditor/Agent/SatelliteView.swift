import CoreGraphics
import CoreText
import Geometry
import Foundation
import ImageIO
import TileKit

/// The landmark from above, out of the satellite imagery the Roads view
/// shows (Esri World Imagery, under its terms, credited): one picture
/// centred on the landmark, north up, its OSM outlines drawn in red and a
/// grid in metres east and north of its centre, so the agent reads the
/// roofs and places shapes by the grid. The tiles come from the editor's
/// ImagerySource with the key of Settings.
enum SatelliteView {
    static let zoom = 19
    static let source = ImagerySource.esri

    /// Makes the picture for the landmark in `folder`, `radius` metres
    /// around its centre, to `file`. Returns metres a pixel and the tiles
    /// that did not come.
    static func make(folder: URL, radius: Double, to file: URL, cache: URL,
                     run: (URL, [String]) -> (Int32, String)) throws -> (metresPerPixel: Double, missing: Int) {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        let (lon, lat) = source.centre
        let n = Double(1 << zoom) * 256
        let r = lat * .pi / 180
        // The centre in the world's pixels at this zoom, and the scale there.
        let cx = (lon + 180) / 360 * n, cy = (1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n
        let mpp = 156_543.03392 * cos(r) / Double(1 << zoom)
        let half = radius / mpp
        let x0 = Int((cx - half) / 256), x1 = Int((cx + half) / 256), y0 = Int((cy - half) / 256), y1 = Int((cy + half) / 256)
        let w = Int(half * 2), h = w
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw NSError(domain: "SatelliteView", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot draw"])
        }
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var missing = 0
        for tx in x0...x1 {
            for ty in y0...y1 {
                let tile = cache.appendingPathComponent("\(zoom)_\(tx)_\(ty).jpg")
                if !FileManager.default.fileExists(atPath: tile.path), let url = Self.source.url(z: zoom, x: tx, y: ty) {
                    let (status, _) = run(URL(fileURLWithPath: "/usr/bin/curl"), ["-fsSL", "--http1.1", "--max-time", "60", "-o", tile.path, url.absoluteString])
                    if status != 0 { try? FileManager.default.removeItem(at: tile) }
                }
                guard let src = CGImageSourceCreateWithURL(tile as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    missing += 1
                    continue
                }
                // The tile's place in the picture: pixels from the top left,
                // CoreGraphics' y from the bottom.
                let px = Double(tx) * 256 - (cx - half), py = Double(ty) * 256 - (cy - half)
                ctx.draw(image, in: CGRect(x: px, y: Double(h) - py - 256, width: 256, height: 256))
            }
        }
        // A point in metres east and north of the centre, in the context.
        func at(_ p: P2) -> CGPoint { CGPoint(x: half + p.x / mpp, y: half + p.y / mpp) }
        // The grid: a line every 20 m, labelled every 40.
        let step = 20.0, reach = Double(Int(radius / step)) * step
        ctx.setLineWidth(1)
        for v in stride(from: -reach, through: reach, by: step) {
            let strong = Int(v) % 40 == 0
            ctx.setStrokeColor(CGColor(gray: 1, alpha: v == 0 ? 0.8 : strong ? 0.45 : 0.25))
            ctx.move(to: at(P2(v, -radius))); ctx.addLine(to: at(P2(v, radius))); ctx.strokePath()
            ctx.move(to: at(P2(-radius, v))); ctx.addLine(to: at(P2(radius, v))); ctx.strokePath()
            if strong {
                label("\(Int(v))", at: CGPoint(x: at(P2(v, 0)).x + 3, y: 4), ctx)
                label("\(Int(v))", at: CGPoint(x: 4, y: at(P2(0, v)).y + 3), ctx)
            }
        }
        // The landmark's outlines.
        ctx.setStrokeColor(CGColor(red: 1, green: 0.15, blue: 0.15, alpha: 0.95))
        ctx.setLineWidth(2)
        for b in source.buildings {
            for poly in b.polygons {
                for ring in poly where ring.count >= 3 {
                    ctx.move(to: at(ring[0]))
                    for p in ring.dropFirst() { ctx.addLine(to: at(p)) }
                    ctx.closePath()
                    ctx.strokePath()
                }
            }
        }
        label("N up · x east, y north, metres from the centre · \(String(format: "%.2f", mpp)) m a pixel", at: CGPoint(x: 6, y: Double(h) - 18), ctx)
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "SatelliteView", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write"])
        }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return (mpp, missing)
    }

    static func label(_ text: String, at p: CGPoint, _ ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil), .foregroundColor: CGColor(red: 1, green: 1, blue: 0.6, alpha: 1)]))
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }

    /// When the imagery at the landmark was taken, by Esri's metadata.
    static func capture(folder: URL, run: (URL, [String]) -> (Int32, String)) -> String? {
        guard let source = try? LandmarkSource(folder.appendingPathComponent("landmark.json")) else { return nil }
        let (lon, lat) = (String(format: "%.6f", source.centre.0), String(format: "%.6f", source.centre.1))
        let around = String(format: "%.5f,%.5f,%.5f,%.5f", source.centre.0 - 0.01, source.centre.1 - 0.01, source.centre.0 + 0.01, source.centre.1 + 0.01)
        let url = "https://services.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/identify"
            + "?geometry=\(lon),\(lat)&geometryType=esriGeometryPoint&sr=4326&layers=all&tolerance=1"
            + "&mapExtent=\(around)&imageDisplay=800,600,96&returnGeometry=false&f=json"
        let (status, said) = run(URL(fileURLWithPath: "/usr/bin/curl"), ["-fsSL", "--http1.1", "--max-time", "30", url])
        guard status == 0, let json = try? JSONSerialization.jsonObject(with: Data(said.utf8)) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        for r in results {
            guard let a = r["attributes"] as? [String: Any], let date = a["SRC_DATE"] as? String, date.count == 8 else { continue }
            let day = "\(date.prefix(4))-\(date.dropFirst(4).prefix(2))-\(date.suffix(2))"
            return ([day] + [a["SRC_RES"].map { "\($0) m" }, a["NICE_DESC"] as? String].compactMap { $0 }).joined(separator: ", ")
        }
        return nil
    }
}
