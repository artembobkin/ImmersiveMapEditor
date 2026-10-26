import CoreGraphics
import CoreML
import Foundation
import Vision

/// What is in the way in a street photo, pixel by pixel, by DeepLabV3
/// (Apple's Core ML build of the TensorFlow model, Apache 2.0, trained on
/// PASCAL VOC): people, bicycles, motorbikes, cars, buses and trains. The
/// model (9 MB) is fetched once from Apple into the data folder's
/// config/models and compiled there; it runs on the device. Without it
/// (no network yet), PeopleMask falls back to Vision's people alone.
enum Segmenter {
    static let url = "https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3.mlmodel"
    /// PASCAL VOC's classes in the way: bicycle, bus, car, motorbike, person, train.
    static let inTheWay: Set<Int32> = [2, 6, 7, 14, 15, 19]

    /// The data folder's models folder, set at start by whoever runs this
    /// process (the app, the agent's tools, a headless command).
    nonisolated(unsafe) static var folder: URL?
    nonisolated(unsafe) private static var loaded: VNCoreMLModel?
    nonisolated(unsafe) private static var failed = false

    /// The model, fetched and compiled the first time, nil when it cannot be had.
    static func model() -> VNCoreMLModel? {
        if let loaded { return loaded }
        guard !failed, let folder else { return nil }
        failed = true
        let compiled = folder.appendingPathComponent("DeepLabV3.mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let raw = folder.appendingPathComponent("DeepLabV3.mlmodel")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: raw.path) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                p.arguments = ["-fsSL", "--max-time", "180", "-o", raw.path, url]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return nil }
                p.waitUntilExit()
                guard p.terminationStatus == 0 else { try? FileManager.default.removeItem(at: raw); return nil }
            }
            guard let made = try? MLModel.compileModel(at: raw) else { return nil }
            try? FileManager.default.removeItem(at: compiled)
            guard (try? FileManager.default.moveItem(at: made, to: compiled)) != nil else { return nil }
        }
        guard let ml = try? MLModel(contentsOf: compiled), let vn = try? VNCoreMLModel(for: ml) else { return nil }
        loaded = vn
        failed = false
        return vn
    }

    /// The class of every pixel of a picture, 513 by 513 over its whole
    /// extent, nil without the model.
    static func labels(of image: CGImage) -> MLMultiArray? {
        guard let model = model() else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let result = request.results?.first as? VNCoreMLFeatureValueObservation else { return nil }
        return result.featureValue.multiArrayValue
    }
}
