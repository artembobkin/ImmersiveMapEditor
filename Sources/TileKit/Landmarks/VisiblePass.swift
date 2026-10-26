import Foundation
import Metal
import simd

/// What of a model an outside camera can see: the model drawn from many
/// places around and above it, each pixel holding the number of the
/// triangle it shows, back faces culled as the engine culls them; a
/// triangle shown in no picture is one no one sees (inside a shell, under
/// another face, in a sealed pocket), and goes. A window's recess, a
/// pilaster's side, a sill's top show from the right places and stay.
public enum VisiblePass {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Out { float4 position [[position]]; };
    vertex Out vs(const device packed_float3 *v [[buffer(0)]], constant float4x4 &vp [[buffer(1)]], uint id [[vertex_id]]) {
        Out o;
        o.position = vp * float4(float3(v[id]), 1);
        return o;
    }
    // Only the fragments that pass the depth test run (early tests), and
    // each marks its triangle seen: no picture to read back.
    [[early_fragment_tests]]
    fragment void fs(Out i [[stage_in]], uint prim [[primitive_id]], device atomic_uint *seen [[buffer(0)]]) {
        atomic_store_explicit(&seen[prim], 1u, memory_order_relaxed);
    }
    """

    /// The triangles seen, as a mask over `tris` (three corners each, X
    /// east, Y north, Z up), or nil when there is no GPU to ask.
    public static func visible(_ tris: [SIMD3<Double>], size: Int = 4096) -> [Bool]? {
        let count = tris.count / 3
        guard count > 0, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: source, options: nil),
              let vs = library.makeFunction(name: "vs"), let fs = library.makeFunction(name: "fs") else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vs
        d.fragmentFunction = fs
        d.depthAttachmentPixelFormat = .depth32Float
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: ds) else { return nil }
        // The model's corners as the view's floats: X east, Y up, -Z north.
        var floats: [Float] = []
        floats.reserveCapacity(tris.count * 3)
        var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
        for p in tris {
            floats += [Float(p.x), Float(p.z), Float(-p.y)]
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        guard let vbuf = device.makeBuffer(bytes: floats, length: floats.count * 4) else { return nil }
        let centre = (lo + hi) / 2, radius = max(simd_length(hi - lo) / 2, 1)
        let target = SIMD3<Float>(Float(centre.x), Float(centre.z), Float(-centre.y))
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: size, height: size, mipmapped: false)
        dd.usage = [.renderTarget]
        dd.storageMode = .private
        guard let depth = device.makeTexture(descriptor: dd),
              let flags = device.makeBuffer(length: count * 4, options: .storageModeShared) else { return nil }
        memset(flags.contents(), 0, count * 4)
        // From all around: far off at a slant and from high up, from straight
        // above, and close by at street level looking up (the undersides of
        // cornices, the heads of windows: what a walker sees).
        var views: [(eye: SIMD3<Float>, at: SIMD3<Float>, half: Float)] = []
        func far(_ azimuth: Double, _ elevation: Double) {
            let a = azimuth * .pi / 180, e = elevation * .pi / 180, dist = Float(radius * 3)
            let dir = SIMD3<Float>(Float(sin(a) * cos(e)), Float(sin(e)), Float(-cos(a) * cos(e)))
            views.append((target + dir * dist, target, atan(Float(radius) / dist) * 1.05))
        }
        far(0, 89.5)
        for e in [2.0, 10, 25, 45, 70] {
            let n = e < 30 ? 24 : 12
            for k in 0..<n { far(360 * Double(k) / Double(n), e) }
        }
        let ground = Float(lo.z), top = Float(hi.z)
        for k in 0..<24 {
            let a = 2 * Double.pi * Double(k) / 24, dist = Float(radius * 1.15)
            let eye = SIMD3<Float>(target.x + Float(sin(a)) * dist, ground + 1.7, target.z - Float(cos(a)) * dist)
            views.append((eye, SIMD3<Float>(target.x, ground + (top - ground) * 0.6, target.z), 0.9))
        }
        if let only = ProcessInfo.processInfo.environment["LANDMARK_VIS_VIEWS"], let n = Int(only) {
            // One view alone, to see what it sees.
            views = [views[min(n, views.count - 1)]]
        }
        for view in views {
            let eye = view.eye, half = view.half, dist = simd_length(view.at - eye)
            let f = simd_normalize(view.at - eye)
            let r = simd_normalize(simd_cross(f, SIMD3<Float>(0, 1, 0)))
            let u = simd_cross(r, f)
            let viewM = simd_float4x4(rows: [SIMD4(r.x, r.y, r.z, -simd_dot(r, eye)), SIMD4(u.x, u.y, u.z, -simd_dot(u, eye)),
                                             SIMD4(-f.x, -f.y, -f.z, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
            let near = max(0.3, dist - Float(radius) * 1.3), far = dist + Float(radius) * 1.3
            let ys = 1 / tan(half), zs = far / (near - far)
            let proj = simd_float4x4(rows: [SIMD4(ys, 0, 0, 0), SIMD4(0, ys, 0, 0), SIMD4(0, 0, zs, zs * near), SIMD4(0, 0, -1, 0)])
            var vp = proj * viewM
            let pass = MTLRenderPassDescriptor()
            pass.renderTargetWidth = size
            pass.renderTargetHeight = size
            pass.defaultRasterSampleCount = 1
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .dontCare
            guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            enc.setRenderPipelineState(pipeline)
            enc.setDepthStencilState(depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.back)
            enc.setVertexBuffer(vbuf, offset: 0, index: 0)
            enc.setVertexBytes(&vp, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            enc.setFragmentBuffer(flags, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tris.count)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
        }
        let marks = flags.contents().assumingMemoryBound(to: UInt32.self)
        return (0..<count).map { marks[$0] != 0 }
    }
}
