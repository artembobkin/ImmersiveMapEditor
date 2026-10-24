import AppKit
import Combine
import MetalKit
import simd

/// The built tiles in 3D, drawn as the engine draws a model tile: the
/// palette times the light map, raw values, no lighting of its own, back
/// faces culled. The tiles picked on the map (`Workspace.shown`), each placed
/// and scaled as the engine places it, so the seams show as they will on the
/// map.
///
/// The mouse as in the engine: drag to move over the ground, right-drag (or
/// option-drag) to turn and tilt, scroll or pinch to zoom toward the cursor.
/// Flight (Tab):
/// W A S D, Q down, E up, shift faster, right-drag to look, scroll to change
/// speed. F frames the tiles.
final class TileView: MTKView {
    let model: Workspace
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let white: MTLTexture
    private let groundColour: MTLTexture
    private var tiles: [TileModel] = []
    private var loaded = -1
    private var watching: AnyCancellable?

    // The camera: a target, the distance to it and the way it looks.
    private var target = SIMD3<Double>(0, 0, 0)
    private var distance = 900.0
    private var yaw = 20.0        // degrees from north, clockwise
    private var pitch = -45.0     // degrees, down is negative
    private var keys = Set<UInt16>()
    private var speed = 30.0      // metres a second in flight
    private var lastFrame = CACurrentMediaTime()
    private var lastDrag: NSPoint?

