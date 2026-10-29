// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Metal

/// One texture of a model, encoded: the ASTC blocks of every mip level,
/// level 0 first, down to one pixel.
struct EncodedTexture {
    let width: Int
    let height: Int
    let levels: [Data]
    /// How close the GPU's decode of level 0 is to the source, in decibels.
    /// Nil when the machine has no Metal device to decode with.
    let peakSignalToNoiseRatio: Double?
}

/// Turns the PNG of a model into the layer of a tile's texture array: ASTC
/// from the system's encoder (ImageIO), which writes 4x4 and 8x8 blocks.
///
/// The channel values pass through untouched: the engine samples model
/// textures raw, with no sRGB decode, so the mip levels are averaged in the
/// same raw values and nothing is converted on the way.
final class TextureEncoder {
    let blockEdge: Int
    private var encodedByDigest: [SHA256.Digest: EncodedTexture] = [:]
    private let decodeCheck: ASTCDecodeCheck?

    init(blockEdge: Int) throws {
        guard blockEdge == 4 || blockEdge == 8 else {
            throw BakeError("the system encoder writes ASTC 4x4 and 8x8 only, not \(blockEdge)x\(blockEdge)")
        }
        self.blockEdge = blockEdge
        self.decodeCheck = ASTCDecodeCheck(blockEdge: blockEdge)
    }

    /// The lowest decode quality among the textures encoded so far. Nil when
    /// there is no Metal device to decode with.
    var lowestPeakSignalToNoiseRatio: Double? {
        encodedByDigest.values.compactMap(\.peakSignalToNoiseRatio).min()
    }

    static func digest(of png: Data) -> SHA256.Digest {
        SHA256.hash(data: png)
    }

    /// Encodes a PNG once: the same bytes asked for again, by another model
    /// or another tile, come from the cache.
    func encode(png: Data, name: String) throws -> EncodedTexture {
        let digest = Self.digest(of: png)
        if let encoded = encodedByDigest[digest] {
            return encoded
        }
        var level = try Self.decode(png: png, name: name)
        guard level.width.nonzeroBitCount == 1, level.height.nonzeroBitCount == 1 else {
            throw BakeError("\(name): the texture is \(level.width)x\(level.height), and a mip chain needs powers of two")
        }
        let source = level
        var levels: [Data] = []
        while true {
            levels.append(try astcBlocks(of: level, name: name))
            if level.width == 1, level.height == 1 {
                break
            }
            level = level.halved()
        }
        var ratio: Double?
        if let decodeCheck {
            let decoded = try decodeCheck.decode(blocks: levels[0], width: source.width, height: source.height)
            let direct = source.peakSignalToNoiseRatio(against: decoded)
            let flipped = source.flippedVertically().peakSignalToNoiseRatio(against: decoded)
            guard direct > flipped else {
                throw BakeError("\(name): the encoded texture decodes upside down")
            }
            ratio = direct
        }
        let encoded = EncodedTexture(width: source.width, height: source.height, levels: levels,
                                     peakSignalToNoiseRatio: ratio)
        encodedByDigest[digest] = encoded
        return encoded
    }

    // MARK: - Pixels

    /// RGBA8 pixels, top row first.
    struct Pixels {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        /// The next mip level: each pixel the average of the two by two
        /// above it (of two, where the level is already one pixel thin).
        func halved() -> Pixels {
            let halfWidth = max(1, width / 2)
            let halfHeight = max(1, height / 2)
            var result = [UInt8](repeating: 0, count: halfWidth * halfHeight * 4)
            for y in 0..<halfHeight {
                let y0 = min(y * 2, height - 1)
                let y1 = min(y * 2 + 1, height - 1)
                for x in 0..<halfWidth {
                    let x0 = min(x * 2, width - 1)
                    let x1 = min(x * 2 + 1, width - 1)
                    for channel in 0..<4 {
                        let sum = Int(bytes[(y0 * width + x0) * 4 + channel])
                            + Int(bytes[(y0 * width + x1) * 4 + channel])
                            + Int(bytes[(y1 * width + x0) * 4 + channel])
                            + Int(bytes[(y1 * width + x1) * 4 + channel])
                        result[(y * halfWidth + x) * 4 + channel] = UInt8((sum + 2) / 4)
                    }
                }
            }
            return Pixels(width: halfWidth, height: halfHeight, bytes: result)
        }

        func flippedVertically() -> Pixels {
            var result = [UInt8]()
            result.reserveCapacity(bytes.count)
            for row in (0..<height).reversed() {
                result.append(contentsOf: bytes[(row * width * 4)..<((row + 1) * width * 4)])
            }
            return Pixels(width: width, height: height, bytes: result)
        }

        /// Over the color channels. The alpha of a model texture is opaque.
        func peakSignalToNoiseRatio(against other: [UInt8]) -> Double {
            var squaredError = 0.0
            for pixel in 0..<(width * height) {
                for channel in 0..<3 {
                    let difference = Double(bytes[pixel * 4 + channel]) - Double(other[pixel * 4 + channel])
                    squaredError += difference * difference
                }
            }
            guard squaredError > 0 else {
                return .infinity
            }
            return 10 * log10(255 * 255 / (squaredError / Double(width * height * 3)))
        }
    }

