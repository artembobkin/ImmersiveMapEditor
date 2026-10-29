import AppKit
import Geometry
import GLTF
import MetalKit
import simd
import TileKit

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
        /// A model lit as the engine lights it: its light baked with these
        /// settings (the Preview view).
        case lit(URL, Lighting.Settings)

        static func == (a: Source, b: Source) -> Bool {
            switch (a, b) {
            case let (.model(x), .model(y)): x == y
            case let (.boxes(x, _), .boxes(y, _)): x == y
            case let (.lit(x, s), .lit(y, t)): x == y && s == t
            default: false
            }
        }
    }

    /// What is shown, and what is on its way.
    private(set) var source: Source?
    private var mesh: LandmarkRenderer.Model?
    /// The model lit, when the source is `lit`.
    private var lit: LandmarkRenderer.LitModel?
    /// The engine's shadow of the sun on the lit model: how dark, 0 for none.
    var shadowStrength = 0.45 { didSet { renderer.shadowStrength = Float(shadowStrength) } }
    /// The camera's lens: its vertical field of view in degrees. Changed,
    /// the camera moves so the model stays the same size in the frame: the
    /// lens alone changes, as a photographer's would.
    var lens = 50.0 {
        didSet {
            guard lens > 1, lens < 179 else { lens = oldValue; return }
            controller.camera.distance *= tan(oldValue / 2 * .pi / 180) / tan(lens / 2 * .pi / 180)
            controller.camera.fovDegrees = lens
        }
    }
    /// The wireframe over the shading, and back faces culled (a model's,
    /// not the OSM boxes': their winding is not kept).
    var wireframe = false
    private var cull: Bool { if case .model = source { return true } else { return false } }
    /// What went wrong reading the model, or how big it is.
    var status: (String) -> Void = { _ in }
    /// The camera as the headless render takes it, whenever it changes:
    /// "X Y Z HEADING PITCH HFOV W H", the eye in the build's metres (X
    /// east, Y north, Z up), the heading a compass bearing, the pitch up
    /// positive, the lens its horizontal field of view, the drawable's
    /// size (the user, 2026-10-29: shown in the viewport so a view can be
    /// rendered again exactly, for a check).
    var camera: (String) -> Void = { _ in }
    private var lastCamera = ""
    /// The axes' labels at their places on the screen (points of the view),
    /// whenever the camera moves; empty when a label is behind the camera.
    var labels: ([ViewLabel]) -> Void = { _ in }

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
    /// With `again`, the same landmark read again (its model rebuilt by the
    /// agent): the camera stays where the user put it.
    func show(_ next: Source?, again: Bool = false) {
        guard again || next != source else { return }
        let keepCamera = (again && next == source && mesh != nil) || sameModel(next)
        source = next
        guard let next else {
            mesh = nil
            lit = nil
            return
        }
        let device = renderer.device
        let name: String
        switch next {
        case .model(let url), .lit(let url, _): name = url.lastPathComponent
        case .boxes: name = "OSM boxes"
        }
        if case .lit = next { status("Baking the light of \(name)…") } else { status("Reading \(name)…") }
        Task.detached {
            let result = Result { () throws -> LandmarkRenderer.Model in
                switch next {
                case .model(let url): return try LandmarkRenderer.Model.load(url, device: device)
                case .boxes(_, let boxes): return try LandmarkRenderer.Model.extruded(boxes, device: device)
                case .lit(let url, let settings):
                    let started = Date()
                    let baked = try LandmarkLight.bake(url, settings: settings)
                    let model = try LandmarkRenderer.LitModel.make(baked, device: device)
                    return model.plain(String(format: ", light %d px in %.1f s", baked.size, Date().timeIntervalSince(started)))
                }
            }
            await MainActor.run {
                guard self.source == next else { return }
                switch result {
                case .success(let model):
                    self.mesh = model
                    self.lit = model.lit
                    if !keepCamera { self.frameModel() }
                    let s = model.size
                    self.status(String(format: "%@: %dk triangles, %.0f × %.0f m, %.0f m high%@",
                                       name, model.triangles / 1000, s.x, s.z, s.y, model.note))
                case .failure(let error):
                    self.status("Cannot read \(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Whether `next` shows the same model as now, lit or not (the light
    /// baked again): the camera stays.
    private func sameModel(_ next: Source?) -> Bool {
        guard mesh != nil, let next, let source else { return false }
        switch (source, next) {
        case let (.lit(a, _), .lit(b, _)), let (.model(a), .lit(b, _)), let (.lit(a, _), .model(b)): return a == b
        default: return false
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
            renderer.encode(enc, model: mesh, viewProjection: vp, cull: cull)
        }
    }

    /// A model, or boxes, rendered from around and above to PNGs in `dir`
    /// without a window: what the landmarks' agent compares with photos.
    /// Returns the files, named by where they look from.
    func views(_ next: Source, to dir: URL, width: Int = 1024, height: Int = 768) throws -> [URL] {
        source = next
        mesh = try loadPlain(next)
        lit = try loadLit(next)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        // From the south, east, north, west, at eye level and a slant, and
        // from straight above (north up).
        let shots: [(String, Double, Double)] = [("from-south", 180, -12), ("from-east", 90, -12), ("from-north", 0, -12),
                                                 ("from-west", 270, -12), ("from-south-west", 225, -35), ("from-north-east", 45, -35),
                                                 ("from-above", 0, -89.9)]
        for (name, from, pitch) in shots {
            frameModel()
            // Looking down, a yaw of 0 puts north at the top.
            controller.camera.yaw = pitch < -80 ? 0 : (from + 180).truncatingRemainder(dividingBy: 360)
            controller.camera.pitch = pitch
            controller.camera.distance *= pitch < -80 ? 1.1 : 0.9
            let vp = controller.camera.viewProjection(aspect: Double(width) / Double(height))
            let url = dir.appendingPathComponent("\(name).png")
            try TileRenderer.renderPNG(device: renderer.device, queue: renderer.queue, to: url, width: width, height: height) { enc in
                encodeStill(enc, vp)
            }
            out.append(url)
        }
        return out
    }

    /// The model (or the boxes) seen as a photo's camera saw it: from `eye`
    /// (metres east, north and up of the landmark's centre), along `heading`
    /// (a compass bearing) tipped by `pitch` (degrees, up positive), `hfov`
    /// degrees wide, to a PNG of `width` by `height` without a window.
    func look(_ next: Source, to out: URL, eye: SIMD3<Double>, heading: Double, pitch: Double, hfov: Double,
              width: Int, height: Int) throws {
        source = next
        mesh = try loadPlain(next)
        lit = try loadLit(next)
        let aspect = Double(width) / Double(height)
        controller.camera.yaw = heading
        controller.camera.pitch = pitch
        controller.camera.fovDegrees = 2 * atan(tan(hfov / 2 * .pi / 180) / aspect) * 180 / .pi
        controller.camera.distance = 100
        let e = SIMD3(eye.x, eye.z, -eye.y)
        controller.camera.target = e + controller.camera.forward * 100
        let vp = controller.camera.viewProjection(aspect: aspect)
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TileRenderer.renderPNG(device: renderer.device, queue: renderer.queue, to: out, width: width, height: height) { enc in
            encodeStill(enc, vp)
        }
        controller.camera.fovDegrees = lens
    }

    /// A source read as a plain model (a lit one unlit), for the renders
    /// without a window.
    private func loadPlain(_ next: Source) throws -> LandmarkRenderer.Model {
        switch next {
        case .model(let url), .lit(let url, _): try LandmarkRenderer.Model.load(url, device: renderer.device)
        case .boxes(_, let boxes): try LandmarkRenderer.Model.extruded(boxes, device: renderer.device)
        }
    }

    /// A lit source baked and read, nil for any other.
    private func loadLit(_ next: Source) throws -> LandmarkRenderer.LitModel? {
        guard case let .lit(url, settings) = next else { return nil }
        return try LandmarkRenderer.LitModel.make(try LandmarkLight.bake(url, settings: settings), device: renderer.device)
    }

    /// One frame without a window, lit when the source is.
    private func encodeStill(_ enc: MTLRenderCommandEncoder, _ vp: simd_float4x4) {
        if let lit {
            renderer.encodeLit(enc, model: lit, viewProjection: vp, wireframe: wireframe)
        } else {
            renderer.encode(enc, model: mesh, viewProjection: vp, cull: cull)
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
        let c = controller.camera, e = c.eye
        let hfov = 2 * atan(tan(c.fovDegrees / 2 * .pi / 180) * aspect) * 180 / .pi
        let line = String(format: "%.1f %.1f %.1f %.0f %.0f %.0f %d %d", e.x, -e.z, e.y, (c.yaw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360),
                          c.pitch, hfov, Int(view.drawableSize.width), Int(view.drawableSize.height))
        if line != lastCamera {
            lastCamera = line
            camera(line)
            if let lit {
                let vp = c.viewProjection(aspect: aspect)
                let w = Double(bounds.width), h = Double(bounds.height)
                labels(lit.labels.compactMap { text, p in
                    let clip = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
                    guard clip.w > 0.1 else { return nil }
                    let x = (Double(clip.x / clip.w) + 1) / 2 * w, y = (1 - Double(clip.y / clip.w)) / 2 * h
                    return ViewLabel(text: text, point: CGPoint(x: x, y: y))
                })
            }
        }
        if let lit {
            renderer.encodeLit(enc, model: lit, viewProjection: controller.camera.viewProjection(aspect: aspect), wireframe: wireframe)
        } else {
            renderer.encode(enc, model: mesh, viewProjection: controller.camera.viewProjection(aspect: aspect), wireframe: wireframe, cull: cull)
        }
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
    private let litPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let shadowSampler: MTLSamplerState
    private let white: MTLTexture
    private let shadowMap: MTLTexture
    static let shadowSize = 4096
    /// The engine's shadow of the sun: how dark it is where a surface is
    /// fully in shadow, with the engine's cool tint.
    var shadowStrength: Float = ProcessInfo.processInfo.environment["LANDMARK_SHADOW"].flatMap(Float.init) ?? 0.45
    static let shadowTint = SIMD3<Float>(0.88, 0.92, 1.0)

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

    // The model lit as the engine lights it: its palette tone times its
    // light map, times the sun's shadow (a shadow map from the sun, with
    // the engine's cool tint), no lighting of its own.
    // Packed throughout: 11 floats a vertex, as the buffer is laid.
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
    fragment float4 lfs(LOut i [[stage_in]], texture2d<float> light [[texture(0)]], depth2d<float> shadow [[texture(1)]],
                        sampler s [[sampler(0)]], sampler sc [[sampler(1)]], constant LU& u [[buffer(1)]]) {
        float3 n = normalize(i.normal);
        float3 c = i.colour * (u.colour.a > 0.5 ? light.sample(s, i.uv).rgb : u.colour.rgb);
        // Where the sun's shadow falls: a surface turned from the sun is in it whole.
        float facing = dot(n, u.sunDirection.xyz);
        float2 st = i.inSun.xy * float2(0.5, -0.5) + 0.5;
        float z = i.inSun.z - 0.0004;
        float lit = 0;
        for (int dx = -1; dx <= 1; dx++) for (int dy = -1; dy <= 1; dy++)
            lit += shadow.sample_compare(sc, st + float2(dx, dy) * u.shadow.y, z);
        lit /= 9;
        if (facing <= 0.02) lit = 0;
        if (st.x < 0 || st.x > 1 || st.y < 0 || st.y > 1) lit = 1;
        if (u.shadow.w > 0.5) return float4(u.colour.rgb, 1);   // the wireframe's lines
        // In full shadow a surface keeps (1 - strength) of its light, tinted
        // cool in the same measure: at 0 there is no shadow at all (the tint
        // used to show whole at any strength).
        float3 dark = mix(float3(1), float3(0.88, 0.92, 1.0), saturate(u.shadow.x * 2)) * (1 - u.shadow.x);
        float3 shaded = u.shadow.x > 0 ? mix(float3(1), dark, 1 - lit) : float3(1);
        return float4(c * shaded, 1);
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
        /// The ground's colour, alpha 0; alpha 1 takes the light map.
        var colour: SIMD4<Float>
    }

    /// A model lit: every triangle with its palette tone and its place in
    /// the light map, one buffer, and the light map as a texture.
    struct LitModel {
        let vertices: MTLBuffer
        let count: Int
        let light: MTLTexture
        let ground: MTLBuffer
        /// The axes beside the model: three arrows (a bar and a cone each,
        /// triangles) east, north and up from a corner outside its bounds
        /// on the ground, so they never cross it (the user, 2026-10-29),
        /// `axisCounts` vertices each; and the labels' places in the
        /// scene, X E, Y N, Z and the compass's other points.
        let axes: MTLBuffer
        let axisCounts: [Int]
        let labels: [(String, SIMD3<Float>)]
        let centre: SIMD3<Double>
        let size: SIMD3<Double>
        let triangles: Int
        /// Toward the sun, when the light baked has none: the engine's sun
        /// casts the shadows. Nil when the sun is baked in.
        let sun: SIMD3<Float>?

        static func make(_ r: LandmarkLight.Result, device: MTLDevice) throws -> LitModel {
            var v: [Float] = []
            v.reserveCapacity(r.triangles * 33)
            var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
            for t in 0..<r.triangles {
                // The build's east, north, up to the view's east, up, south.
                let p = (0..<3).map { SIMD3(r.positions[t * 9 + $0 * 3], r.positions[t * 9 + $0 * 3 + 2], -r.positions[t * 9 + $0 * 3 + 1]) }
                let n = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
                let c = (0..<3).map { Float(r.colours[t * 3 + $0]) / 255 }
                for k in 0..<3 {
                    lo = simd_min(lo, p[k])
                    hi = simd_max(hi, p[k])
                    // The map's row 0 is the north: V turned.
                    v += [Float(p[k].x), Float(p[k].y), Float(p[k].z), Float(n.x), Float(n.y), Float(n.z), c[0], c[1], c[2],
                          Float(r.uv1[t * 6 + k * 2]), Float(1 - r.uv1[t * 6 + k * 2 + 1])]
                }
            }
            guard !v.isEmpty, let buffer = device.makeBuffer(bytes: v, length: v.count * 4) else { throw TileModel.Failure.glb("no triangles") }
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: r.size, height: r.size, mipmapped: true)
            d.usage = [.shaderRead]
            guard let texture = device.makeTexture(descriptor: d) else { throw TileModel.Failure.glb("no texture") }
            var px = [UInt8](repeating: 255, count: r.size * r.size * 4)
            for i in 0..<(r.size * r.size) {
                px[i * 4] = r.light[i * 3]
                px[i * 4 + 1] = r.light[i * 3 + 1]
                px[i * 4 + 2] = r.light[i * 3 + 2]
            }
            texture.replace(region: MTLRegionMake2D(0, 0, r.size, r.size), mipmapLevel: 0, withBytes: px, bytesPerRow: r.size * 4)
            if let queue = device.makeCommandQueue(), let cmd = queue.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() {
                blit.generateMipmaps(for: texture)
                blit.endEncoding()
                cmd.commit()
                cmd.waitUntilCompleted()
            }
            let centre = (lo + hi) / 2
            let radius = Float(max(hi.x - lo.x, hi.z - lo.z) * 1.5 + 40)
            let (gx, gy, gz) = (Float(centre.x), Float(lo.y) - 0.02, Float(centre.z))
            var g: [Float] = []
            for (x, z) in [(-1, -1), (-1, 1), (1, 1), (-1, -1), (1, 1), (1, -1)] as [(Float, Float)] {
                g += [gx + x * radius, gy, gz + z * radius, 0, 1, 0, 1, 1, 1, 0, 0]
            }
            // The axes: arrows from the south-west corner, 8 m out, 20 m long.
            let o = SIMD3<Float>(Float(lo.x) - 8, Float(lo.y), Float(hi.z) + 8), len: Float = 20
            var a: [Float] = []
            var counts: [Int] = []
            for d in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, -1), SIMD3<Float>(0, 1, 0)] {
                let before = a.count
                arrow(&a, from: o, along: d, length: len)
                counts.append((a.count - before) / 11)
            }
            let labels: [(String, SIMD3<Float>)] = [("X  E", o + SIMD3(len + 3, 0, 0)), ("Y  N", o + SIMD3(0, 0, -len - 3)), ("Z", o + SIMD3(0, len + 3, 0)),
                                                    ("W", o + SIMD3(-6, 0, 0)), ("S", o + SIMD3(0, 0, 6))]
            return LitModel(vertices: buffer, count: v.count / 11, light: texture, ground: device.makeBuffer(bytes: g, length: g.count * 4)!,
                            axes: device.makeBuffer(bytes: a, length: a.count * 4)!, axisCounts: counts, labels: labels,
                            centre: centre, size: hi - lo, triangles: r.triangles, sun: r.sun)
        }

        /// An arrow: a bar 0.5 m across and a cone 4 m long, 1.4 m across,
        /// as triangles in the lit layout (11 floats a vertex).
        static func arrow(_ a: inout [Float], from o: SIMD3<Float>, along d: SIMD3<Float>, length: Float) {
            let helper: SIMD3<Float> = abs(d.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let u = simd_normalize(simd_cross(d, helper)), w = simd_cross(d, u)
            func put(_ p: SIMD3<Float>) { a += [p.x, p.y, p.z, 0, 1, 0, 1, 1, 1, 0, 0] }
            func tri(_ p: SIMD3<Float>, _ q: SIMD3<Float>, _ r: SIMD3<Float>) { put(p); put(q); put(r) }
            let n = 12, barR: Float = 0.25, coneR: Float = 0.7, coneLen: Float = 4
            let neck = o + d * (length - coneLen), tip = o + d * length
            func ring(_ c: SIMD3<Float>, _ r: Float, _ k: Int) -> SIMD3<Float> {
                let t = 2 * Float.pi * Float(k) / Float(n)
                return c + u * (r * cos(t)) + w * (r * sin(t))
            }
            for k in 0..<n {
                let k1 = (k + 1) % n
                tri(ring(o, barR, k), ring(o, barR, k1), ring(neck, barR, k1))
                tri(ring(o, barR, k), ring(neck, barR, k1), ring(neck, barR, k))
                tri(o, ring(o, barR, k1), ring(o, barR, k))
                tri(ring(neck, coneR, k), ring(neck, coneR, k1), tip)
                tri(neck, ring(neck, coneR, k1), ring(neck, coneR, k))
            }
        }

        /// As a plain model's record (its size, its count), for the view's
        /// status and framing.
        func plain(_ note: String) -> Model {
            Model(parts: [], ground: ground, centre: centre, size: size, triangles: triangles, lit: self, note: note)
        }
    }

    /// A model on the GPU: one buffer of vertices per part, with its texture.
    struct Model {
        struct Part { let vertices: MTLBuffer; let count: Int; let texture: MTLTexture?; let colour: SIMD4<Float> }
        let parts: [Part]
        let ground: MTLBuffer
        let centre: SIMD3<Double>
        let size: SIMD3<Double>
        let triangles: Int
        /// The same model lit, when it was baked.
        var lit: LitModel? = nil
        var note = ""

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
        let c = MTLSamplerDescriptor()
        c.minFilter = .linear
        c.magFilter = .linear
        c.compareFunction = .lessEqual
        c.sAddressMode = .clampToEdge
        c.tAddressMode = .clampToEdge
        shadowSampler = device.makeSamplerState(descriptor: c)!
        let sm = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: Self.shadowSize, height: Self.shadowSize, mipmapped: false)
        sm.usage = [.renderTarget, .shaderRead]
        sm.storageMode = .private
        shadowMap = device.makeTexture(descriptor: sm)!
        let w = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white = device.makeTexture(descriptor: w)!
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8](repeating: 255, count: 4),
                      bytesPerRow: 4)
    }

    /// Draws the model lit as the engine draws it: first the shadow map from
    /// the sun (an orthographic look at the model along the sun's rays),
    /// then the model, its tones times its light map times the shadow, and
    /// the ground plain with the shadow on it (the engine's ground is the
    /// vector tile, with no light of ours on it).
    func encodeLit(_ enc: MTLRenderCommandEncoder, model: LitModel, viewProjection: simd_float4x4, wireframe: Bool) {
        // The sun's look: orthographic over the model's bounds.
        let c = SIMD3<Float>(Float(model.centre.x), Float(model.centre.y), Float(model.centre.z))
        let radius = Float(simd_length(model.size) / 2) + 2
        let dir = model.sun ?? simd_normalize(SIMD3<Float>(-0.5, 0.707, 0.5))
        let eye = c + dir * (radius * 2)
        let f = -dir
        let r = simd_normalize(simd_cross(f, SIMD3<Float>(0, 1, 0)))
        let u = simd_cross(r, f)
        let view = simd_float4x4(rows: [SIMD4(r.x, r.y, r.z, -simd_dot(r, eye)), SIMD4(u.x, u.y, u.z, -simd_dot(u, eye)),
                                        SIMD4(-f.x, -f.y, -f.z, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
        // The ground's shadow reaches beyond the model: the map covers twice its radius.
        let ext = radius * 2.2, near: Float = 0.1, far = radius * 4.5
        let ortho = simd_float4x4(rows: [SIMD4(1 / ext, 0, 0, 0), SIMD4(0, 1 / ext, 0, 0),
                                         SIMD4(0, 0, -1 / (far - near), -near / (far - near)), SIMD4(0, 0, 0, 1)])
        let sun = ortho * view
        var uniforms = LitUniforms(viewProjection: viewProjection, sun: sun, sunDirection: SIMD4(dir, 0),
                                   shadow: SIMD4(model.sun == nil ? 0 : shadowStrength, 1 / Float(Self.shadowSize), 1, 0),
                                   colour: SIMD4(0.86, 0.85, 0.82, 0))
        if model.sun != nil, shadowStrength > 0 {
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = shadowMap
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .store
            // The view's pass is already begun on `buffer`, so the shadow
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
        }
        enc.setRenderPipelineState(litPipeline)
        enc.setDepthStencilState(depth)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentSamplerState(shadowSampler, index: 1)
        enc.setFragmentTexture(model.light, index: 0)
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

/// A label of the 3D view at a point of it, for an overlay.
struct ViewLabel: Identifiable, Equatable {
    var id: String { text }
    let text: String
    let point: CGPoint
}
