import AppKit
import GLTF
import MetalKit
import simd

/// One landmark model in 3D, as Modeling made it: its own materials and
/// atlas, a soft light from the sun's side so its form reads, over a plain
/// ground. The mouse as in the Tiles 3D view: drag to move, right-drag (or
/// option-drag) to turn and tilt, scroll or pinch to zoom; F frames it.
final class LandmarkView: MTKView {
    private let renderer: LandmarkRenderer
    private var controller = CameraController()
    private var lastDrag: NSPoint?
    private var turning = false
    /// The model shown, and the one on its way.
    private(set) var url: URL?
    private var mesh: LandmarkRenderer.Model?
    /// What went wrong reading the model, or how big it is.
    var status: (String) -> Void = { _ in }

    /// nil without a Metal device.
    static func make() -> LandmarkView? {
        LandmarkRenderer().map(LandmarkView.init(renderer:))
    }

    private init(renderer: LandmarkRenderer) {
        self.renderer = renderer
        super.init(frame: .zero, device: renderer.device)
        colorPixelFormat = TileRenderer.colourFormat
        depthStencilPixelFormat = TileRenderer.depthFormat
        sampleCount = TileRenderer.samples
        clearColor = TileRenderer.sky
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    private var size: SIMD2<Double> { SIMD2(Double(bounds.width), Double(bounds.height)) }

    /// Shows a model: read off the main thread, then framed.
    func show(_ glb: URL?) {
        guard glb != url else { return }
        url = glb
        mesh = nil
        guard let glb else { return }
        let device = renderer.device
        status("Reading \(glb.lastPathComponent)…")
        Task.detached {
            let result = Result { try LandmarkRenderer.Model.load(glb, device: device) }
            await MainActor.run {
                guard self.url == glb else { return }
                switch result {
                case .success(let model):
                    self.mesh = model
                    self.frameModel()
                    let s = model.size
                    self.status(String(format: "%@: %dk triangles, %.0f × %.0f m, %.0f m high",
                                       glb.lastPathComponent, model.triangles / 1000, s.x, s.z, s.y))
                case .failure(let error):
                    self.status("Cannot read \(glb.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    /// A model rendered to a PNG without a window, framed as the view frames
    /// it: `--landmark-snapshot`.
    func snapshot(_ glb: URL, to out: URL, width: Int, height: Int) throws {
        mesh = try LandmarkRenderer.Model.load(glb, device: renderer.device)
        frameModel()
        let vp = controller.camera.viewProjection(aspect: Double(width) / Double(height))
        try TileRenderer.renderPNG(device: renderer.device, queue: renderer.queue, to: out, width: width, height: height) { enc in
            renderer.encode(enc, model: mesh, viewProjection: vp)
        }
    }

    func frameModel() {
        guard let mesh else { return }
        let c = mesh.centre, s = mesh.size
        controller.camera.frame(centre: SIMD2(c.x, -c.z), span: max(s.x, s.y, s.z) * 1.6 + 20)
        controller.camera.target.y = c.y * 0.5
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
        turning = event.modifierFlags.contains(.option)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (dx, dy) = drag(event) else { return }
        controller.drag(dx, dy, turning: turning, size: size, flying: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let (dx, dy) = drag(event) else { return }
        controller.drag(dx, dy, turning: true, size: size, flying: false)
    }

    private func drag(_ event: NSEvent) -> (Double, Double)? {
        guard let last = lastDrag else { return nil }
        let now = event.locationInWindow
        lastDrag = now
        return (Double(now.x - last.x), Double(now.y - last.y))
    }

    private func point(_ event: NSEvent) -> SIMD2<Double> {
        let p = convert(event.locationInWindow, from: nil)
        return SIMD2(Double(p.x), Double(p.y))
    }

    override func scrollWheel(with event: NSEvent) {
        _ = controller.scroll(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                              at: point(event), size: size, flying: false)
    }

    override func magnify(with event: NSEvent) {
        controller.magnify(Double(event.magnification), at: point(event), size: size)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 3, !event.modifierFlags.contains(.command) { frameModel() } else { super.keyDown(with: event) }
    }
}

extension LandmarkView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = renderer.queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let aspect = max(Double(bounds.width), 1) / max(Double(bounds.height), 1)
        renderer.encode(enc, model: mesh, viewProjection: controller.camera.viewProjection(aspect: aspect))
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Draws a landmark model: each part with its texture (or its colour), lit
/// softly by a sun from `SUN_FROM`'s side, over a ground plane.
final class LandmarkRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let white: MTLTexture

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
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
    """

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var colour: SIMD4<Float>
        var sun: SIMD4<Float>
    }

    /// A model on the GPU: one buffer of vertices per part, with its texture.
    struct Model {
        struct Part { let vertices: MTLBuffer; let count: Int; let texture: MTLTexture?; let colour: SIMD4<Float> }
        let parts: [Part]
        let ground: MTLBuffer
        let centre: SIMD3<Double>
        let size: SIMD3<Double>
        let triangles: Int

        static func load(_ url: URL, device: MTLDevice) throws -> Model {
            let loader = MTKTextureLoader(device: device)
            var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
            var parts: [Part] = []
            var triangles = 0
            for part in try GLTF.primitives(url) {
                // The build's +Z up (east, north, up) back to the view's +Y up,
                // -Z north, as the tiles are drawn.
                let tris = part.tris.map { SIMD3($0.x, $0.z, -$0.y) }
                var v: [Float] = []
                v.reserveCapacity(tris.count * 8)
                for t in stride(from: 0, to: tris.count - 2, by: 3) {
                    let a = tris[t], b = tris[t + 1], c = tris[t + 2]
                    let n = simd_normalize(simd_cross(b - a, c - a))
                    for k in 0..<3 {
                        let p = tris[t + k]
                        lo = simd_min(lo, p)
                        hi = simd_max(hi, p)
                        let uv = part.uvs?[t + k] ?? .zero
                        v += [Float(p.x), Float(p.y), Float(p.z), Float(n.x), Float(n.y), Float(n.z), Float(uv.x), Float(uv.y)]
                    }
                }
                guard !v.isEmpty, let buffer = device.makeBuffer(bytes: v, length: v.count * 4) else { continue }
                let texture = part.material.image.flatMap {
                    try? loader.newTexture(data: $0, options: [.SRGB: false, .generateMipmaps: true,
                                                               .textureUsage: MTLTextureUsage.shaderRead.rawValue])
                }
                let f = part.material.factor.map(Float.init) + [1, 1, 1, 1]
                parts.append(Part(vertices: buffer, count: v.count / 8, texture: texture, colour: SIMD4(f[0], f[1], f[2], 1)))
                triangles += v.count / 24
            }
            guard !parts.isEmpty else { throw TileModel.Failure.glb("no triangles") }
            // The ground: a square under the model, a little below its foot.
            let c = (lo + hi) / 2, r = Float(max(hi.x - lo.x, hi.z - lo.z) * 1.5 + 40)
            let (gx, gy, gz) = (Float(c.x), Float(lo.y) - 0.02, Float(c.z))
            let g: [Float] = [
                gx - r, gy, gz - r, 0, 1, 0, 0, 0, gx - r, gy, gz + r, 0, 1, 0, 0, 0, gx + r, gy, gz + r, 0, 1, 0, 0, 0,
                gx - r, gy, gz - r, 0, 1, 0, 0, 0, gx + r, gy, gz + r, 0, 1, 0, 0, 0, gx + r, gy, gz - r, 0, 1, 0, 0, 0,
            ]
            return Model(parts: parts, ground: device.makeBuffer(bytes: g, length: g.count * 4)!,
                         centre: c, size: hi - lo, triangles: triangles)
        }
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
        s.mipFilter = .linear
        s.sAddressMode = .repeat
        s.tAddressMode = .repeat
        sampler = device.makeSamplerState(descriptor: s)!
        let w = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white = device.makeTexture(descriptor: w)!
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8](repeating: 255, count: 4),
                      bytesPerRow: 4)
    }

    func encode(_ enc: MTLRenderCommandEncoder, model: Model?, viewProjection: simd_float4x4) {
        guard let model else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        enc.setFragmentSamplerState(sampler, index: 0)
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
        draw(model.ground, 6, nil, SIMD4(0.86, 0.85, 0.82, 1))
        for p in model.parts { draw(p.vertices, p.count, p.texture, p.colour) }
    }
}