    init?(model: Workspace) {
        self.model = model
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        let source = """
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
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "vs")
            d.fragmentFunction = library.makeFunction(name: "fs")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            d.depthAttachmentPixelFormat = .depth32Float
            d.rasterSampleCount = 4
            pipeline = try device.makeRenderPipelineState(descriptor: d)
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
        func solid(_ c: SIMD4<Float>) -> MTLTexture {
            let t = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))!
            var px = SIMD4<UInt8>(UInt8(c.x * 255), UInt8(c.y * 255), UInt8(c.z * 255), 255)
            t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
            return t
        }
        white = solid(SIMD4(1, 1, 1, 1))
        groundColour = solid(Colours.ground)
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = 4
        clearColor = MTLClearColor(red: 0.80, green: 0.85, blue: 0.90, alpha: 1)
        preferredFramesPerSecond = 60
        delegate = self
        watching = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Tiles

    /// Reads the tiles shown again, placed in the projection of their range.
    private func reload() {
        loaded = model.tilesRevision
        guard let device, let region = model.shownProjection else {
            tiles = []
            model.tileStatus = "No tiles shown: pick them on the Map"
            return
        }
        var made: [TileModel] = [], missing: [String] = []
        for t in model.shown {
            do {
                made.append(try TileModel.load(device: device, root: model.root, z: t.z, x: t.x, y: t.y, region: region))
            } catch {
                missing.append(t.name)
            }
        }
        let before = Set(tiles.map { "\($0.x)/\($0.y)" })
        tiles = made
        let triangles = made.reduce(0) { $0 + $1.triangles }
        model.tileStatus = "\(made.count) tiles, \(triangles / 1000)k triangles" +
            (missing.isEmpty ? "" : ". Not built: " + missing.joined(separator: ", "))
        if before != Set(made.map { "\($0.x)/\($0.y)" }) { frameTiles() }
    }

    private var shown: [TileModel] { tiles }

    /// The camera over the tiles shown, looking down at a slant.
    func frameTiles() {
        let list = shown.isEmpty ? tiles : shown
        guard !list.isEmpty else { return }
        let c = list.reduce(Vec2.zero) { $0 + $1.centre } / Double(list.count)
        let span = (list.map { ($0.centre - c).length }.max() ?? 0) * 2 + 700
        target = SIMD3(c.x, 0, -c.y)
        distance = span * 1.1
        pitch = -50
        yaw = 20
        needsDisplay = true
    }

    /// Draws the ground and the tiles shown.
    func encode(_ enc: MTLRenderCommandEncoder, _ vp: simd_float4x4) {
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setFragmentSamplerState(sampler, index: 0)
        struct U { var viewProjection: simd_float4x4; var place: SIMD4<Float> }

        // The vector tile's ground, a plain plane just under the models.
        let list = shown
        if let device, !list.isEmpty {
            let c = list.reduce(Vec2.zero) { $0 + $1.centre } / Double(list.count)
            let r = Float((list.map { ($0.centre - c).length }.max() ?? 0) + 400)
            let quad: [Float] = [-r, -0.05, r, r, -0.05, r, r, -0.05, -r, -r, -0.05, r, r, -0.05, -r, -r, -0.05, -r]
            let zeros = [Float](repeating: 0, count: 12)
            var u = U(viewProjection: vp, place: SIMD4(Float(c.x), 0, Float(-c.y), 1))
            enc.setVertexBuffer(device.makeBuffer(bytes: quad, length: quad.count * 4), offset: 0, index: 0)
            enc.setVertexBuffer(device.makeBuffer(bytes: zeros, length: zeros.count * 4), offset: 0, index: 1)
            enc.setVertexBuffer(device.makeBuffer(bytes: zeros, length: zeros.count * 4), offset: 0, index: 2)
            enc.setVertexBytes(&u, length: MemoryLayout<U>.stride, index: 3)
            enc.setFragmentTexture(groundColour, index: 0)
            enc.setFragmentTexture(white, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        for t in list {
            var u = U(viewProjection: vp, place: SIMD4(Float(t.centre.x), 0, Float(-t.centre.y), Float(t.scale)))
            enc.setVertexBuffer(t.positions, offset: 0, index: 0)
            enc.setVertexBuffer(t.uv0, offset: 0, index: 1)
            enc.setVertexBuffer(t.uv1, offset: 0, index: 2)
            enc.setVertexBytes(&u, length: MemoryLayout<U>.stride, index: 3)
            enc.setFragmentTexture(t.palette, index: 0)
            enc.setFragmentTexture(model.showLightMap ? t.light : white, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: t.indexCount, indexType: t.indexType,
                                      indexBuffer: t.indices, indexBufferOffset: 0)
        }
    }

    /// The view as it is, rendered to a PNG without a window: `--snapshot`.
    func snapshot(to url: URL, width: Int, height: Int) throws {
        if loaded != model.tilesRevision { reload() }
        guard let device, let buffer = queue.makeCommandBuffer() else { return }
        func texture(_ format: MTLPixelFormat, samples: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = samples > 1 || format == .depth32Float ? .private : .shared
            return device.makeTexture(descriptor: d)!
        }
        let colour = texture(.bgra8Unorm, samples: 4), resolved = texture(.bgra8Unorm, samples: 1)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colour
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = clearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = texture(.depth32Float, samples: 4)
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(enc, viewProjection(aspect: Double(width) / Double(height)))
        enc.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: width * height * 4)
        resolved.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32)!
        for i in 0..<(width * height) {
            rep.bitmapData![i * 4] = px[i * 4 + 2]
            rep.bitmapData![i * 4 + 1] = px[i * 4 + 1]
            rep.bitmapData![i * 4 + 2] = px[i * 4]
            rep.bitmapData![i * 4 + 3] = 255
        }
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// Puts the camera somewhere, for a snapshot.
    func place(target: SIMD3<Double>, distance: Double, yaw: Double, pitch: Double) {
        self.target = target
        self.distance = distance
        self.yaw = yaw
        self.pitch = pitch
    }

    // MARK: The camera

    private var forward: SIMD3<Double> {
        let p = pitch * .pi / 180, y = yaw * .pi / 180
        return SIMD3(cos(p) * sin(y), sin(p), -cos(p) * cos(y))
    }
    private var eye: SIMD3<Double> { target - forward * distance }

    private func viewProjection(aspect given: Double? = nil) -> simd_float4x4 {
        let f = forward
        let e = eye
        let right = simd_normalize(simd_cross(f, SIMD3(0, 1, 0)))
        let up = simd_cross(right, f)
        let view = simd_double4x4(rows: [
            SIMD4(right.x, right.y, right.z, -simd_dot(right, e)),
            SIMD4(up.x, up.y, up.z, -simd_dot(up, e)),
            SIMD4(-f.x, -f.y, -f.z, simd_dot(f, e)),
            SIMD4(0, 0, 0, 1),
        ])
        let aspect = given ?? max(Double(bounds.width), 1) / max(Double(bounds.height), 1)
        let fovy = 50.0 * .pi / 180
        // Near and far follow the height, so the street and the whole block
        // both keep their depth.
        let near = max(0.1, min(5, max(e.y, 1) * 0.02)), far = max(20000, distance * 10)
        let ys = 1 / tan(fovy / 2), xs = ys / aspect, zs = far / (near - far)
        let projection = simd_double4x4(rows: [
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, zs * near),
            SIMD4(0, 0, -1, 0),
        ])
        let m = projection * view
        return simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                       SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }

    /// Moves in flight: the keys held, for the time since the last frame.
    private func fly() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.1)
        lastFrame = now
        guard model.flying, !keys.isEmpty else { return }
        let f = forward
        let right = simd_normalize(simd_cross(f, SIMD3(0, 1, 0)))
        var move = SIMD3<Double>(0, 0, 0)
        if keys.contains(13) { move += f }          // W
        if keys.contains(1) { move -= f }           // S
        if keys.contains(2) { move += right }       // D
        if keys.contains(0) { move -= right }       // A
        if keys.contains(14) { move.y += 1 }        // E
        if keys.contains(12) { move.y -= 1 }        // Q
        guard simd_length(move) > 0 else { return }
        let fast = NSEvent.modifierFlags.contains(.shift) ? 4.0 : 1.0
        target += simd_normalize(move) * speed * fast * dt
    }

    // MARK: Input

    // The mouse as in the engine (MapGestureControllerMac): the left button
    // drags the ground, the right one turns (sideways) and tilts (up and
    // down), and so does the left one with option. In flight the right button
    // looks around from the eye.
    private var turning = false

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
        turning = event.modifierFlags.contains(.option)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (dx, dy) = drag(event) else { return }
        if turning { turn(dx, dy) } else { pan(dx, dy) }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let (dx, dy) = drag(event) else { return }
        turn(dx, dy)
    }

    /// The mouse's move since the last event, in points.
    private func drag(_ event: NSEvent) -> (Double, Double)? {
        guard let last = lastDrag else { return nil }
        let now = event.locationInWindow
        lastDrag = now
        return (Double(now.x - last.x), Double(now.y - last.y))
    }

    /// Turns the camera as the engine does: across the whole width is half a
    /// turn, down the whole height tilts twice the pitch range (the engine's
    /// `tiltGestureSensitivity` 2), dragging down tilts toward the horizon.
    private func turn(_ dx: Double, _ dy: Double) {
        let w = max(Double(bounds.width), 1), h = max(Double(bounds.height), 1)
        let e = eye
        yaw += dx / w * 180
        if model.flying {
            pitch = min(89, max(-89, pitch - dy / h * 2 * 88))
            target = e + forward * distance
        } else {
            pitch = min(-2, max(-89, pitch - dy / h * 2 * 87))
        }
        needsDisplay = true
    }

    /// Moves the target over the ground, by screen points.
    private func pan(_ dx: Double, _ dy: Double) {
        let metresPerPoint = distance * tan(25 * .pi / 180) * 2 / max(Double(bounds.height), 1)
        let y = yaw * .pi / 180
        let right = SIMD3(cos(y), 0, sin(y)), ahead = SIMD3(sin(y), 0, -cos(y))
        target -= (right * dx + ahead * dy) * metresPerPoint
        needsDisplay = true
    }

    /// Scrolling zooms, the wheel and the trackpad alike, up zooming in, as in
    /// the engine. In flight it sets the speed.
    override func scrollWheel(with event: NSEvent) {
        if model.flying {
            speed = min(500, max(2, speed * exp(event.scrollingDeltaY / 50)))
            model.tileStatus = String(format: "Flight speed %.0f m/s", speed)
        } else {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
            zoom(by: exp(-dy), at: convert(event.locationInWindow, from: nil))
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 / (1 + event.magnification), at: convert(event.locationInWindow, from: nil))
    }

    /// Zooms toward the ground under the cursor, as the engine does: the
    /// camera comes closer along the way to that point, which stays under
    /// the cursor. Off the ground, toward the target.
    private func zoom(by factor: Double, at p: NSPoint) {
        let k = min(20000, max(5, distance * factor)) / distance
        let w = max(Double(bounds.width), 1), h = max(Double(bounds.height), 1)
        let f = forward
        let right = simd_normalize(simd_cross(f, SIMD3(0, 1, 0)))
        let up = simd_cross(right, f)
        let t = tan(25 * Double.pi / 180)
        let ray = f + right * ((Double(p.x) / w * 2 - 1) * t * w / h) + up * ((Double(p.y) / h * 2 - 1) * t)
        let e = eye
        if ray.y < -1e-3 {
            let ground = e + ray * (-e.y / ray.y)
            target = ground + (target - ground) * k
        }
        distance *= k
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        switch event.keyCode {
        case 48:                                    // tab
            model.flying.toggle()
            if model.flying { distance = 20 } else { distance = max(distance, 200) }
            keys = []
        case 3: frameTiles()                             // F
        case 37: model.showLightMap.toggle()        // L
        default:
            if [0, 1, 2, 12, 13, 14].contains(event.keyCode) && model.flying {
                keys.insert(event.keyCode)
                lastFrame = CACurrentMediaTime()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }
}

extension TileView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if loaded != model.tilesRevision { reload() }
        fly()
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(enc, viewProjection())
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
