import Foundation
import ImageIO
import Metal
import simd

/// Draws the tiles shown: each in its palette's colours under the previews'
/// one light (`PreviewLight`: a sun with its shadow over an ambient light),
/// back faces culled, placed and scaled as the engine places it, over a
/// plain plane where the vector tile's ground would be. Metal only: no
/// camera, no input.
final class TileRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    static let colourFormat = MTLPixelFormat.bgra8Unorm
    static let depthFormat = MTLPixelFormat.depth32Float
    static let samples = 4
    static let sky = MTLClearColor(red: 0.80, green: 0.85, blue: 0.90, alpha: 1)

    private let pipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let shadowSampler: MTLSamplerState
    private let shadowMap: MTLTexture
    private let groundColour: MTLTexture

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    \(PreviewLight.shader)
    // The frame's view and projection, the sun's look for the shadow map,
    // where the tile goes (xyz) at what scale (w), toward the sun, and the
    // shadow's strength (x) with one texel of its map (y).
    struct U { float4x4 viewProjection; float4x4 sun; float4 place; float4 sunDirection; float4 shadow; };
    struct Out { float4 position [[position]]; float2 uv; float3 normal; float4 inSun; };
    vertex Out vs(uint vid [[vertex_id]], const device packed_float3* p [[buffer(0)]],
                  const device float2* uv [[buffer(1)]], const device packed_float3* n [[buffer(2)]],
                  constant U& u [[buffer(3)]]) {
        float3 world = u.place.xyz + float3(p[vid]) * u.place.w;
        Out o;
        o.position = u.viewProjection * float4(world, 1);
        o.uv = uv[vid];
        o.normal = float3(n[vid]);
        // Pulled along the normal a little, against acne on the faces facing the sun.
        o.inSun = u.sun * float4(world + o.normal * 0.08, 1);
        return o;
    }
    // The sun's depth alone, for the shadow map.
    vertex float4 svs(uint vid [[vertex_id]], const device packed_float3* p [[buffer(0)]], constant U& u [[buffer(3)]]) {
        return u.sun * float4(u.place.xyz + float3(p[vid]) * u.place.w, 1);
    }
    fragment float4 fs(Out i [[stage_in]], texture2d<float> palette [[texture(0)]], depth2d<float> shadow [[texture(1)]],
                       sampler s [[sampler(0)]], sampler compare [[sampler(1)]], constant U& u [[buffer(3)]]) {
        float3 n = normalize(i.normal);
        float sunlit = previewSunlit(shadow, compare, i.inSun, dot(n, u.sunDirection.xyz), u.shadow.y);
        return float4(previewLit(palette.sample(s, i.uv).rgb, n, u.sunDirection.xyz, sunlit, u.shadow.x), 1);
    }
    """

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var sun: simd_float4x4
        var place: SIMD4<Float>
        var sunDirection: SIMD4<Float>
        var shadow: SIMD4<Float>
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
            let sd = MTLRenderPipelineDescriptor()
            sd.vertexFunction = library.makeFunction(name: "svs")
            sd.fragmentFunction = nil
            sd.depthAttachmentPixelFormat = .depth32Float
            shadowPipeline = try device.makeRenderPipelineState(descriptor: sd)
        } catch {
            NSLog("ImmersiveMapEditor: tile shaders: \(error)")
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
        guard let shadowMap = PreviewLight.makeShadowMap(device), let shadowSampler = PreviewLight.makeShadowSampler(device) else { return nil }
        self.shadowMap = shadowMap
        self.shadowSampler = shadowSampler
        let t = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))!
        let c = Colours.ground
        var px = SIMD4<UInt8>(UInt8(c.x * 255), UInt8(c.y * 255), UInt8(c.z * 255), 255)
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
        groundColour = t
    }

    /// What a z15 tile reaches from its centre, its corner and its
    /// overhang: the scene the sun's shadow map has to hold around the
    /// tiles' centres.
    private static let tileReach = 560.0

    /// Draws the ground and the tiles under the light: first the sun's
    /// depth into the shadow map, on a command buffer of its own (the
    /// view's pass is already begun), then the frame.
    func encode(_ enc: MTLRenderCommandEncoder, tiles library: TileLibrary, viewProjection vp: simd_float4x4) {
        guard let (c, reach) = library.extent else { return }
        let radius = Float(reach + Self.tileReach)
        let sun = PreviewLight.sunMatrix(centre: SIMD3(Float(c.x), 0, Float(-c.y)), radius: radius, room: 1.15)
        func uniforms(_ place: SIMD4<Float>) -> Uniforms {
            Uniforms(viewProjection: vp, sun: sun, place: place, sunDirection: SIMD4(PreviewLight.sun, 0),
                     shadow: SIMD4(PreviewLight.shadowStrength, 1 / Float(PreviewLight.shadowSize), 0, 0))
        }
        func place(_ t: TileModel) -> SIMD4<Float> { SIMD4(Float(t.centre.x), 0, Float(-t.centre.y), Float(t.scale)) }

        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        if let own = queue.makeCommandBuffer(), let s = own.makeRenderCommandEncoder(descriptor: pass) {
            s.setRenderPipelineState(shadowPipeline)
            s.setDepthStencilState(depth)
            s.setCullMode(.none)
            s.setDepthBias(2, slopeScale: 2, clamp: 0.01)
            for t in library.tiles {
                var u = uniforms(place(t))
                s.setVertexBuffer(t.positions, offset: 0, index: 0)
                s.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 3)
                s.drawIndexedPrimitives(type: .triangle, indexCount: t.indexCount, indexType: t.indexType,
                                        indexBuffer: t.indices, indexBufferOffset: 0)
            }
            s.endEncoding()
            own.commit()
            own.waitUntilCompleted()
        }

        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentSamplerState(shadowSampler, index: 1)
        enc.setFragmentTexture(shadowMap, index: 1)
        // The vector tile's ground, a plain plane just under the models,
        // with their shadows on it.
        let r = Float(reach + 400)
        let quad: [Float] = [-r, -0.05, r, r, -0.05, r, r, -0.05, -r, -r, -0.05, r, r, -0.05, -r, -r, -0.05, -r]
        let zeros = [Float](repeating: 0, count: 12)
        let ups: [Float] = [0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]
        var ground = uniforms(SIMD4(Float(c.x), 0, Float(-c.y), 1))
        enc.setVertexBuffer(device.makeBuffer(bytes: quad, length: quad.count * 4), offset: 0, index: 0)
        enc.setVertexBuffer(device.makeBuffer(bytes: zeros, length: zeros.count * 4), offset: 0, index: 1)
        enc.setVertexBuffer(device.makeBuffer(bytes: ups, length: ups.count * 4), offset: 0, index: 2)
        enc.setVertexBytes(&ground, length: MemoryLayout<Uniforms>.stride, index: 3)
        enc.setFragmentBytes(&ground, length: MemoryLayout<Uniforms>.stride, index: 3)
        enc.setFragmentTexture(groundColour, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        for t in library.tiles {
            var u = uniforms(place(t))
            enc.setVertexBuffer(t.positions, offset: 0, index: 0)
            enc.setVertexBuffer(t.uv0, offset: 0, index: 1)
            enc.setVertexBuffer(t.normals, offset: 0, index: 2)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 3)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 3)
            enc.setFragmentTexture(t.palette, index: 0)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: t.indexCount, indexType: t.indexType,
                                      indexBuffer: t.indices, indexBufferOffset: 0)
        }
    }

    /// The tiles drawn offscreen to a PNG, `width` by `height`.
    func snapshot(_ library: TileLibrary, viewProjection: simd_float4x4, to url: URL, width: Int, height: Int) throws {
        try Self.renderPNG(device: device, queue: queue, to: url, width: width, height: height) { enc in
            encode(enc, tiles: library, viewProjection: viewProjection)
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
