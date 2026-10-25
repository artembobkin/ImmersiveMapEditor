import SwiftUI

/// The map a tile is chosen on: drag to move, scroll or pinch to zoom at the
/// cursor (as in the engine). A click picks a tile, a double-click (or Open
/// the Tile) opens it to work on, F frames the work. The scroll wheel comes
/// through Metal/AppKitBridge.swift.
struct MapPicker: View {
    @Environment(Session.self) private var session
    @State private var size = CGSize(width: 800, height: 600)
    @State private var dragFrom: SIMD2<Double>?
    @State private var magnifyFrom: Double?

    var body: some View {
        let workspace = session.workspace, camera = session.camera
        MapCanvas(workspace: workspace, camera: camera, raster: session.raster, picked: session.candidate)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { p in
                session.open(tile: camera.tile(at: p, in: size))
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { p in
                session.candidate = camera.tile(at: p, in: size)
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                if dragFrom == nil { dragFrom = camera.centre }
                camera.centre = dragFrom! - SIMD2(v.translation.width, v.translation.height) / camera.pointsPerUnit
            }.onEnded { _ in dragFrom = nil })
            .simultaneousGesture(MagnifyGesture().onChanged { v in
                if magnifyFrom == nil { magnifyFrom = camera.zoom }
                camera.zoom(to: magnifyFrom! + log2(v.magnification), keeping: v.startLocation, in: size)
            }.onEnded { _ in magnifyFrom = nil })
            .focusable()
            .focusEffectDisabled()
            .onKeyPress("f") {
                camera.frame(workspace)
                return .handled
            }
            .onScrollWheel { dy, p in camera.zoom(to: camera.zoom + dy, keeping: p, in: size) }
    }
}
