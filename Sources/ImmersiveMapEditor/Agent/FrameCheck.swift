import CoreGraphics
import Foundation
import ImageIO
import Vision

/// What the picture inside a street photo's red frame holds, read off its
/// pixels (the user, 2026-10-27: the geometry can say where the landmark
/// should be, not that the picture shows it). Two checks:
///
/// - Signs of a building: a facade is sharp, evenly lit and full of
///   straight edges, most of them upright (pilasters, window sides, the
///   corners); the sky, a snowy or rainy windscreen, a sun flare and a
///   blur are smooth, burnt out or edged every which way.
/// - Agreement: the photos of one facade show one building, so their
///   pictures look alike (Vision's feature print, the Mac's own); one far
///   from all the others shows something else (the sky, a windscreen,
///   another house).
enum FrameCheck {
    struct Signs {
        /// Variance of the Laplacian of the frame's grey, on 0...1 values.
        var sharpness: Double
        /// Of its pixels, the share burnt out white or black.
        var clipped: Double
        /// Of its pixels, the share smooth (hardly any change around).
        var smooth: Double
        /// Of its pixels, the share on a strong edge.
        var edges: Double
        /// Of the strong edges, the share upright (within 15°).
        var upright: Double
    }

    /// The frame's picture: the box (fractions of the picture, from its
    /// top left) cut out and scaled to `side` across at most.
    static func crop(_ image: CGImage, box: CGRect, side: Int = 320) -> CGImage? {
        let w = Double(image.width), h = Double(image.height)
        let rect = CGRect(x: box.minX * w, y: box.minY * h, width: box.width * w, height: box.height * h).integral
        guard rect.width >= 16, rect.height >= 16, let part = image.cropping(to: rect) else { return nil }
        let scale = min(1, Double(side) / Double(max(part.width, part.height)))
        let cw = max(8, Int(Double(part.width) * scale)), ch = max(8, Int(Double(part.height) * scale))
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        return ctx.makeImage()
    }

