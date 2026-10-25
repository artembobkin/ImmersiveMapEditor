import SwiftUI

/// The Light view: the light map of the working tile, seen from above. Drag to move, scroll or pinch to zoom at the cursor, F frames.
struct LightView: View {
    @Environment(Session.self) private var session
    @State private var size = CGSize(width: 800, height: 600)
    /// Points per tile, and the view's centre in tiles.
    @State private var scale = 400.0
    @State private var centre = SIMD2<Double>(0, 0)
    @State private var dragFrom: SIMD2<Double>?
    @State private var magnifyFrom: Double?

    var body: some View {
        let workspace = session.workspace, lights = session.lights
        let tiles = workspace.tile.map { [$0] } ?? []
        let built = tiles.filter { workspace.built.contains($0) }
        Group {
            if built.isEmpty {
                ContentUnavailableView("The tile is not built", systemImage: "sun.max",
                                       description: Text("Pick a built tile on the Map: its light map shows here."))
            } else {
                Canvas { ctx, _ in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
                    for t in tiles {
                        let r = rect(t)
                        if let map = lights.maps[t] {
                            ctx.draw(Image(decorative: map.image, scale: 1), in: r)
                        } else {
                            ctx.fill(Path(r), with: .color(Color(white: 0.2)))
                        }
                        ctx.stroke(Path(r), with: .color(.white.opacity(0.35)), lineWidth: 1)
                        ctx.draw(Text(verbatim: t.name).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8)),
                                 at: CGPoint(x: r.minX + 6, y: r.minY + 4), anchor: .topLeading)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                    if dragFrom == nil { dragFrom = centre }
                    centre = dragFrom! - SIMD2(v.translation.width, v.translation.height) / scale
                }.onEnded { _ in dragFrom = nil })
                .simultaneousGesture(MagnifyGesture().onChanged { v in
                    if magnifyFrom == nil { magnifyFrom = scale }
                    zoom(to: magnifyFrom! * v.magnification, keeping: v.startLocation)
                }.onEnded { _ in magnifyFrom = nil })
                .onScrollWheel { dy, p in zoom(to: scale * pow(2, dy), keeping: p) }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress("f") {
                    frame(tiles)
                    return .handled
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // Where the other views looked, else the tile framed.
        .onChange(of: tiles, initial: true) { take(tiles) }
        .onChange(of: size) { take(tiles) }
        .onChange(of: centre) { give() }
        .onChange(of: scale) { give() }
        .task(id: [tiles.map(\.name).joined(separator: " "), "\(workspace.tilesRevision)"]) {
            lights.load(tiles, from: workspace)
        }
    }

    /// A tile's square on screen.
    private func rect(_ t: TileKey) -> CGRect {
        let x = (Double(t.x) - centre.x) * scale + size.width / 2
        let y = (Double(t.y) - centre.y) * scale + size.height / 2
        return CGRect(x: x, y: y, width: scale, height: scale)
    }

    /// The camera the views share, or the tile framed while it is not set.
    private func take(_ tiles: [TileKey]) {
        let shared = session.viewCamera
        guard let z = tiles.first?.z, let c = shared.tileUnits(z: z) else { return frame(tiles) }
        centre = c
        scale = SharedCamera.tileMetres(z: z, latitude: latitudeOf(c.y, z)) / shared.metresPerPoint
    }

    /// The view given to the others as it moves.
    private func give() {
        guard let z = session.workspace.tile?.z else { return }
        session.viewCamera.set(tileUnits: centre, z: z, pointsPerTile: scale)
    }

    private func latitudeOf(_ y: Double, _ z: Int) -> Double {
        atan(sinh(.pi * (1 - 2 * y / pow(2, Double(z))))) * 180 / .pi
    }

    private func frame(_ tiles: [TileKey]) {
        guard !tiles.isEmpty else { return }
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        let w = Double(xs.max()! - xs.min()! + 1), h = Double(ys.max()! - ys.min()! + 1)
        centre = SIMD2(Double(xs.min()!) + w / 2, Double(ys.min()!) + h / 2)
        scale = max(40, min(size.width / w, size.height / h) * 0.92)
    }

    private func zoom(to next: Double, keeping p: CGPoint) {
        let clamped = min(8000, max(40, next))
        let at = centre + SIMD2(p.x - size.width / 2, p.y - size.height / 2) / scale
        scale = clamped
        centre = at - SIMD2(p.x - size.width / 2, p.y - size.height / 2) / scale
    }
}