    private static func decode(png: Data, name: String) throws -> Pixels {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BakeError("\(name): the texture is not an image ImageIO reads")
        }
        guard image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst else {
            throw BakeError("\(name): the texture has an alpha channel, and model textures are opaque")
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        // The context takes the image's own color space, so drawing converts
        // nothing and the bytes are the channel values stored in the file.
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            throw BakeError("\(name): the texture could not be decoded")
        }
        for pixel in 0..<(width * height) {
            bytes[pixel * 4 + 3] = 255
        }
        return Pixels(width: width, height: height, bytes: bytes)
    }

    // MARK: - ASTC

    private func astcBlocks(of pixels: Pixels, name: String) throws -> Data {
        // ImageIO writes the rows of an ASTC file bottom row first. Metal
        // reads block row 0 as the top of the texture, so the image goes in
        // upside down and comes out top row first.
        let flipped = pixels.flippedVertically()
        guard let provider = CGDataProvider(data: Data(flipped.bytes) as CFData),
              let image = CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: pixels.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw BakeError("\(name): a mip level could not be handed to the encoder")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "org.khronos.astc" as CFString, 1, nil) else {
            throw BakeError("ImageIO has no ASTC encoder on this system")
        }
        let blockSize = blockEdge == 4 ? kCGImagePropertyASTCBlockSize4x4 : kCGImagePropertyASTCBlockSize8x8
        let properties: [CFString: Any] = [kCGImagePropertyEncoder: kCGImagePropertyASTCEncoder,
                                           kCGImagePropertyASTCBlockSize: blockSize]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw BakeError("\(name): the ASTC encoder failed on a \(pixels.width)x\(pixels.height) level")
        }

        // The file is a 16-byte header and the blocks. The tile stores the
        // blocks alone, so the header is checked here and dropped.
        let file = output as Data
        let headerByteCount = 16
        let blocksWide = (pixels.width + blockEdge - 1) / blockEdge
        let blocksHigh = (pixels.height + blockEdge - 1) / blockEdge
        func dimension(at offset: Int) -> Int {
            Int(file[offset]) | Int(file[offset + 1]) << 8 | Int(file[offset + 2]) << 16
        }
        guard file.count == headerByteCount + blocksWide * blocksHigh * 16,
              file.littleEndianUInt32(at: 0) == 0x5CA1_AB13,
              Int(file[4]) == blockEdge, Int(file[5]) == blockEdge, file[6] == 1,
              dimension(at: 7) == pixels.width, dimension(at: 10) == pixels.height, dimension(at: 13) == 1 else {
            throw BakeError("\(name): the ASTC encoder returned an unexpected file for a \(pixels.width)x\(pixels.height) level")
        }
        return file.subdata(in: headerByteCount..<file.count)
    }
}

/// Decodes ASTC blocks the way the engine will, on the GPU, so the baker
/// can tell that a texture came out the right way up and how close it is
/// to its source.
final class ASTCDecodeCheck {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let blockEdge: Int

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void copyTexels(texture2d<float, access::read> source [[texture(0)]],
                           texture2d<float, access::write> destination [[texture(1)]],
                           uint2 position [[thread_position_in_grid]]) {
        if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
            return;
        }
        destination.write(source.read(position), position);
    }
    """

    init?(blockEdge: Int) {
        guard let device = MTLCreateSystemDefaultDevice(),
              device.supportsFamily(.apple2),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let function = library.makeFunction(name: "copyTexels"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.blockEdge = blockEdge
    }

    /// RGBA8 pixels of the decoded blocks, top row first.
    func decode(blocks: Data, width: Int, height: Int) throws -> [UInt8] {
        let compressedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: blockEdge == 4 ? .astc_4x4_ldr : .astc_8x8_ldr,
            width: width, height: height, mipmapped: false)
        compressedDescriptor.usage = [.shaderRead]
        let decodedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        decodedDescriptor.usage = [.shaderWrite]
        decodedDescriptor.storageMode = .shared
        guard let compressed = device.makeTexture(descriptor: compressedDescriptor),
              let decoded = device.makeTexture(descriptor: decodedDescriptor),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw BakeError("Metal could not set up the texture decode check")
        }
        let blocksWide = (width + blockEdge - 1) / blockEdge
        blocks.withUnsafeBytes { bytes in
            compressed.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, slice: 0,
                               withBytes: bytes.baseAddress!, bytesPerRow: blocksWide * 16,
                               bytesPerImage: bytes.count)
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(compressed, index: 0)
        encoder.setTexture(decoded, index: 1)
        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = pipeline.maxTotalThreadsPerThreadgroup / groupWidth
        encoder.dispatchThreadgroups(MTLSize(width: (width + groupWidth - 1) / groupWidth,
                                             height: (height + groupHeight - 1) / groupHeight,
                                             depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            decoded.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return pixels
    }
}
