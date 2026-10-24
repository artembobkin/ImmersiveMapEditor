import AppKit
import MetalKit
import simd

/// The built tiles in 3D (`Workspace.shown`), drawn every frame. A thin
/// view: the tiles come from a `TileLibrary`, are drawn by a
/// `TileRenderer`, through the eye of a `CameraController`, and this view
/// only hands it AppKit's input (which SwiftUI has no API for).
///
/// The mouse as in the engine: drag to move over the ground, right-drag (or
/// option-drag) to turn and tilt, scroll or pinch to zoom toward the cursor.
/// Tab flies (W A S D, Q down, E up, shift faster, right-drag to look,
/// scroll for speed). F frames the tiles, L the light map.
final class TileView: MTKView {
    let model: Workspace
    private let renderer: TileRenderer
    private var library = TileLibrary()
    private var controller = CameraController()
    private var lastDrag: NSPoint?
    /// The left button turns instead of moving while option was held at its
    /// press, as in the engine.
    private var turning = false

    init?(model: Workspace) {
        guard let renderer = TileRenderer() else { return nil }
        self.model = model
        self.renderer = renderer
        super.init(frame: .zero, device: renderer.device)
        colorPixelFormat = TileRenderer.colourFormat
        depthStencilPixelFormat = TileRenderer.depthFormat
        sampleCount = TileRenderer.samples
        clearColor = TileRenderer.sky
        // Drawn every frame: flight moves it, and whatever of the workspace it
        // shows is read as it draws.
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    private var size: SIMD2<Double> { SIMD2(Double(bounds.width), Double(bounds.height)) }

    /// The tiles read again if the workspace's changed, framed when they are
    /// another set.
    private func refresh() {
        guard library.isStale(model) else { return }
        if library.reload(model, device: renderer.device) { frameTiles() }
    }

    /// The camera over the tiles shown, looking down at a slant.
    func frameTiles() {
        guard let (c, reach) = library.extent else { return }
        controller.camera.frame(centre: c, span: reach * 2 + 700)
    }

    /// The tiles shown, rendered to a PNG without a window: `--snapshot`.
    func snapshot(to url: URL, width: Int, height: Int) throws {
        refresh()
        try renderer.snapshot(library, viewProjection: controller.camera.viewProjection(aspect: Double(width) / Double(height)),
                              lightMap: model.showLightMap, to: url, width: width, height: height)
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
        turning = event.modifierFlags.contains(.option)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (dx, dy) = drag(event) else { return }
        controller.drag(dx, dy, turning: turning, size: size, flying: model.flying)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let (dx, dy) = drag(event) else { return }
        controller.drag(dx, dy, turning: true, size: size, flying: model.flying)
    }

    /// The mouse's move since the last event, in points.
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
        if let speed = controller.scroll(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                         at: point(event), size: size, flying: model.flying) {
            model.tileStatus = String(format: "Flight speed %.0f m/s", speed)
        }
    }

    override func magnify(with event: NSEvent) {
        controller.magnify(Double(event.magnification), at: point(event), size: size)
    }

    private static let flightKeys: [UInt16: CameraController.Key] = [
        13: .forward, 1: .back, 0: .left, 2: .right, 14: .up, 12: .down,     // W S A D E Q
    ]

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 48:                                    // tab
            model.flying.toggle()
            controller.setFlying(model.flying)
        case 3: frameTiles()                        // F
        case 37: model.showLightMap.toggle()        // L
        default:
            if let key = Self.flightKeys[event.keyCode], model.flying {
                controller.press(key)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if let key = Self.flightKeys[event.keyCode] { controller.release(key) }
    }
}

extension TileView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        refresh()
        controller.step(flying: model.flying, fast: NSEvent.modifierFlags.contains(.shift))
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = renderer.queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let aspect = max(Double(bounds.width), 1) / max(Double(bounds.height), 1)
        renderer.encode(enc, tiles: library, viewProjection: controller.camera.viewProjection(aspect: aspect),
                        lightMap: model.showLightMap)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
