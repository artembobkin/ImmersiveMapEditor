import MetalKit
import simd

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 colour; float2 position; float2 extrude; float pixel; };
struct U { float4 view; float4 scale; };
struct Out { float4 position [[position]]; float4 colour; };
vertex Out vs(uint vid [[vertex_id]], const device V* v [[buffer(0)]], constant U& u [[buffer(1)]]) {
    V x = v[vid];
    float2 world = x.position + (x.pixel > 0.5 ? float2(0) : x.extrude);
    float2 clip = (world - u.view.xy) * u.scale.x / u.view.zw;
    if (x.pixel > 0.5) clip += x.extrude / u.view.zw;
    Out o;
    o.position = float4(clip, 0, 1);
    o.colour = x.colour;
    o.colour.a *= u.scale.y;
    return o;
}
fragment float4 fs(Out i [[stage_in]]) { return i.colour; }
struct TV { float2 position; float2 uv; };
struct TOut { float4 position [[position]]; float2 uv; };
vertex TOut tvs(uint vid [[vertex_id]], const device TV* v [[buffer(0)]], constant U& u [[buffer(1)]]) {
    TOut o;
    o.position = float4((v[vid].position - u.view.xy) * u.scale.x / u.view.zw, 0, 1);
    o.uv = v[vid].uv;
    return o;
}
fragment float4 tfs(TOut i [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]],
                    constant U& u [[buffer(1)]]) {
    return float4(t.sample(s, i.uv).rgb, u.scale.y);
}
"""

/// Draws the Roads view: its pipelines (colour, and polygons through the
/// stencil, non-zero winding), the document's layers, the overlay.
@MainActor
final class RoadsRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let colourPipeline: MTLRenderPipelineState
    private let imagePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let satellite: SatelliteTiles
    private let stencilPipeline: MTLRenderPipelineState
    private let plain: MTLDepthStencilState
    private let count: MTLDepthStencilState
    private let fill: MTLDepthStencilState
    weak var view: RoadsView?

    private var meshes = RoadLayers()

    init?(view: RoadsView) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.view = view
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.sampleCount = 4
        view.clearColor = MTLClearColor(red: Double(Colours.ground.x), green: Double(Colours.ground.y),
                                        blue: Double(Colours.ground.z), alpha: 1)
        view.clearStencil = 0
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "vs")
            d.fragmentFunction = library.makeFunction(name: "fs")
            d.rasterSampleCount = 4
            d.depthAttachmentPixelFormat = .depth32Float_stencil8
            d.stencilAttachmentPixelFormat = .depth32Float_stencil8
            let c = d.colorAttachments[0]!
            c.pixelFormat = .bgra8Unorm
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .sourceAlpha
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            colourPipeline = try device.makeRenderPipelineState(descriptor: d)
            d.vertexFunction = library.makeFunction(name: "tvs")
            d.fragmentFunction = library.makeFunction(name: "tfs")
            imagePipeline = try device.makeRenderPipelineState(descriptor: d)
            d.vertexFunction = library.makeFunction(name: "vs")
            d.fragmentFunction = library.makeFunction(name: "fs")
            c.writeMask = []
            stencilPipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            NSLog("ImmersiveMapEditor: shaders: \(error)")
            return nil
        }
        let none = MTLDepthStencilDescriptor()
        plain = device.makeDepthStencilState(descriptor: none)!
        // Non-zero winding: counter-clockwise triangles count up, clockwise
        // ones down, so overlapping areas join and holes stay open.
        let wind = MTLDepthStencilDescriptor()
        let up = MTLStencilDescriptor(), down = MTLStencilDescriptor()
        up.depthStencilPassOperation = .incrementWrap
        down.depthStencilPassOperation = .decrementWrap
        wind.frontFaceStencil = up
        wind.backFaceStencil = down
        count = device.makeDepthStencilState(descriptor: wind)!
        // Covers where the count is not zero and clears it on the way.
        let cover = MTLDepthStencilDescriptor()
        let test = MTLStencilDescriptor()
        test.stencilCompareFunction = .notEqual
        test.depthStencilPassOperation = .zero
        cover.frontFaceStencil = test
        cover.backFaceStencil = test
        fill = device.makeDepthStencilState(descriptor: cover)!
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: s)!
        satellite = SatelliteTiles(device: device)
        super.init()
        satellite.arrived = { [weak view] in view?.needsDisplay = true }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    // MARK: Drawing

    func draw(in mtkView: MTKView) {
        guard let view, let model = view.model,
              let pass = mtkView.currentRenderPassDescriptor, let drawable = mtkView.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if meshes.revision != model.revision { meshes = RoadLayers(model) }
        let size = mtkView.bounds.size
        let t = view.transform
        var u = Uniforms(view: SIMD4(Float(t.centre.x), Float(t.centre.y), Float(size.width / 2), Float(size.height / 2)),
                         scale: SIMD4(Float(t.scale), 1, 0, 0))
        /// The opacity the layers drawn next take.
        func opacity(_ a: Float) {
            u.scale.y = a
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        }
        opacity(1)
        // Clip space keeps the world's Y up: a counter-clockwise ring stays one.
        enc.setFrontFacing(.counterClockwise)

        func plainDraw(_ m: Mesh) {
            guard !m.v.isEmpty, let b = device.makeBuffer(bytes: m.v, length: m.v.count * MemoryLayout<Vertex>.stride) else { return }
            enc.setRenderPipelineState(colourPipeline)
            enc.setDepthStencilState(plain)
            enc.setVertexBuffer(b, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: m.v.count)
        }
        func stencilDraw(_ s: StencilBatch) {
            guard !s.fans.v.isEmpty,
                  let f = device.makeBuffer(bytes: s.fans.v, length: s.fans.v.count * MemoryLayout<Vertex>.stride),
                  let c = device.makeBuffer(bytes: s.cover.v, length: s.cover.v.count * MemoryLayout<Vertex>.stride)
            else { return }
            enc.setRenderPipelineState(stencilPipeline)
            enc.setDepthStencilState(count)
            enc.setVertexBuffer(f, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: s.fans.v.count)
            enc.setRenderPipelineState(colourPipeline)
            enc.setDepthStencilState(fill)
            enc.setStencilReferenceValue(0)
            enc.setVertexBuffer(c, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: s.cover.v.count)
        }

        let imagery = model.layers.satellite
        if imagery {
            opacity(Float(model.layers.satelliteOpacity))
            drawSatellite(enc, source: model.layers.imagery, doc: model.doc, tile: view.focus, transform: t, size: size,
                          pixels: mtkView.drawableSize.width / max(1, size.width))
            // The roadway over the imagery as see-through as asked, so the real
            // road shows under it.
            opacity(Float(model.layers.roadwayOpacity))
        }
        if model.layers.buildings {
            // Over the imagery only their outlines, the roofs show through.
            if !imagery { stencilDraw(meshes.buildings) }
            plainDraw(meshes.buildingEdges)
        }
        plainDraw(meshes.kerb)
        stencilDraw(meshes.roadway)
        if !imagery { stencilDraw(meshes.cuts) }
        opacity(1)
        plainDraw(meshes.cutEdges)
        if model.layers.markings {
            plainDraw(meshes.paint)
            stencilDraw(meshes.letters)
        }
        plainDraw(meshes.shelters)
        if model.layers.centreLines { plainDraw(meshes.centreLines) }
        plainDraw(meshes.grid)
        plainDraw(view.overlay())

        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// The imagery's tiles over the working tile only (or the document's
    /// tiles with none), those of them in view, at the zoom whose texels are
    /// about the screen's pixels and never coarser than the z15 tile itself.
    /// Local metres are linear in Web Mercator, so a tile is a rectangle: from
    /// the z15 grid of the document's projection.
    private func drawSatellite(_ enc: MTLRenderCommandEncoder, source: ImagerySource, doc: RoadPlan, tile: TileKey?, transform t: ViewTransform2D,
                               size: CGSize, pixels: Double) {
        let proj = doc.projection, x0 = doc.tiles.x0, y0 = doc.tiles.y0
        let (a, b) = proj.tileRect(x: x0, y: y0)
        let w = b.x - a.x
        // A z15 tile's place (continuous) to metres, and back.
        func metres(_ x: Double, _ y: Double) -> Vec2 { Vec2(a.x + (x - Double(x0)) * w, b.y - (y - Double(y0)) * w) }
        let (lo, hi) = t.visible(in: size)
        let fx0 = Double(x0) + (lo.x - a.x) / w, fx1 = Double(x0) + (hi.x - a.x) / w
        let fy0 = Double(y0) + (b.y - hi.y) / w, fy1 = Double(y0) + (b.y - lo.y) / w
        let z = min(19, max(15, Int((15 + log2(w * t.scale * pixels / source.tileTexels)).rounded())))
        let k = pow(2, Double(z - 15)), n = Int(k)
        // The z15 tiles covered: the working tile, or the document's.
        let (cx0, cy0, cx1, cy1) = tile.map { ($0.x, $0.y, $0.x, $0.y) } ?? (doc.tiles.x0, doc.tiles.y0, doc.tiles.x1, doc.tiles.y1)
        let tx0 = max(cx0 * n, Int((fx0 * k).rounded(.down))), tx1 = min(cx1 * n + n - 1, Int((fx1 * k).rounded(.down)))
        let ty0 = max(cy0 * n, Int((fy0 * k).rounded(.down))), ty1 = min(cy1 * n + n - 1, Int((fy1 * k).rounded(.down)))
        guard tx1 >= tx0, ty1 >= ty0, (tx1 - tx0 + 1) * (ty1 - ty0 + 1) <= 400 else { return }
        enc.setRenderPipelineState(imagePipeline)
        enc.setDepthStencilState(plain)
        enc.setFragmentSamplerState(sampler, index: 0)
        for ty in ty0...ty1 {
            for tx in tx0...tx1 {
                guard let tex = satellite.texture(.init(source: source, z: z, x: tx, y: ty)) else { continue }
                let p = metres(Double(tx) / k, Double(ty) / k), q = metres(Double(tx + 1) / k, Double(ty + 1) / k)
                // Two triangles, counter-clockwise: p is the north-west corner, q the south-east.
                let v: [SIMD4<Float>] = [
                    SIMD4(Float(p.x), Float(q.y), 0, 1), SIMD4(Float(q.x), Float(q.y), 1, 1), SIMD4(Float(q.x), Float(p.y), 1, 0),
                    SIMD4(Float(p.x), Float(q.y), 0, 1), SIMD4(Float(q.x), Float(p.y), 1, 0), SIMD4(Float(p.x), Float(p.y), 0, 0),
                ]
                enc.setVertexBytes(v, length: v.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
                enc.setFragmentTexture(tex, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
    }
}
