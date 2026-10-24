import MetalKit
import simd

/// One vertex for everything drawn: a point in metres, an extrusion from
/// it (in metres, or in screen points when `pixel` is 1) and a colour. The
/// layout matches `V` in the shader.
struct Vertex {
    var colour: SIMD4<Float>
    var position: SIMD2<Float>
    var extrude: SIMD2<Float>
    var pixel: Float = 0
}

struct Uniforms {
    var view: SIMD4<Float>      // the centre in metres, half the view's size in points
    var scale: SIMD4<Float>     // points per metre
}

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

func rgb(_ hex: UInt32, _ alpha: Float = 1) -> SIMD4<Float> {
    SIMD4(Float((hex >> 16) & 255) / 255, Float((hex >> 8) & 255) / 255, Float(hex & 255) / 255, alpha)
}

/// The colours, the tile's own palette (build/common.py) where it has one.
enum Colours {
    static let ground = rgb(0xE6E2DC)
    static let building = rgb(0xD2CCC4)
    static let buildingEdge = rgb(0xB9B2A9)
    static let asphalt = rgb(0x6E6A7D)
    static let kerb = rgb(0xA6A3B1)
    static let marking = rgb(0xECE8E1)
    static let yellow = rgb(0xE8C24A)
    static let bad = rgb(0xE5484D)
    static let cutEdge = rgb(0xE5484D)
    static let centreLine = rgb(0x3C7DD9, 0.55)
    static let crossing = rgb(0x3C7DD9)
    static let stop = rgb(0x2E9E5B)
    static let tileEdge = rgb(0x8A6FD1, 0.8)
    static let shelter = rgb(0xF2EBDD)
    static let shelterEdge = rgb(0x5B5E6C)
    static let handle = rgb(0xFFFFFF)
    static let handleEdge = rgb(0x30303A)
    static let selected = rgb(0xFF8A1F)
    static let draft = rgb(0x1F9BFF)
}

/// Builds vertex lists.
struct Mesh {
    var v: [Vertex] = []

    mutating func triangle(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ colour: SIMD4<Float>) {
        for p in [a, b, c] { v.append(Vertex(colour: colour, position: SIMD2(Float(p.x), Float(p.y)), extrude: .zero)) }
    }

    /// A convex polygon, as a fan.
    mutating func convex(_ pts: [Vec2], _ colour: SIMD4<Float>) {
        guard pts.count >= 3 else { return }
        for i in 1..<(pts.count - 1) { triangle(pts[0], pts[i], pts[i + 1], colour) }
    }

    /// A ring as a fan for the stencil: overlapping triangles count the
    /// winding, the cover pass fills where it is not zero.
    mutating func fan(_ ring: [Vec2]) {
        convex(ring, .zero)
    }

    /// A line `width` screen points wide from a to b.
    mutating func pixelLine(_ a: Vec2, _ b: Vec2, width: Float, _ colour: SIMD4<Float>) {
        let d = b - a
        guard d.length > 1e-9 else { return }
        let n = d.normalized.left
        let e = SIMD2(Float(n.x), Float(n.y)) * width / 2
        let pa = SIMD2(Float(a.x), Float(a.y)), pb = SIMD2(Float(b.x), Float(b.y))
        let quad = [(pa, -e), (pb, -e), (pb, e), (pa, -e), (pb, e), (pa, e)]
        for (p, x) in quad { v.append(Vertex(colour: colour, position: p, extrude: x, pixel: 1)) }
    }

    mutating func pixelPolyline(_ pts: [Vec2], closed: Bool = false, width: Float, _ colour: SIMD4<Float>) {
        guard pts.count >= 2 else { return }
        for i in 0..<(pts.count - 1) { pixelLine(pts[i], pts[i + 1], width: width, colour) }
        if closed { pixelLine(pts[pts.count - 1], pts[0], width: width, colour) }
    }

    /// A square `size` screen points across at p.
    mutating func pixelSquare(_ p: Vec2, size: Float, _ colour: SIMD4<Float>) {
        let h = size / 2
        let c = SIMD2(Float(p.x), Float(p.y))
        for e in [SIMD2<Float>(-h, -h), SIMD2(h, -h), SIMD2(h, h), SIMD2(-h, -h), SIMD2(h, h), SIMD2(-h, h)] {
            v.append(Vertex(colour: colour, position: c, extrude: e, pixel: 1))
        }
    }

    /// A strip `width` metres wide along a segment.
    mutating func band(_ a: Vec2, _ b: Vec2, width: Double, _ colour: SIMD4<Float>) {
        let n = (b - a).normalized.left * (width / 2)
        convex([a - n, b - n, b + n, a + n], colour)
    }
}

