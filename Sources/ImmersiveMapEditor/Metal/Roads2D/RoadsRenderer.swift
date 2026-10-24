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
    return o;
}
fragment float4 fs(Out i [[stage_in]]) { return i.colour; }
"""

/// Draws the Roads view: its pipelines (colour, and polygons through the
/// stencil, non-zero winding), the document's layers, the overlay.
@MainActor
final class RoadsRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let colourPipeline: MTLRenderPipelineState
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
        super.init()
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
                         scale: SIMD4(Float(t.scale), 0, 0, 0))
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
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

        if model.layers.buildings {
            stencilDraw(meshes.buildings)
            plainDraw(meshes.buildingEdges)
        }
        plainDraw(meshes.kerb)
        stencilDraw(meshes.roadway)
        stencilDraw(meshes.cuts)
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
}
