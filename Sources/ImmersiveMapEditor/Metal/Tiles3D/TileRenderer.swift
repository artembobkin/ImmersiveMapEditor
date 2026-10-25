import Foundation
import ImageIO
import Metal
import simd

/// Draws tiles as the engine draws a model tile: the palette times the light
/// map, raw values, no lighting of its own, back faces culled, each tile
/// placed and scaled as the engine places it, over a plain plane where the
/// vector tile's ground would be. Metal only: no camera, no input.
final class TileRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    static let colourFormat = MTLPixelFormat.bgra8Unorm
    static let depthFormat = MTLPixelFormat.depth32Float
    static let samples = 4
    static let sky = MTLClearColor(red: 0.80, green: 0.85, blue: 0.90, alpha: 1)

    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let white: MTLTexture
    private let groundColour: MTLTexture

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct U { float4x4 viewProjection; float4 place; };
    struct Out { float4 position [[position]]; float2 uv0; float2 uv1; };
    vertex Out vs(uint vid [[vertex_id]], const device packed_float3* p [[buffer(0)]],
                  const device float2* uv0 [[buffer(1)]], const device float2* uv1 [[buffer(2)]],
                  constant U& u [[buffer(3)]]) {
        float3 world = u.place.xyz + float3(p[vid]) * u.place.w;
        Out o;
        o.position = u.viewProjection * float4(world, 1);
        o.uv0 = uv0[vid];
        o.uv1 = uv1[vid];
        return o;
    }
    fragment float4 fs(Out i [[stage_in]], texture2d<float> palette [[texture(0)]],
                       texture2d<float> light [[texture(1)]], sampler s [[sampler(0)]]) {
        return float4(palette.sample(s, i.uv0).rgb * light.sample(s, i.uv1).rgb, 1);
    }
    """

    /// What a draw takes per tile: the frame's view and projection, and where
    /// the tile goes (xyz) at what scale (w).
    private struct Uniforms {
        var viewProjection: simd_float4x4
        var place: SIMD4<Float>
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "vs")
            d.fragmentFunction = library.makeFunction(name: "fs")
            d.colorAttachments[0].pixelFormat = Self.colourFormat
            d.depthAttachmentPixelFormat = Self.depthFormat
            d.rasterSampleCount = Self.samples
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            return nil
        }
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        depth = device.makeDepthStencilState(descriptor: ds)!
        // As the engine samples: trilinear, 4x anisotropy, clamped.
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.maxAnisotropy = 4
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)!
        func solid(_ c: SIMD4<Float>) -> MTLTexture {
            let t = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1,
                                                                        mipmapped: false))!
            var px = SIMD4<UInt8>(UInt8(c.x * 255), UInt8(c.y * 255), UInt8(c.z * 255), 255)
            t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
            return t
        }
        white = solid(SIMD4(1, 1, 1, 1))
        groundColour = solid(Colours.ground)
    }

    /// Draws the ground and the tiles.
    func encode(_ enc: MTLRenderCommandEncoder, tiles library: TileLibrary, viewProjection vp: simd_float4x4,
                lightMap: Bool) {
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setFragmentSamplerState(sampler, index: 0)
        // The vector tile's ground, a plain plane just under the models.
        if let (c, reach) = library.extent {
            let r = Float(reach + 400)
            let quad: [Float] = [-r, -0.05, r, r, -0.05, r, r, -0.05, -r, -r, -0.05, r, r, -0.05, -r, -r, -0.05, -r]
            let zeros = [Float](repeating: 0, count: 12)
            var u = Uniforms(viewProjection: vp, place: SIMD4(Float(c.x), 0, Float(-c.y), 1))
            enc.setVertexBuffer(device.makeBuffer(bytes: quad, length: quad.count * 4), offset: 0, index: 0)
            enc.setVertexBuffer(device.makeBuffer(bytes: zeros, length: zeros.count * 4), offset: 0, index: 1)
            enc.setVertexBuffer(device.makeBuffer(bytes: zeros, length: zeros.count * 4), offset: 0, index: 2)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 3)
            enc.setFragmentTexture(groundColour, index: 0)
            enc.setFragmentTexture(white, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        for t in library.tiles {
            var u = Uniforms(viewProjection: vp, place: SIMD4(Float(t.centre.x), 0, Float(-t.centre.y), Float(t.scale)))
            enc.setVertexBuffer(t.positions, offset: 0, index: 0)
            enc.setVertexBuffer(t.uv0, offset: 0, index: 1)
            enc.setVertexBuffer(t.uv1, offset: 0, index: 2)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 3)
            enc.setFragmentTexture(t.palette, index: 0)
            enc.setFragmentTexture(lightMap ? t.light : white, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: t.indexCount, indexType: t.indexType,
                                      indexBuffer: t.indices, indexBufferOffset: 0)
        }
    }

    /// The tiles drawn offscreen to a PNG, `width` by `height`.
    func snapshot(_ library: TileLibrary, viewProjection: simd_float4x4, lightMap: Bool, to url: URL,
                  width: Int, height: Int) throws {
        try Self.renderPNG(device: device, queue: queue, to: url, width: width, height: height) { enc in
            encode(enc, tiles: library, viewProjection: viewProjection, lightMap: lightMap)
        }
    }

    /// One frame drawn by `encode` without a window, into a PNG: the 3D views'
    /// formats, multisampled and resolved.
    static func renderPNG(device: MTLDevice, queue: MTLCommandQueue, to url: URL, width: Int, height: Int,
                          encode: (MTLRenderCommandEncoder) -> Void) throws {
        guard let buffer = queue.makeCommandBuffer() else { return }
        func texture(_ format: MTLPixelFormat, samples: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = samples > 1 || format == Self.depthFormat ? .private : .shared
            return device.makeTexture(descriptor: d)!
        }
        let colour = texture(Self.colourFormat, samples: Self.samples), resolved = texture(Self.colourFormat, samples: 1)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colour
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.sky
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = texture(Self.depthFormat, samples: Self.samples)
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(enc)
        enc.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: width * height * 4)
        resolved.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        // BGRA as it was drawn, opaque.
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent),
              let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw RenderFailure.png }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { throw RenderFailure.png }
    }

    enum RenderFailure: Error { case png }
}