/// A batch filled through the stencil: its rings' fans, then one cover
/// quad over their bounds.
struct StencilBatch {
    var fans = Mesh()
    var cover = Mesh()
    mutating func add(_ rings: [[Vec2]]) {
        for r in rings { fans.fan(r) }
    }
    mutating func close(_ colour: SIMD4<Float>) {
        let pts = fans.v.map(\.position)
        guard let first = pts.first else { return }
        var lo = first, hi = first
        for p in pts { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let a = Vec2(Double(lo.x) - 1, Double(lo.y) - 1), b = Vec2(Double(hi.x) + 1, Double(hi.y) + 1)
        cover.convex([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], colour)
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let colourPipeline: MTLRenderPipelineState
    private let stencilPipeline: MTLRenderPipelineState
    private let plain: MTLDepthStencilState
    private let count: MTLDepthStencilState
    private let fill: MTLDepthStencilState
    weak var view: MapView?

    /// The layers of the document, rebuilt when it changes.
    private var built = -1
    private var buildings = StencilBatch()
    private var buildingEdges = Mesh()
    private var kerb = Mesh()
    private var roadway = StencilBatch()
    private var cuts = StencilBatch()
    private var cutEdges = Mesh()
    private var paint = Mesh()
    private var letters = StencilBatch()
    private var shelters = Mesh()
    private var centreLines = Mesh()
    private var grid = Mesh()

    init?(view: MapView) {
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

    // MARK: Building the layers

    private func rebuild(_ model: EditorModel) {
        built = model.revision
        let doc = model.doc
        buildings = StencilBatch()
        buildingEdges = Mesh()
        for b in model.context.buildings where b.count >= 3 {
            buildings.add([signedArea(b) < 0 ? b.reversed() : b])
            buildingEdges.pixelPolyline(b, closed: true, width: 1, Colours.buildingEdge)
        }
        buildings.close(Colours.building)

        kerb = Mesh()
        roadway = StencilBatch()
        cuts = StencilBatch()
        cutEdges = Mesh()
        for a in doc.areas {
            if a.op == "add" {
                roadway.add(a.rings)
                for ring in a.rings {
                    for i in ring.indices { kerb.band(ring[i], ring[(i + 1) % ring.count], width: 0.7, Colours.kerb) }
                }
            } else {
                cuts.add(a.rings)
                for ring in a.rings { cutEdges.pixelPolyline(ring, closed: true, width: 1.5, Colours.cutEdge) }
            }
        }
        roadway.close(Colours.asphalt)
        cuts.close(Colours.ground)

        paint = Mesh()
        letters = StencilBatch()
        for m in doc.markings {
            switch m.kind {
            case "line":
                for q in MarkingShapes.lineQuads(m) { paint.convex(q, m.colour == "yellow" ? Colours.yellow : Colours.marking) }
            case "zebra":
                for (q, whole) in MarkingShapes.zebraBars(m, inside: model.onRoadway) {
                    paint.convex(q, whole ? Colours.marking : Colours.bad)
                }
            case "zigzag":
                for q in MarkingShapes.stroke(MarkingShapes.zigzag(m), width: MarkingShapes.zigzagLine) {
                    paint.convex(q, Colours.yellow)
                }
            default:
                letters.add(MarkingShapes.letterRings(m))
            }
        }
        letters.close(Colours.marking)

        shelters = Mesh()
        for s in doc.shelters {
            let r = MarkingShapes.shelterRect(s)
            shelters.convex(r, Colours.shelter)
            shelters.pixelPolyline(r, closed: true, width: 1.5, Colours.shelterEdge)
            // The open side, to the road.
            shelters.pixelLine(r[3], r[2], width: 3, Colours.draft)
        }

        centreLines = Mesh()
        for r in model.context.roads {
            let pedestrian = ["footway", "pedestrian"].contains(r.highway)
            centreLines.pixelPolyline(r.points, width: pedestrian ? 1 : 1.5,
                                      pedestrian ? rgb(0x3C7DD9, 0.25) : Colours.centreLine)
        }

        grid = Mesh()
        let t = doc.tiles
        let proj = doc.projection
        for y in t.y0...t.y1 {
            for x in t.x0...t.x1 {
                let (a, b) = proj.tileRect(x: x, y: y)
                grid.pixelPolyline([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, width: 1.5, Colours.tileEdge)
            }
        }
    }

    // MARK: Drawing

    func draw(in mtkView: MTKView) {
        guard let view, let model = view.model,
              let pass = mtkView.currentRenderPassDescriptor, let drawable = mtkView.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if built != model.revision { rebuild(model) }
        let size = mtkView.bounds.size
        var u = Uniforms(view: SIMD4(Float(view.centre.x), Float(view.centre.y), Float(size.width / 2), Float(size.height / 2)),
                         scale: SIMD4(Float(view.scale), 0, 0, 0))
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

        if model.showBuildings {
            stencilDraw(buildings)
            plainDraw(buildingEdges)
        }
        plainDraw(kerb)
        stencilDraw(roadway)
        stencilDraw(cuts)
        plainDraw(cutEdges)
        if model.showMarkings {
            plainDraw(paint)
            stencilDraw(letters)
        }
        plainDraw(shelters)
        if model.showCentreLines { plainDraw(centreLines) }
        plainDraw(grid)
        plainDraw(view.overlay())

        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
