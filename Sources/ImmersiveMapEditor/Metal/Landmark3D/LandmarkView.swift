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
    /// A model placed in the tile: its file and its origin in the tile's
    /// metres, east, north and up.
    struct Placed: Equatable {
        let url: URL
        let origin: SIMD3<Double>
    }

    enum Source: Equatable {
        case model(URL)
        case boxes(id: String, [TileLandmark.Box])
        /// Every model of the tile together where the build places them,
        /// their palette alone, no build (the user, 2026-11-02: a quick look
        /// at all the models at once).
        case models([Placed])
        /// A model in its palette's colours under the previews' light
        /// (`PreviewLight`), over a ground with its shadow (the Preview view).
        case lit(URL)

        static func == (a: Source, b: Source) -> Bool {
            switch (a, b) {
            case let (.model(x), .model(y)): x == y
            case let (.boxes(x, _), .boxes(y, _)): x == y
            case let (.models(x), .models(y)): x == y
            case let (.lit(x), .lit(y)): x == y
            default: false
            }
        }
    }

    /// What is shown, and what is on its way.
    private(set) var source: Source?
    private var mesh: LandmarkRenderer.Model?
    /// The model lit, when the source is `lit`.
    private var lit: LandmarkRenderer.LitModel?
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
    private var cull: Bool {
        switch source {
        case .model, .models: return true
        default: return false
        }
    }
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
        case .model(let url), .lit(let url): name = url.lastPathComponent
        case .boxes: name = "OSM boxes"
        case .models(let placed): name = "\(placed.count) landmarks"
        }
        status("Reading \(name)…")
        Task.detached {
            let result = Result { () throws -> LandmarkRenderer.Model in
                switch next {
                case .model(let url): return try LandmarkRenderer.Model.load(url, device: device)
                case .boxes(_, let boxes): return try LandmarkRenderer.Model.extruded(boxes, device: device)
                case .models(let placed): return try LandmarkRenderer.Model.load(placed, device: device)
                case .lit(let url):
                    return try LandmarkRenderer.LitModel.make(try LandmarkTones.read(url), device: device).plain("")
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

    /// Whether `next` shows the same model as now, lit or not: the camera
    /// stays.
    private func sameModel(_ next: Source?) -> Bool {
        guard mesh != nil, let next, let source else { return false }
        switch (source, next) {
        case let (.lit(a), .lit(b)), let (.model(a), .lit(b)), let (.lit(a), .model(b)): return a == b
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
        case .model(let url), .lit(let url): try LandmarkRenderer.Model.load(url, device: renderer.device)
        case .boxes(_, let boxes): try LandmarkRenderer.Model.extruded(boxes, device: renderer.device)
        case .models(let placed): try LandmarkRenderer.Model.load(placed, device: renderer.device)
        }
    }

    /// A lit source read, nil for any other.
    private func loadLit(_ next: Source) throws -> LandmarkRenderer.LitModel? {
        guard case let .lit(url) = next else { return nil }
        return try LandmarkRenderer.LitModel.make(try LandmarkTones.read(url), device: renderer.device)
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
                let eye = SIMD3<Float>(c.eye)
                labels(lit.labels.compactMap { text, p in
                    let clip = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
                    guard clip.w > 0.1, !lit.hidden(from: eye, to: p) else { return nil }
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

/// A label of the 3D view at a point of it, for an overlay.
struct ViewLabel: Identifiable, Equatable {
    var id: String { text }
    let text: String
    let point: CGPoint
}
