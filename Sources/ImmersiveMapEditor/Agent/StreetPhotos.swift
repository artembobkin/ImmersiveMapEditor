import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// Street-level photos of a landmark (Mapillary's) judged by geometry: from
/// where each camera stands, which way it looks and how wide (its focal
/// length), against the landmark's outlines and height from OSM and the
/// other buildings of the tile, where the landmark is in the frame, how
/// much of the frame it fills, how much of it shows, and whether a
/// neighbour stands in the way. The best are picked track by track (a
/// Mapillary sequence: one car's or walker's pass), a track or two for each
/// side the landmark is seen from, a frame or two from each. A kept photo
/// gets the landmark framed in red, and a panorama is cut to it, so the
/// agent knows which building it is looking at.
struct StreetScene {
    /// Longitude and latitude of the landmark's centre.
    let lon: Double, lat: Double
    /// Metres a degree, east and north.
    let kx: Double, ky: Double
    /// The corners of the landmark's convex hull, in metres around its
    /// centre: enough for where it is seen from, a few dozen instead of
    /// the thousands of corners of a landmark of many parts.
    let corners: [P2]
    /// How tall it is at most.
    let top: Double
    /// The other buildings of the tile, to see what hides it, each with its
    /// bounds (west, south, east, north).
    let others: [(shape: Geometry, bounds: (Double, Double, Double, Double))]

    init(folder: URL) throws {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        (lon, lat) = source.centre
        kx = cos(lat * .pi / 180) * 111_320.0
        ky = 110_574.0
        let all = source.buildings.flatMap { $0.polygons.flatMap { $0.first ?? [] } }
        let hull = Geometry.collection(all.map { Geometry.point($0) }).convexHull
        corners = hull.kind == .polygon ? Array(hull.exterior.dropLast()) : all
        top = source.buildings.compactMap(\.height).max() ?? 15
        let own = Set(source.buildings.map(\.osm))
        var others: [(shape: Geometry, bounds: (Double, Double, Double, Double))] = []
        // The tile's buildings, apart from the landmark's own.
        let tileFolder = folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("osm")
        if let tile = try? Tile(folder: tileFolder), let osm = try? Osm(tile) {
            let centre = tile.metres(lat: lat, lon: lon)
            for a in osm.areas() where a.tags["building"] != nil && a.tags["building"] != "no" && !own.contains("\(a.kind)/\(a.id)") {
                for poly in a.shape.polygons where poly.area > 20 {
                    let shape = Geometry.polygon(poly.exterior.map { $0 - centre })
                    others.append((shape, shape.bounds))
                }
            }
        }
        self.others = others
    }

    /// Metres east and north of the centre.
    func metres(lon: Double, lat: Double) -> P2 { P2((lon - self.lon) * kx, (lat - self.lat) * ky) }
}

/// One photo, as Mapillary describes it.
struct StreetPhoto {
    let id: String
    /// Where the camera stands, in the scene's metres.
    let at: P2
    /// Which way it looks, a compass bearing.
    let compass: Double?
    let pano: Bool
    /// "perspective", "fisheye" or "spherical".
    let camera: String
    /// Focal length over the longer side, OpenSfM's normalisation.
    let focal: Double
    let width: Int, height: Int
    let captured: Date?
    let author: String
    let sequence: String
    let thumb: String?
    /// How far the pose Mapillary computed (structure from motion) is from
    /// what the device recorded: a large difference means one of them is
    /// wrong, and the photo may not show what the geometry says.
    let poseDoubt: Bool
    /// Mapillary's own quality score, 0 to 1, when it has one.
    let quality: Double?
    /// The local hour it was taken, to tell night from day.
    let hour: Int?

    static let fields = "id,computed_geometry,geometry,computed_compass_angle,compass_angle,captured_at,creator,is_pano,camera_type,camera_parameters,width,height,sequence,quality_score"

