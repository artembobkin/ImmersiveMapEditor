import AppKit
import Geometry
import GLTF
import MetalKit
import simd
import TileKit

/// Draws a landmark model: each part with its texture (or its colour), lit
/// softly by a sun from `SUN_FROM`'s side, over a ground plane.
final class LandmarkRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let litPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let shadowSampler: MTLSamplerState
    private let white: MTLTexture
    private let shadowMap: MTLTexture

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    \(PreviewLight.shader)
    struct V { packed_float3 position; packed_float3 normal; float2 uv; };
    struct U { float4x4 viewProjection; float4 colour; float4 sun; };
    struct Out { float4 position [[position]]; float3 normal; float2 uv; };
    vertex Out vs(uint vid [[vertex_id]], const device V* v [[buffer(0)]], constant U& u [[buffer(1)]]) {
        Out o;
        o.position = u.viewProjection * float4(float3(v[vid].position), 1);
        o.normal = float3(v[vid].normal);
        o.uv = v[vid].uv;
        return o;
    }
    fragment float4 fs(Out i [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]],
                       constant U& u [[buffer(1)]]) {
        float3 n = normalize(i.normal);
        float light = 0.62 + 0.38 * max(dot(n, u.sun.xyz), 0.0) + 0.08 * n.y;
        return float4(t.sample(s, i.uv).rgb * u.colour.rgb * light, 1);
    }

    // The model in its palette's colours under the previews' light: the
    // sun with its shadow (a shadow map from the sun) over an ambient
    // light, as PreviewLight has it.
    struct LV { packed_float3 position; packed_float3 normal; packed_float3 colour; packed_float2 uv; };
    struct LU { float4x4 viewProjection; float4x4 sun; float4 sunDirection; float4 shadow; float4 colour; };
    struct LOut { float4 position [[position]]; float3 normal; float3 colour; float2 uv; float4 inSun; };
    vertex LOut lvs(uint vid [[vertex_id]], const device LV* v [[buffer(0)]], constant LU& u [[buffer(1)]]) {
        LOut o;
        float4 p = float4(float3(v[vid].position), 1);
        o.position = u.viewProjection * p;
        o.normal = float3(v[vid].normal);
        o.colour = float3(v[vid].colour);
        o.uv = float2(v[vid].uv);
        // Pulled along the normal a little, against acne on the faces facing the sun.
        o.inSun = u.sun * float4(p.xyz + o.normal * 0.08, 1);
        return o;
    }
    vertex float4 svs(uint vid [[vertex_id]], const device LV* v [[buffer(0)]], constant LU& u [[buffer(1)]]) {
        return u.sun * float4(float3(v[vid].position), 1);
    }
    fragment float4 lfs(LOut i [[stage_in]], depth2d<float> shadow [[texture(1)]], sampler sc [[sampler(1)]],
                        constant LU& u [[buffer(1)]]) {
        if (u.shadow.w > 0.5) return float4(u.colour.rgb, 1);   // the wireframe's lines
        float3 n = normalize(i.normal);
        // The ground takes the uniform's colour, the model its own.
        float3 c = u.colour.a > 0.5 ? i.colour : u.colour.rgb;
        float sunlit = previewSunlit(shadow, sc, i.inSun, dot(n, u.sunDirection.xyz), u.shadow.y);
        return float4(previewLit(c, n, u.sunDirection.xyz, sunlit, u.shadow.x), 1);
    }
    """

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var colour: SIMD4<Float>
        var sun: SIMD4<Float>
    }

    private struct LitUniforms {
        var viewProjection: simd_float4x4
        var sun: simd_float4x4
        var sunDirection: SIMD4<Float>
        /// Strength, a texel of the shadow map, 0, and 1 for the wireframe's lines.
        var shadow: SIMD4<Float>
        /// The ground's colour, alpha 0; alpha 1 takes the model's own.
        var colour: SIMD4<Float>
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
            d.colorAttachments[0].pixelFormat = TileRenderer.colourFormat
            d.depthAttachmentPixelFormat = TileRenderer.depthFormat
            d.rasterSampleCount = TileRenderer.samples
            pipeline = try device.makeRenderPipelineState(descriptor: d)
            d.vertexFunction = library.makeFunction(name: "lvs")
            d.fragmentFunction = library.makeFunction(name: "lfs")
            litPipeline = try device.makeRenderPipelineState(descriptor: d)
            let sd = MTLRenderPipelineDescriptor()
            sd.vertexFunction = library.makeFunction(name: "svs")
            sd.fragmentFunction = nil
            sd.depthAttachmentPixelFormat = .depth32Float
            shadowPipeline = try device.makeRenderPipelineState(descriptor: sd)
        } catch {
            NSLog("ImmersiveMapEditor: landmark shaders: \(error)")
            return nil
        }
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        depth = device.makeDepthStencilState(descriptor: ds)!
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.mipFilter = ProcessInfo.processInfo.environment["LANDMARK_NO_MIPS"] == nil ? .linear : .notMipmapped
        s.sAddressMode = .repeat
        s.tAddressMode = .repeat
        sampler = device.makeSamplerState(descriptor: s)!
        guard let shadowMap = PreviewLight.makeShadowMap(device), let shadowSampler = PreviewLight.makeShadowSampler(device) else { return nil }
        self.shadowMap = shadowMap
        self.shadowSampler = shadowSampler
        let w = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white = device.makeTexture(descriptor: w)!
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8](repeating: 255, count: 4),
                      bytesPerRow: 4)
    }

    /// Draws the model under the previews' light: first the shadow map from
    /// the sun (an orthographic look at the model along the sun's rays),
    /// then the ground plain with the shadow on it and the model in its
    /// colours, lit.
    func encodeLit(_ enc: MTLRenderCommandEncoder, model: LitModel, viewProjection: simd_float4x4, wireframe: Bool) {
        let c = SIMD3<Float>(Float(model.centre.x), Float(model.centre.y), Float(model.centre.z))
        let radius = Float(simd_length(model.size) / 2) + 2
        var uniforms = LitUniforms(viewProjection: viewProjection, sun: PreviewLight.sunMatrix(centre: c, radius: radius),
                                   sunDirection: SIMD4(PreviewLight.sun, 0),
                                   shadow: SIMD4(PreviewLight.shadowStrength, 1 / Float(PreviewLight.shadowSize), 1, 0),
                                   colour: SIMD4(0.86, 0.85, 0.82, 0))
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        // The view's pass is already begun on its buffer, so the shadow
        // pass goes on a buffer of its own, committed and done first.
        if let own = queue.makeCommandBuffer(), let s = own.makeRenderCommandEncoder(descriptor: pass) {
            s.setRenderPipelineState(shadowPipeline)
            s.setDepthStencilState(depth)
            s.setCullMode(.none)
            s.setDepthBias(2, slopeScale: 2, clamp: 0.01)
            s.setVertexBuffer(model.vertices, offset: 0, index: 0)
            s.setVertexBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
            s.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: model.count)
            s.endEncoding()
            own.commit()
            own.waitUntilCompleted()
        }
        enc.setRenderPipelineState(litPipeline)
        enc.setDepthStencilState(depth)
        enc.setFragmentSamplerState(shadowSampler, index: 1)
        enc.setFragmentTexture(shadowMap, index: 1)
        enc.setFrontFacing(.counterClockwise)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
        enc.setCullMode(.none)
        enc.setVertexBuffer(model.ground, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        uniforms.colour.w = 1
        enc.setVertexBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
        enc.setCullMode(.back)
        enc.setVertexBuffer(model.vertices, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: model.count)
        if wireframe {
            enc.setTriangleFillMode(.lines)
            enc.setDepthBias(-1, slopeScale: -1, clamp: 0)
            uniforms.colour = SIMD4(0.12, 0.1, 0.1, 0)
            uniforms.shadow.w = 1
            enc.setVertexBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: model.count)
            enc.setTriangleFillMode(.fill)
            enc.setDepthBias(0, slopeScale: 0, clamp: 0)
        }
        // The axes: east red, north green, up blue.
        enc.setVertexBuffer(model.axes, offset: 0, index: 0)
        uniforms.shadow.w = 1
        let axisColours: [SIMD4<Float>] = [SIMD4(0.85, 0.2, 0.2, 0), SIMD4(0.2, 0.7, 0.25, 0), SIMD4(0.2, 0.4, 0.9, 0)]
        var start = 0
        for (k, colour) in axisColours.enumerated() {
            uniforms.colour = colour
            enc.setVertexBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<LitUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: start, vertexCount: model.axisCounts[k])
            start += model.axisCounts[k]
        }
        enc.setCullMode(.none)
    }

    /// Draws the model shaded, and over it its wireframe when asked. A
    /// model's back faces are culled, as the engine culls them: a shell
    /// shows only its outside, and a face turned in shows as a hole.
    func encode(_ enc: MTLRenderCommandEncoder, model: Model?, viewProjection: simd_float4x4, wireframe: Bool = false, cull: Bool = false) {
        guard let model else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFrontFacing(.counterClockwise)
        // The sun from the south-west (SUN_FROM 225), high: +X east, -Z north.
        let sun = simd_normalize(SIMD3<Float>(-0.5, 0.9, 0.5))
        func draw(_ buffer: MTLBuffer, _ count: Int, _ texture: MTLTexture?, _ colour: SIMD4<Float>) {
            var u = Uniforms(viewProjection: viewProjection, colour: colour, sun: SIMD4(sun, 0))
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentTexture(texture ?? white, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.setCullMode(.none)
        draw(model.ground, 6, nil, SIMD4(0.86, 0.85, 0.82, 1))
        enc.setCullMode(cull ? .back : .none)
        for p in model.parts { draw(p.vertices, p.count, p.texture, p.colour) }
        if wireframe {
            // The edges in dark lines, pulled a little toward the eye so they
            // win over the faces they lie on.
            enc.setTriangleFillMode(.lines)
            enc.setDepthBias(-1, slopeScale: -1, clamp: 0)
            for p in model.parts { draw(p.vertices, p.count, nil, SIMD4(0.12, 0.1, 0.1, 1)) }
            enc.setTriangleFillMode(.fill)
            enc.setDepthBias(0, slopeScale: 0, clamp: 0)
        }
        enc.setCullMode(.none)
    }
}
