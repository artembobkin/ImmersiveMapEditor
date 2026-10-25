import AppKit
import Geometry
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
    /// What to show: a model's GLB, or a landmark's OSM buildings as boxes
    /// while it has no model.
    enum Source: Equatable {
        case model(URL)
        case boxes(id: String, [TileLandmark.Box])

        static func == (a: Source, b: Source) -> Bool {
            switch (a, b) {
            case let (.model(x), .model(y)): x == y
            case let (.boxes(x, _), .boxes(y, _)): x == y
            default: false
            }
        }
    }

    /// What is shown, and what is on its way.
    private(set) var source: Source?
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

    /// Shows a model or boxes: made off the main thread, then framed.
    func show(_ next: Source?) {
        guard next != source else { return }
        source = next
        mesh = nil
        guard let next else { return }
        let device = renderer.device
        let name: String
        switch next {
        case .model(let url): name = url.lastPathComponent
        case .boxes: name = "OSM boxes"
        }
        status("Reading \(name)…")
        Task.detached {
            let result = Result {
                switch next {
                case .model(let url): try LandmarkRenderer.Model.load(url, device: device)
                case .boxes(_, let boxes): try LandmarkRenderer.Model.extruded(boxes, device: device)
                }
            }
            await MainActor.run {
                guard self.source == next else { return }
                switch result {
                case .success(let model):
                    self.mesh = model
                    self.frameModel()
                    let s = model.size
                    self.status(String(format: "%@: %dk triangles, %.0f × %.0f m, %.0f m high",
                                       name, model.triangles / 1000, s.x, s.z, s.y))
                case .failure(let error):
                    self.status("Cannot read \(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// A model rendered to a PNG without a window, framed as the view frames
    /// it: `--landmark-snapshot`.
    func snapshot(_ glb: URL, to out: URL, width: Int, height: Int) throws {
        source = .model(glb)
        mesh = try LandmarkRenderer.Model.load(glb, device: renderer.device)
        frameModel()
        let vp = controller.camera.viewProjection(aspect: Double(width) / Double(height))
        try TileRenderer.renderPNG(device: renderer.device, queue: renderer.queue, to: out, width: width, height: height) { enc in
            renderer.encode(enc, model: mesh, viewProjection: vp)
        }
    }

    /// A model, or boxes, rendered from around and above to PNGs in `dir`
    /// without a window: what the landmarks' agent compares with photos.
    /// Returns the files, named by where they look from.
    func views(_ next: Source, to dir: URL, width: Int = 1024, height: Int = 768) throws -> [URL] {
        source = next
        switch next {
        case .model(let url): mesh = try LandmarkRenderer.Model.load(url, device: renderer.device)
        case .boxes(_, let boxes): mesh = try LandmarkRenderer.Model.extruded(boxes, device: renderer.device)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        // From the south, east, north, west, at eye level and a slant, and
        // from straight above (north up).
        let shots: [(String, Double, Double)] = [("from-south", 180, -12), ("from-east", 90, -12), ("from-north", 0, -12),
                                                 ("from-west", 270, -12), ("from-south-west", 225, -35), ("from-north-east", 45, -35),
                                                 ("from-above", 0, -89.9)]
        for (name, from, pitch) in shots {
            frameModel()
            controller.camera.yaw = (from + 180).truncatingRemainder(dividingBy: 360)
            controller.camera.pitch = pitch
            controller.camera.distance *= pitch < -80 ? 1.1 : 0.9
            let vp = controller.camera.viewProjection(aspect: Double(width) / Double(height))
            let url = dir.appendingPathComponent("\(name).png")
            try TileRenderer.renderPNG(device: renderer.device, queue: renderer.queue, to: url, width: width, height: height) { enc in
                renderer.encode(enc, model: mesh, viewProjection: vp)
            }
            out.append(url)
        }
        return out
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
            return try make(parts: parts, lo: lo, hi: hi, triangles: triangles, device: device)
        }

        /// Boxes extruded from outlines, as a map of OSM data shows
        /// buildings: walls light, roofs a little darker.
        static func extruded(_ boxes: [TileLandmark.Box], device: MTLDevice) throws -> Model {
            var walls: [Float] = [], roofs: [Float] = []
            var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
            // East, up, south: the view's axes.
            func add(_ v: inout [Float], _ p: SIMD3<Double>, _ n: SIMD3<Double>) {
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
                v += [Float(p.x), Float(p.y), Float(p.z), Float(n.x), Float(n.y), Float(n.z), 0, 0]
            }
            func at(_ q: Vec2, _ h: Double) -> SIMD3<Double> { SIMD3(q.x, h, -q.y) }
            for box in boxes {
                for rings in box.polygons where !rings.isEmpty && rings[0].count >= 3 {
                    for ring in rings {
                        for i in ring.indices {
                            let a = ring[i], b = ring[(i + 1) % ring.count]
                            let d = b - a
                            guard simd_length(d) > 1e-6 else { continue }
                            let n = simd_normalize(SIMD3(d.y, 0, d.x))
                            let (a0, b0, a1, b1) = (at(a, box.base), at(b, box.base), at(a, box.top), at(b, box.top))
                            for p in [a0, b0, b1, a0, b1, a1] { add(&walls, p, n) }
                        }
                    }
                    let shape = Geometry.polygon(rings[0].map { P2($0.x, $0.y) }, holes: rings.dropFirst().map { $0.map { P2($0.x, $0.y) } })
                    for t in shape.constrainedDelaunay() where t.count == 3 {
                        for p in t { add(&roofs, at(Vec2(p.x, p.y), box.top), SIMD3(0, 1, 0)) }
                    }
                }
            }
            var parts: [Part] = []
            for (v, colour) in [(walls, SIMD4<Float>(0.86, 0.84, 0.80, 1)), (roofs, SIMD4<Float>(0.66, 0.66, 0.70, 1))] where !v.isEmpty {
                parts.append(Part(vertices: device.makeBuffer(bytes: v, length: v.count * 4)!, count: v.count / 8,
                                  texture: nil, colour: colour))
            }
            return try make(parts: parts, lo: lo, hi: hi, triangles: (walls.count + roofs.count) / 24, device: device)
        }

        /// The model of its parts, over a ground plane under its foot.
        private static func make(parts: [Part], lo: SIMD3<Double>, hi: SIMD3<Double>, triangles: Int,
                                 device: MTLDevice) throws -> Model {
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