    /// The grey of a picture, 0...1, row by row from the top.
    static func grey(_ image: CGImage) -> (values: [Double], width: Int, height: Int) {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var out = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            out[i] = (0.299 * Double(bytes[i * 4]) + 0.587 * Double(bytes[i * 4 + 1]) + 0.114 * Double(bytes[i * 4 + 2])) / 255
        }
        return (out, w, h)
    }

    static func signs(_ picture: CGImage) -> Signs {
        let (g, w, h) = grey(picture)
        guard w >= 8, h >= 8 else { return Signs(sharpness: 0, clipped: 1, smooth: 1, edges: 0, upright: 0) }
        var clipped = 0, smooth = 0, strong = 0, upright = 0, n = 0
        var lap: [Double] = []
        lap.reserveCapacity(w * h)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let v = g[i]
                n += 1
                if v > 0.97 || v < 0.03 { clipped += 1 }
                // Sobel.
                let gx = (g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1]) - (g[i - w - 1] + 2 * g[i - 1] + g[i + w - 1])
                let gy = (g[i + w - 1] + 2 * g[i + w] + g[i + w + 1]) - (g[i - w - 1] + 2 * g[i - w] + g[i - w + 1])
                let m = (gx * gx + gy * gy).squareRoot()
                if m < 0.04 { smooth += 1 }
                if m > 0.25 {
                    strong += 1
                    // An upright edge: its gradient across, near horizontal.
                    if abs(gy) < abs(gx) * tan(15 * Double.pi / 180) { upright += 1 }
                }
                lap.append(g[i - w] + g[i + w] + g[i - 1] + g[i + 1] - 4 * v)
            }
        }
        let mean = lap.reduce(0, +) / Double(max(1, lap.count))
        let variance = lap.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, lap.count))
        let total = Double(max(1, n))
        return Signs(sharpness: variance, clipped: Double(clipped) / total, smooth: Double(smooth) / total,
                     edges: Double(strong) / total, upright: strong > 0 ? Double(upright) / Double(strong) : 0)
    }

    /// The Mac's feature print of a picture: how alike two pictures are.
    static func featurePrint(_ picture: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: picture, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Double {
        var d: Float = 0
        guard (try? a.computeDistance(&d, to: b)) != nil else { return .infinity }
        return Double(d)
    }

    /// How sure the Mac's scene classifier is that a picture holds a
    /// building (its most confident of structure, building, arch, window)
    /// and that it shows the sky.
    static func classify(_ picture: CGImage) -> (building: Double, sky: Double) {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: picture, options: [:]).perform([request])
        let found = request.results ?? []
        func sure(_ id: String) -> Double { Double(found.first { $0.identifier == id }?.confidence ?? 0) }
        return (["structure", "building", "arch", "window"].map(sure).max() ?? 0, sure("sky"))
    }

    struct Verdict {
        let keep: Bool
        /// Why it is dropped, or what was read when it is kept.
        let note: String
    }

    /// The candidates' pictures judged, each in the group of its facade.
    /// Dropped: a blank (hardly an edge, mostly smooth: burnt out, a sun
    /// flare); the sky (the classifier sure of the sky, over 0.9, and not
    /// of a building, under 0.4); a picture the classifier is unsure holds
    /// a building (under 0.5) that is also further from its three most
    /// alike pictures of the facade than the facade's pictures typically
    /// are (a windscreen, a car filling the frame, an empty street; the
    /// likeness of their upper parts, the facade, not the street at its
    /// foot). One the classifier is unsure of but that looks like its
    /// facade's others (a night view) stays. The classifier alone (a
    /// building over 0.6) was tried and lost a quarter of the good photos:
    /// it names a building unsurely at night, in a panorama or behind
    /// people. Measured on Detsky Mir (2026-10-27, the user's choice of
    /// the compromise): of 58 photos marked by eye the two bad dropped and
    /// four good of 50 lost; on an earlier 48, the five bad dropped. A
    /// picture not read stays.
    static func judge(_ pictures: [CGImage?], groups: [Int]) -> [Verdict] {
        let n = pictures.count
        var signs: [Signs?] = Array(repeating: nil, count: n)
        var sure = [Double](repeating: 1, count: n)
        var sky = [Double](repeating: 0, count: n)
        var prints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: n)
        for i in 0..<n {
            guard let p = pictures[i] else { continue }
            signs[i] = Self.signs(p)
            (sure[i], sky[i]) = classify(p)
            // Its upper part, the facade: the street, the cars and the
            // people at its foot differ from photo to photo of one facade.
            prints[i] = crop(p, box: CGRect(x: 0, y: 0, width: 1, height: 0.6)).flatMap(featurePrint)
        }
        // Each picture's mean distance to its three most alike in its group,
        // and the group's typical (median) one.
        var near = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            guard let a = prints[i] else { continue }
            let ds = (0..<n).filter { $0 != i && groups[$0] == groups[i] }.compactMap { j in prints[j].map { distance(a, $0) } }.sorted()
            guard ds.count >= 3 else { continue }
            near[i] = ds.prefix(3).reduce(0, +) / 3
        }
        var typical: [Int: Double] = [:]
        for g in Set(groups) {
            let ds = (0..<n).filter { groups[$0] == g && !near[$0].isNaN }.map { near[$0] }.sorted()
            if ds.count >= 4 { typical[g] = ds[ds.count / 2] }
        }
        return (0..<n).map { i in
            guard let s = signs[i] else { return Verdict(keep: true, note: "its picture not read") }
            let read = String(format: "building %.2f, sky %.2f, edges %.2f, smooth %.2f", sure[i], sky[i], s.edges, s.smooth)
                + (near[i].isNaN ? "" : String(format: ", %.2f from its three most alike (the facade's typical %.2f)", near[i], typical[groups[i]] ?? .nan))
            if s.edges < 0.1 && s.smooth > 0.6 { return Verdict(keep: false, note: "a blank picture: burnt out or a sun flare (\(read))") }
            if sky[i] > 0.9 && sure[i] < 0.4 { return Verdict(keep: false, note: "the sky (\(read))") }
            if sure[i] < 0.5 {
                // Unsure of a building to the classifier: kept only when it
                // looks like its facade's others.
                guard let t = typical[groups[i]], !near[i].isNaN else { return Verdict(keep: false, note: "no building in it (\(read))") }
                if near[i] > t { return Verdict(keep: false, note: "no building in it, and unlike its facade's other photos (\(read))") }
            }
            return Verdict(keep: true, note: read)
        }
    }

    /// Of a facade's pictures, each one's typical distance to the others
    /// (the median), and the ones far from the rest: beyond the median of
    /// those distances by `spread` times their median absolute deviation.
    static func strangers(_ prints: [VNFeaturePrintObservation?], spread: Double = 2.5) -> (typical: [Double], far: [Bool]) {
        let n = prints.count
        var typical = [Double](repeating: .infinity, count: n)
        for i in 0..<n {
            guard let a = prints[i] else { continue }
            let ds = (0..<n).filter { $0 != i }.compactMap { j in prints[j].map { distance(a, $0) } }.sorted()
            if !ds.isEmpty { typical[i] = ds[ds.count / 2] }
        }
        let finite = typical.filter(\.isFinite).sorted()
        guard finite.count >= 4 else { return (typical, typical.map { !$0.isFinite }) }
        let median = finite[finite.count / 2]
        let deviations = finite.map { abs($0 - median) }.sorted()
        let mad = max(deviations[deviations.count / 2], 0.02)
        return (typical, typical.map { !$0.isFinite || $0 > median + spread * mad })
    }
}
