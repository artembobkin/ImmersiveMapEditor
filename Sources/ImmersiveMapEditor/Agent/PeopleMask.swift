import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

/// The people, cars and buses in a reference photo painted black: Vision's
/// person segmentation (the Mac's own model) and DeepLabV3 (Segmenter,
/// fetched once), both on the device. A reference is the building, and a
/// crowd or the traffic before it only distracts.
enum PeopleMask {
    /// Paints the people of a JPEG black, in place. Leaves it as it is when
    /// the model finds none or fails. Returns whether it painted.
    @discardableResult
    static func erase(_ file: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let out = erase(image),
              let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// The picture with its people black, nil when there are none: the
    /// whole picture segmented for the large ones, and the people the
    /// detector finds each segmented in their own crop, where their outline
    /// comes out. Only what the model finds is painted: a small or far
    /// figure it misses stays (the user, 2026-10-26).
    static func erase(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let canvas = Canvas(p: data.assumingMemoryBound(to: UInt8.self), stride: ctx.bytesPerRow, w: w, h: h)
        var painted = false
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        if let mask = segmentation(of: image) { painted = canvas.paint(mask, in: full) || painted }
        for box in people(in: image) {
            let crop = box.insetBy(dx: -box.width * 0.4, dy: -box.height * 0.3).intersection(full).integral
            guard crop.width >= 8, crop.height >= 8, let part = image.cropping(to: crop) else { continue }
            if let mask = segmentation(of: part), canvas.paint(mask, in: crop) { painted = true }
        }
        // Then everything in the way by class: the whole picture, and its
        // quarters for the small and far.
        var windows = [full]
        for i in 0..<2 {
            for j in 0..<2 { windows.append(CGRect(x: Double(w) * 0.5 * Double(i), y: Double(h) * 0.5 * Double(j), width: Double(w) * 0.5, height: Double(h) * 0.5)) }
        }
        for window in windows {
            guard let part = window == full ? image : image.cropping(to: window.integral), let labels = Segmenter.labels(of: part) else { continue }
            if canvas.paint(labels: labels, in: window.integral) { painted = true }
        }
        return painted ? ctx.makeImage() : nil
    }

    /// Where the people are, in pixels from the top left, by the detector.
    static func people(in image: CGImage) -> [CGRect] {
        let w = Double(image.width), h = Double(image.height)
        let windows = [CGRect(x: 0, y: 0, width: w, height: h)]
        var boxes: [CGRect] = []
        for window in windows {
            guard let part = window.width < w ? image.cropping(to: window.integral) : image else { continue }
            let detect = VNDetectHumanRectanglesRequest()
            detect.upperBodyOnly = false
            try? VNImageRequestHandler(cgImage: part, options: [:]).perform([detect])
            for person in detect.results ?? [] where person.confidence > 0.3 {
                // Vision's box: normalised, from the bottom left of its
                // picture. The bitmap's rows go down from the top.
                let b = person.boundingBox, pw = Double(part.width), ph = Double(part.height)
                let box = CGRect(x: window.minX + b.minX * pw, y: window.minY + (1 - b.maxY) * ph, width: b.width * pw, height: b.height * ph)
                // The same person seen in two windows.
                if let k = boxes.firstIndex(where: { over($0, box) > 0.5 }) {
                    boxes[k] = boxes[k].union(box)
                } else {
                    boxes.append(box)
                }
            }
        }
        return boxes
    }

    /// How much two boxes overlap, over the smaller of them.
    static func over(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        return i.width * i.height / max(1, min(a.width * a.height, b.width * b.height))
    }

    /// Vision's mask of the people in a picture, nil when it sees none.
    static func segmentation(of image: CGImage) -> CVPixelBuffer? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            FileHandle.standardError.write(Data("PeopleMask: \(error)\n".utf8))
            return nil
        }
        return request.results?.first?.pixelBuffer
    }

    /// The bitmap being painted: RGBA rows from the top.
    struct Canvas {
        let p: UnsafeMutablePointer<UInt8>
        let stride: Int, w: Int, h: Int

        /// Paints black where a mask (over `region` of the bitmap) says a
        /// person is. Returns whether it painted anything.
        func paint(_ mask: CVPixelBuffer, in region: CGRect) -> Bool {
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(mask) else { return false }
            let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask), mstride = CVPixelBufferGetBytesPerRow(mask)
            let m = base.assumingMemoryBound(to: UInt8.self)
            let x0 = max(0, Int(region.minX)), x1 = min(w, Int(region.maxX)), y0 = max(0, Int(region.minY)), y1 = min(h, Int(region.maxY))
            guard x1 > x0, y1 > y0 else { return false }
            var any = false
            for y in y0..<y1 {
                let my = min(mh - 1, (y - y0) * mh / (y1 - y0))
                for x in x0..<x1 where m[my * mstride + min(mw - 1, (x - x0) * mw / (x1 - x0))] >= 128 {
                    let k = y * stride + x * 4
                    p[k] = 0; p[k + 1] = 0; p[k + 2] = 0
                    any = true
                }
            }
            return any
        }

        /// Paints black where the class map says something is in the way.
        func paint(labels: MLMultiArray, in region: CGRect) -> Bool {
            guard labels.shape.count == 2 else { return false }
            let mh = labels.shape[0].intValue, mw = labels.shape[1].intValue
            let x0 = max(0, Int(region.minX)), x1 = min(w, Int(region.maxX)), y0 = max(0, Int(region.minY)), y1 = min(h, Int(region.maxY))
            guard x1 > x0, y1 > y0, mw > 0, mh > 0 else { return false }
            let values = labels.dataPointer.assumingMemoryBound(to: Int32.self)
            let rowStride = labels.strides[0].intValue, colStride = labels.strides[1].intValue
            var any = false
            for y in y0..<y1 {
                let my = min(mh - 1, (y - y0) * mh / (y1 - y0))
                for x in x0..<x1 {
                    let mx = min(mw - 1, (x - x0) * mw / (x1 - x0))
                    guard Segmenter.inTheWay.contains(values[my * rowStride + mx * colStride]) else { continue }
                    let k = y * stride + x * 4
                    p[k] = 0; p[k + 1] = 0; p[k + 2] = 0
                    any = true
                }
            }
            return any
        }
    }
}