    init?(_ e: [String: Any], _ scene: StreetScene) {
        guard let id = e["id"] as? String,
              let c = (e["computed_geometry"] as? [String: Any])?["coordinates"] as? [Double], c.count == 2 else { return nil }
        self.id = id
        at = scene.metres(lon: c[0], lat: c[1])
        compass = (e["computed_compass_angle"] as? NSNumber)?.doubleValue
        pano = e["is_pano"] as? Bool ?? false
        camera = e["camera_type"] as? String ?? (pano ? "spherical" : "perspective")
        let params = e["camera_parameters"] as? [Double] ?? []
        focal = params.first.map { $0 > 0.1 && $0 < 5 ? $0 : 0.7 } ?? 0.7
        width = (e["width"] as? NSNumber)?.intValue ?? 1920
        height = (e["height"] as? NSNumber)?.intValue ?? 1080
        captured = (e["captured_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        author = (e["creator"] as? [String: Any])?["username"] as? String ?? "unknown"
        sequence = e["sequence"] as? String ?? id
        thumb = (e["thumb_original_url"] as? String) ?? (e["thumb_2048_url"] as? String) ?? (e["thumb_1024_url"] as? String)
        var doubt = false
        if let raw = (e["geometry"] as? [String: Any])?["coordinates"] as? [Double], raw.count == 2,
           simd_length(scene.metres(lon: raw[0], lat: raw[1]) - at) > 20 { doubt = true }
        if let c = compass, let raw = (e["compass_angle"] as? NSNumber)?.doubleValue,
           abs(StreetView.wrap(c - raw)) > 35 { doubt = true }
        poseDoubt = doubt
        quality = (e["quality_score"] as? NSNumber)?.doubleValue
        hour = captured.map { Int(($0.timeIntervalSince1970 / 3600 + (scene.lon / 15).rounded()).truncatingRemainder(dividingBy: 24)) }
    }

    var date: String {
        guard let captured else { return "?" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: captured)
    }
}

/// Where the landmark is in a photo's frame, and how good a look it is.
struct StreetView {
    let photo: StreetPhoto
    /// Metres to the nearest corner.
    let distance: Double
    /// The side of the centre the camera stands on (a compass bearing).
    let from: Double
    /// Degrees between where the camera looks and the centre (0 for a panorama).
    let off: Double
    /// The landmark's bearings from the camera, relative to the view, and
    /// the part of that span within the frame.
    let span: ClosedRange<Double>
    let coverage: Double
    /// The frame it takes, as fractions of width and height (0 to 1), in
    /// a panorama the cut taken around it.
    let box: CGRect
    let share: Double
    let hidden: Double
    let score: Double

    static let sides = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    static func side(_ bearing: Double) -> String { sides[Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45) % 8] }

    static func wrap(_ a: Double) -> Double { ((a + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180 }

    /// The look a photo gives of the scene's landmark, nil when it does not
    /// show it (behind the camera, out of the frame, hidden). A quick look
    /// leaves out what hides it, for sorting thousands.
    init?(_ photo: StreetPhoto, in scene: StreetScene, quick: Bool = false) {
        self.photo = photo
        guard !scene.corners.isEmpty else { return nil }
        let toCentre = (atan2(-photo.at.x, -photo.at.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        from = (toCentre + 180).truncatingRemainder(dividingBy: 360)
        var bearings: [(angle: Double, far: Double)] = []
        for c in scene.corners {
            let d = c - photo.at
            bearings.append((Self.wrap(atan2(d.x, d.y) * 180 / .pi - toCentre), simd_length(d)))
        }
        var nearest = Double.infinity, lo = Double.infinity, hi = -Double.infinity
        for b in bearings {
            nearest = min(nearest, b.far)
            lo = min(lo, b.angle)
            hi = max(hi, b.angle)
        }
        distance = nearest
        guard distance > 5 else { return nil }
        guard hi - lo < 300 else { return nil }   // standing inside it
        // The view's direction: the compass, or the centre for a panorama.
        let look = photo.pano ? toCentre : (photo.compass ?? toCentre)
        off = photo.pano ? 0 : abs(Self.wrap(look - toCentre))
        let rel = Self.wrap(toCentre - look)
        span = (lo + rel)...(hi + rel)
        let top = atan2(scene.top - 2, max(distance, 1)) * 180 / .pi, bottom = atan2(-2.0, max(distance, 1)) * 180 / .pi
        let w = Double(photo.width), h = Double(photo.height), l = max(w, h)
        var x0 = 0.0, x1 = 0.0, y0 = 0.0, y1 = 0.0, half = 0.0
        switch photo.camera {
        case "spherical":
            half = 180
            x0 = 0.5 + (span.lowerBound - 8) / 360
            x1 = 0.5 + (span.upperBound + 8) / 360
            y0 = 0.5 - min(top + 8, 80) / 180
            y1 = 0.5 - max(bottom - 10, -60) / 180
        case "fisheye":
            half = 0.5 / photo.focal * 180 / .pi
            func x(_ a: Double) -> Double { 0.5 + photo.focal * l / w * (a * .pi / 180) }
            x0 = x(span.lowerBound); x1 = x(span.upperBound)
            y0 = 0.5 - photo.focal * l / h * (top * .pi / 180); y1 = 0.5 - photo.focal * l / h * (bottom * .pi / 180)
        default:
            half = atan(0.5 * w / l / photo.focal) * 180 / .pi
            func x(_ a: Double) -> Double { 0.5 + photo.focal * l / w * tan(max(-80, min(80, a)) * .pi / 180) }
            x0 = x(span.lowerBound); x1 = x(span.upperBound)
            y0 = 0.5 - photo.focal * l / h * tan(min(top, 80) * .pi / 180); y1 = 0.5 - photo.focal * l / h * tan(bottom * .pi / 180)
        }
        let visible = max(0, min(span.upperBound, half) - max(span.lowerBound, -half))
        coverage = visible / max(span.upperBound - span.lowerBound, 1)
        guard coverage > 0.15 else { return nil }
        let bx0 = max(0, min(1, x0)), bx1 = max(0, min(1, x1)), by0 = max(0, min(1, y0)), by1 = max(0, min(1, y1))
        box = CGRect(x: bx0, y: by0, width: max(0, bx1 - bx0), height: max(0, by1 - by0))
        share = photo.pano ? min(1, visible / 90) : box.width
        guard share > 0.08 else { return nil }
        // What hides it: rays to the corners in view, through the other buildings.
        var rays = 0, blocked = 0
        if !quick {
            for (b, c) in zip(bearings, scene.corners) where b.angle + rel >= max(span.lowerBound, -half) && b.angle + rel <= min(span.upperBound, half) {
                rays += 1
                let d = c - photo.at
                let p0 = photo.at + d * (3 / max(b.far, 3)), p1 = photo.at + d * (1 - 1.5 / max(b.far, 1.5))
                let (x0, x1) = (min(p0.x, p1.x), max(p0.x, p1.x)), (y0, y1) = (min(p0.y, p1.y), max(p0.y, p1.y))
                let ray = Geometry.lineString([p0, p1])
                if scene.others.contains(where: { o in
                    o.bounds.0 <= x1 && o.bounds.2 >= x0 && o.bounds.1 <= y1 && o.bounds.3 >= y0 && o.shape.intersects(ray) }) { blocked += 1 }
            }
        }
        hidden = quick ? 0 : rays == 0 ? 1 : Double(blocked) / Double(rays)
        guard hidden < 0.6 else { return nil }
        let fill = min(share / 0.35, 1) * (share > 0.97 && !photo.pano ? 0.7 : 1)
        let frontal = max(0.2, 1 - off / 75)
        let near = distance < 12 ? 0.4 : distance > 160 ? 0.5 : 1
        let years: Double = photo.captured.map { Date().timeIntervalSince($0) / 31_557_600 } ?? 8
        let fresh = max(0.6, 1 - years * 0.05)
        let sure = photo.poseDoubt ? 0.4 : 1.0
        let good = photo.quality.map { 0.5 + 0.5 * $0 } ?? 0.9
        let day = photo.hour.map { $0 >= 7 && $0 <= 19 ? 1.0 : 0.4 } ?? 1
        score = fill * (0.4 + 0.6 * coverage) * frontal * near * (1 - hidden) * fresh * sure * good * day * (photo.pano ? 0.9 : 1)
    }

    var line: String {
        let what = coverage > 0.9 ? "the whole of it" : "\(Int(coverage * 100))% of it"
        let how = photo.pano ? "a panorama, cut to it" : "\(Int(share * 100))% of the frame, \(Int(off))° off"
        let doubts = [photo.poseDoubt ? "its pose is doubtful" : nil, (photo.hour ?? 12) < 7 || (photo.hour ?? 12) > 19 ? "at night" : nil]
            .compactMap { $0 }
        return "\(photo.id): \(Int(distance)) m, from the \(Self.side(from)), \(what), \(how), \(photo.date)"
            + (doubts.isEmpty ? "" : " (" + doubts.joined(separator: ", ") + ")")
    }
}

enum StreetPicks {
    /// The best looks, a track or two for each side the landmark is seen
    /// from, a frame or two from each track: lines for the agent.
    static func report(_ views: [StreetView], limit: Int) -> (text: String, picks: [StreetView]) {
        guard !views.isEmpty else { return ("", []) }
        var bySequence: [String: [StreetView]] = [:]
        // A poor look (glancing, too close, a sliver) is not worth a track.
        for v in views where v.score >= 0.04 { bySequence[v.photo.sequence, default: []].append(v) }
        // A track's worth: its best frame, and a little for having several.
        let tracks = bySequence.values.map { frames -> (score: Double, frames: [StreetView]) in
            let sorted = frames.sorted { $0.score > $1.score }
            return (sorted[0].score + 0.05 * Double(min(frames.count, 4)), sorted)
        }.sorted { $0.score > $1.score }
        var perSide: [String: Int] = [:]
        var out: [String] = []
        var picks: [StreetView] = []
        var taken = 0
        for track in tracks where taken < limit {
            let best = track.frames[0], side = StreetView.side(best.from)
            guard perSide[side, default: 0] < 2 else { continue }
            perSide[side, default: 0] += 1
            var picked = [best]
            // A second frame of the track when it looks from another side, or
            // from well apart.
            if let other = track.frames.dropFirst().first(where: {
                StreetView.side($0.from) != side || simd_length($0.photo.at - best.photo.at) > 25 }), other.score > best.score * 0.6 {
                picked.append(other)
            }
            taken += picked.count
            out.append("Track by \(best.photo.author), \(best.photo.date), \(track.frames.count) frames show it from the \(side):\n"
                       + picked.map { v -> String in
                           picks.append(v)
                           return "  #\(picks.count) " + v.line
                       }.joined(separator: "\n"))
        }
        return (out.joined(separator: "\n"), picks)
    }

    /// A contact sheet of the picks: their thumbnails in a grid, the landmark
    /// framed in red on each, numbered as the report numbers them, so the
    /// agent sees at once which really show it.
    static func sheet(_ picks: [StreetView], thumbs: [URL?], to file: URL) throws {
        let cells = picks.enumerated().map { k, view -> ContactSheet.Cell in
            ContactSheet.Cell(image: thumbs[k], box: view.box, cut: view.photo.pano,
                              label: "#\(k + 1)  \(view.photo.id)  \(Int(view.distance)) m, from the \(StreetView.side(view.from))")
        }
        try ContactSheet.draw(cells, to: file)
    }
}

/// A grid of pictures with a label each, and a red frame where one is
/// given: what the agent looks at to choose.
enum ContactSheet {
    struct Cell {
        let image: URL?
        /// The frame, as fractions of the picture (from the top left).
        let box: CGRect?
        /// Whether to cut the picture to the frame first (a panorama).
        let cut: Bool
        let label: String
    }

    static func draw(_ cells: [Cell], to file: URL) throws {
        let columns = cells.count <= 4 ? 2 : cells.count <= 9 ? 3 : 4, rows = (cells.count + columns - 1) / columns
        let cw = 320, ch = 260, pad = 6
        let w = columns * cw, h = rows * ch
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (k, cell) in cells.enumerated() {
            let col = k % columns, row = k / columns
            // CoreGraphics' y goes up: the first row at the top.
            let area = CGRect(x: col * cw + pad, y: h - (row + 1) * ch + pad + 22, width: cw - 2 * pad, height: ch - 2 * pad - 22)
            if let url = cell.image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                var shown = image
                var box = cell.box
                if cell.cut, let b = box, let (part, inner) = StreetMarking.cut(image, b) {
                    shown = part
                    box = inner
                }
                let scale = min(area.width / Double(shown.width), area.height / Double(shown.height))
                let dw = Double(shown.width) * scale, dh = Double(shown.height) * scale
                let at = CGRect(x: area.midX - dw / 2, y: area.midY - dh / 2, width: dw, height: dh)
                ctx.draw(shown, in: at)
                if let box {
                    let frame = CGRect(x: at.minX + box.minX * dw, y: at.minY + (1 - box.maxY) * dh, width: box.width * dw, height: box.height * dh)
                    // Dimmed, not painted over: the agent judges the pose by what is around.
                    StreetMarking.mask(ctx, outside: frame, in: at, alpha: 0.65)
                    ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
                    ctx.setLineWidth(3)
                    ctx.stroke(frame.insetBy(dx: -1.5, dy: -1.5))
                }
            }
            let text = NSAttributedString(string: cell.label, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 13, nil), .foregroundColor: CGColor(gray: 0.95, alpha: 1)])
            let line = CTLineCreateWithAttributedString(text)
            ctx.textPosition = CGPoint(x: Double(col * cw + pad), y: Double(h - (row + 1) * ch + pad))
            CTLineDraw(line, ctx)
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// A kept photo marked: everything but the landmark painted black and the
/// landmark framed in red, a panorama cut to it first.
enum StreetMarking {
    /// Paints everything outside `rect` black, `alpha` deep.
    static func mask(_ ctx: CGContext, outside rect: CGRect, in full: CGRect, alpha: Double) {
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(rect)
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
        ctx.fill(full)
        ctx.restoreGState()
    }

    /// A panorama cut around the landmark's box: the part, and the box
    /// within it.
    static func cut(_ image: CGImage, _ box: CGRect) -> (CGImage, CGRect)? {
        let w = Double(image.width), h = Double(image.height)
        let cx0 = max(0, box.minX - 0.03), cx1 = min(1, box.maxX + 0.03)
        let cy0 = max(0, box.minY - 0.04), cy1 = min(1, box.maxY + 0.03)
        let rect = CGRect(x: cx0 * w, y: cy0 * h, width: (cx1 - cx0) * w, height: (cy1 - cy0) * h).integral
        guard rect.width > 50, rect.height > 50, let part = image.cropping(to: rect) else { return nil }
        return (part, CGRect(x: (box.minX - cx0) / (cx1 - cx0), y: (box.minY - cy0) / (cy1 - cy0),
                             width: box.width / (cx1 - cx0), height: box.height / (cy1 - cy0)))
    }

    static func mark(_ file: URL, _ view: StreetView, maxSide: Int = 1280) throws {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw NSError(domain: "StreetMarking", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read the picture"])
        }
        var shown = image
        var box = view.box
        if view.photo.pano, let (part, inner) = cut(image, box) {
            shown = part
            box = inner
        }
        let scale = min(1, Double(maxSide) / Double(max(shown.width, shown.height)))
        let w = Int(Double(shown.width) * scale), h = Int(Double(shown.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.draw(shown, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics' y goes up: the box's fractions are from the top.
        let rect = CGRect(x: box.minX * Double(w), y: (1 - box.maxY) * Double(h), width: box.width * Double(w), height: box.height * Double(h))
            .insetBy(dx: -3, dy: -3)
        mask(ctx, outside: rect, in: CGRect(x: 0, y: 0, width: w, height: h), alpha: 1)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.95))
        ctx.setLineWidth(max(3, Double(w) * 0.004))
        ctx.stroke(rect)
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// Mapillary's coverage tiles (Mapbox vector tiles, zoom 14, the `image`
/// layer: every photo as a point with its id, compass angle, date, pano
/// flag and sequence): the complete and steady list of what is there,
/// where the Graph API's box search answers with a different sample every
/// time. Only what the points need of the protobuf is read.
enum CoverageTile {
    struct Point {
        let lon: Double, lat: Double
        let props: [String: Any]
    }

    static let zoom = 14

    /// The tile holding a longitude and latitude.
    static func tile(lon: Double, lat: Double) -> (x: Int, y: Int) {
        let n = Double(1 << zoom), r = lat * .pi / 180
        return (Int((lon + 180) / 360 * n), Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n))
    }

    /// The points of a tile's `image` layer, in longitude and latitude.
    static func points(_ data: Data, x: Int, y: Int) -> [Point] {
        var out: [Point] = []
        let n = Double(1 << zoom)
        var tile = Reader(Array(data))
        while let (field, wire) = tile.key() {
            guard field == 3, wire == 2, let layer = tile.bytes() else { tile.skip(wire); continue }
            var r = Reader(layer)
            var name = "", extent = 4096.0
            var keys: [String] = [], values: [Any] = [], features: [[UInt8]] = []
            while let (f, w) = r.key() {
                switch (f, w) {
                case (1, 2): name = r.string() ?? ""
                case (2, 2): if let b = r.bytes() { features.append(b) }
                case (3, 2): keys.append(r.string() ?? "")
                case (4, 2): if let b = r.bytes() { values.append(value(b)) }
                case (5, 0): extent = Double(r.varint())
                default: r.skip(w)
                }
            }
            guard name == "image" else { continue }
            for feature in features {
                var fr = Reader(feature)
                var tags: [UInt64] = [], geometry: [UInt64] = [], type = 0
                while let (f, w) = fr.key() {
                    switch (f, w) {
                    case (2, 2): tags = fr.packed()
                    case (3, 0): type = Int(fr.varint())
                    case (4, 2): geometry = fr.packed()
                    default: fr.skip(w)
                    }
                }
                guard type == 1, geometry.count >= 3, geometry[0] & 7 == 1 else { continue }
                var props: [String: Any] = [:]
                for i in stride(from: 0, to: tags.count - 1, by: 2) where Int(tags[i]) < keys.count && Int(tags[i + 1]) < values.count {
                    props[keys[Int(tags[i])]] = values[Int(tags[i + 1])]
                }
                let px = Double(zigzag(geometry[1])), py = Double(zigzag(geometry[2]))
                let lon = (Double(x) + px / extent) / n * 360 - 180
                let lat = atan(sinh(.pi * (1 - 2 * (Double(y) + py / extent) / n))) * 180 / .pi
                out.append(Point(lon: lon, lat: lat, props: props))
            }
        }
        return out
    }

    static func zigzag(_ v: UInt64) -> Int64 { Int64(v >> 1) ^ -Int64(v & 1) }

    static func value(_ bytes: [UInt8]) -> Any {
        var r = Reader(bytes)
        while let (f, w) = r.key() {
            switch (f, w) {
            case (1, 2): return r.string() ?? ""
            case (2, 5): return Double(Float(bitPattern: UInt32(r.fixed(4))))
            case (3, 1): return Double(bitPattern: r.fixed(8))
            case (4, 0): return Int64(bitPattern: r.varint())
            case (5, 0): return r.varint()
            case (6, 0): return zigzag(r.varint())
            case (7, 0): return r.varint() != 0
            default: r.skip(w)
            }
        }
        return ""
    }

    /// A protobuf reader of the little a tile needs.
    struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func varint() -> UInt64 {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let byte = b[i]
                i += 1
                v |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return v
        }

        mutating func key() -> (Int, Int)? {
            guard i < b.count else { return nil }
            let k = varint()
            return (Int(k >> 3), Int(k & 7))
        }

        mutating func bytes() -> [UInt8]? {
            let n = Int(varint())
            guard i + n <= b.count else { i = b.count; return nil }
            defer { i += n }
            return Array(b[i..<(i + n)])
        }

        mutating func string() -> String? { bytes().flatMap { String(bytes: $0, encoding: .utf8) } }

        mutating func packed() -> [UInt64] {
            guard let inner = bytes() else { return [] }
            var r = Reader(inner), out: [UInt64] = []
            while r.i < inner.count { out.append(r.varint()) }
            return out
        }

        mutating func fixed(_ n: Int) -> UInt64 {
            var v: UInt64 = 0
            for k in 0..<n where i + k < b.count { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
            i += n
            return v
        }

        mutating func skip(_ wire: Int) {
            switch wire {
            case 0: _ = varint()
            case 1: i += 8
            case 2: _ = bytes()
            case 5: i += 4
            default: i = b.count
            }
        }
    }
}
