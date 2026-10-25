import SwiftUI

/// The Map view: drag to move, scroll or pinch to zoom at the cursor (as in
/// the engine). A click picks or drops a tile, shift-drag picks a box of
/// them, a double-click shows a built tile in 3D, F frames the work. The
/// scroll wheel comes through Metal/AppKitBridge.swift.
struct MapPicker: View {
    @Environment(Session.self) private var session
    @State private var size = CGSize(width: 800, height: 600)
    @State private var shift = false
    @State private var box: (CGPoint, CGPoint)?
    @State private var dragFrom: SIMD2<Double>?
    @State private var magnifyFrom: Double?

    var body: some View {
        let workspace = session.workspace, camera = session.camera
        MapCanvas(workspace: workspace, camera: camera, raster: session.raster, box: box)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { p in
                let t = camera.tile(at: p, in: size)
                if workspace.built.contains(t) {
                    workspace.selection = [t]
                    workspace.viewMode = .tiles
                }
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { p in
                let t = camera.tile(at: p, in: size)
                if workspace.selection.contains(t) { workspace.selection.remove(t) } else { workspace.selection.insert(t) }
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { v in
                if shift || box != nil {
                    box = (v.startLocation, v.location)
                } else {
                    if dragFrom == nil { dragFrom = camera.centre }
                    camera.centre = dragFrom! - SIMD2(v.translation.width, v.translation.height) / camera.pointsPerUnit
                }
            }.onEnded { _ in
                if let (a, b) = box {
                    let ta = camera.tile(at: a, in: size), tb = camera.tile(at: b, in: size)
                    for y in min(ta.y, tb.y)...max(ta.y, tb.y) {
                        for x in min(ta.x, tb.x)...max(ta.x, tb.x) { workspace.selection.insert(TileKey(z: ta.z, x: x, y: y)) }
                    }
                }
                box = nil
                dragFrom = nil
            })
            .simultaneousGesture(MagnifyGesture().onChanged { v in
                if magnifyFrom == nil { magnifyFrom = camera.zoom }
                camera.zoom(to: magnifyFrom! + log2(v.magnification), keeping: v.startLocation, in: size)
            }.onEnded { _ in magnifyFrom = nil })
            .onModifierKeysChanged(mask: .shift) { _, keys in shift = keys.contains(.shift) }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress("f") {
                camera.frame(workspace)
                return .handled
            }
            .onScrollWheel { dy, p in camera.zoom(to: camera.zoom + dy, keeping: p, in: size) }
    }
}
