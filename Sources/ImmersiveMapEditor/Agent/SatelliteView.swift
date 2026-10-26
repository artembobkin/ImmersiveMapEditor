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
                     run: (URL, [String]) -> (Int32, String)) throws -> (metresPerPixel: Double, missing: Int, roofs: [String]) {
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
        let roofs = roofColours(ctx, source: source, at: at)
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
        return (mpp, missing, roofs)
    }

    /// The colour of each large part's roof, read off the imagery inside
    /// its outline (a metre grid of samples, the darkest third left out as
    /// shadow), and the palette's landmark colour nearest to it: what the
    /// recipe's roof colours should be. The largest parts first, ten at most.
    static func roofColours(_ ctx: CGContext, source: LandmarkSource, at: (P2) -> CGPoint) -> [String] {
        guard let data = ctx.data else { return [] }
        let p = data.assumingMemoryBound(to: UInt8.self), stride = ctx.bytesPerRow, w = ctx.width, h = ctx.height
        let parts = source.buildings.filter { $0.part }
        let candidates = (parts.isEmpty ? source.buildings : parts)
            .map { b in (b, b.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) }) }
            .filter { $0.1 >= 60 }.sorted { $0.1 > $1.1 }.prefix(10)
        var out: [String] = []
        for (b, area) in candidates {
            var samples: [(Double, Double, Double)] = []
            for poly in b.polygons {
                let ring = poly[0]
                guard ring.count >= 3 else { continue }
                let xs = ring.map(\.x), ys = ring.map(\.y)
                var y = ys.min()!
                while y <= ys.max()! {
                    var x = xs.min()!
                    while x <= xs.max()! {
                        let q = P2(x, y)
                        if inside(q, ring) {
                            let c = at(q)
                            // The context's rows go up; the bitmap's go down from the top.
                            let px = Int(c.x), py = h - 1 - Int(c.y)
                            if px >= 0, px < w, py >= 0, py < h {
                                let k = py * stride + px * 4
                                samples.append((Double(p[k]), Double(p[k + 1]), Double(p[k + 2])))
                            }
                        }
                        x += 1
                    }
                    y += 1
                }
            }
            guard samples.count >= 20 else { continue }
            // The darkest third is shadow and the brightest tenth glare.
            let sorted = samples.sorted { $0.0 + $0.1 + $0.2 < $1.0 + $1.1 + $1.2 }
            let kept = sorted[(sorted.count / 3)..<(sorted.count - sorted.count / 10)]
            let n = Double(kept.count)
            let mean = kept.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0 / n, $0.1 + $1.1 / n, $0.2 + $1.2 / n) }
            let (r, g, bl) = (Int(mean.0), Int(mean.1), Int(mean.2))
            // The imagery's brightness is not to be trusted (a light roof
            // burns out white), its hue is: the colour by hue, the greys to
            // the palette's grey.
            let mx = max(r, g, bl), mn = min(r, g, bl)
            let hue: String, colour: String
            if mx - mn < 26 {
                (hue, colour) = mx > 100 ? ("grey", "lm_stone") : ("dark grey, near black", "lm_dark")
            } else if g >= r && g >= bl {
                (hue, colour) = mx > 120 ? ("greenish", "lm_green") : ("dark green", "lm_dark_green")
            } else if r > g && r > bl {
                (hue, colour) = g > bl + 15 ? ("brownish or ochre", "lm_ochre") : ("reddish", "lm_red")
            } else {
                (hue, colour) = ("bluish grey", "lm_stone")
            }
            out.append(String(format: "%@ (%.0f m²): the roof reads rgb(%d, %d, %d), %@: %@", b.osm, area, r, g, bl, hue, colour))
        }
        return out
    }

    /// Whether a point is inside a ring.
    static func inside(_ q: P2, _ ring: [P2]) -> Bool {
        var c = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
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
