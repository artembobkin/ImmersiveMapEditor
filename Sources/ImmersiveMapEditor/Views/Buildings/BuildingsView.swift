import SwiftUI

/// The Buildings view: the tile's buildings of OpenStreetMap from straight
/// above, their outlines and parts, to pick some (click, shift-click) and
/// see their tags, and to mark them a landmark. Drag to move, scroll or
/// pinch to zoom at the cursor, F frames the tile. The camera is the one
/// the views share (its ground point and scale).
struct BuildingsView: View {
    @Environment(Session.self) private var session
    @State private var size = CGSize(width: 800, height: 600)
    /// The middle of the view in the tile's metres, and points a metre.
    @State private var centre = Vec2.zero
    @State private var scale = 1.0
    @State private var dragFrom: Vec2?
    @State private var magnifyFrom: Double?
    @State private var shift = false

    var body: some View {
        let catalog = session.buildings
        let candidates = Set(session.candidateBuildings)
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.9, green: 0.89, blue: 0.87)))
            if let (lo, hi) = catalog.square {
                ctx.stroke(path([[lo, Vec2(hi.x, lo.y), hi, Vec2(lo.x, hi.y)]]), with: .color(.purple.opacity(0.7)), lineWidth: 1.5)
            }
            for b in catalog.all {
                let shape = path(b.polygons.flatMap { $0 })
                let picked = catalog.picked.contains(b.id), marked = candidates.contains(b.id)
                let fill: Color = picked ? .accentColor.opacity(0.55) : marked ? .orange.opacity(0.45)
                    : b.isPart ? Color(white: 0.62).opacity(0.5) : Color(white: 0.72)
                ctx.fill(shape, with: .color(fill), style: FillStyle(eoFill: true))
                ctx.stroke(shape, with: .color(picked ? .accentColor : Color(white: 0.35)), lineWidth: picked ? 2 : (b.isPart ? 0.5 : 1))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1, coordinateSpace: .local) { p in
            guard let b = catalog.building(at: world(p)) else {
                if !shift { catalog.picked = [] }
                return
            }
            if shift {
                if catalog.picked.contains(b.id) { catalog.picked.remove(b.id) } else { catalog.picked.insert(b.id) }
            } else {
                catalog.picked = [b.id]
            }
        }
        .gesture(DragGesture(minimumDistance: 3).onChanged { v in
            if dragFrom == nil { dragFrom = centre }
            centre = dragFrom! + Vec2(-v.translation.width, v.translation.height) / scale
        }.onEnded { _ in dragFrom = nil })
        .simultaneousGesture(MagnifyGesture().onChanged { v in
            if magnifyFrom == nil { magnifyFrom = scale }
            zoom(to: magnifyFrom! * v.magnification, keeping: v.startLocation)
        }.onEnded { _ in magnifyFrom = nil })
        .onScrollWheel { dy, p in zoom(to: scale * pow(2, dy), keeping: p) }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress("f") {
            frame()
            return .handled
        }
        .onModifierKeysChanged(mask: .shift) { _, keys in shift = keys.contains(.shift) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: catalog.square.map { "\($0.0)" }, initial: true) { take() }
        .onChange(of: centre) { give() }
        .onChange(of: scale) { give() }
    }

    /// A screen point in the tile's metres (north up).
    private func world(_ p: CGPoint) -> Vec2 {
        centre + Vec2(p.x - size.width / 2, size.height / 2 - p.y) / scale
    }

    private func screen(_ w: Vec2) -> CGPoint {
        CGPoint(x: (w.x - centre.x) * scale + size.width / 2, y: size.height / 2 - (w.y - centre.y) * scale)
    }

    private func path(_ rings: [[Vec2]]) -> Path {
        var p = Path()
        for ring in rings where ring.count >= 3 { p.addLines(ring.map(screen)); p.closeSubpath() }
        return p
    }

    private func zoom(to next: Double, keeping p: CGPoint) {
        let at = world(p)
        scale = min(200, max(0.05, next))
        centre = at - Vec2(p.x - size.width / 2, size.height / 2 - p.y) / scale
    }

    /// The tile framed whole.
    private func frame() {
        guard let (lo, hi) = session.buildings.square else { return }
        centre = (lo + hi) / 2
        scale = min(size.width / (hi.x - lo.x), size.height / (hi.y - lo.y)) * 0.92
    }

    /// Where the other views looked, else the tile framed.
    private func take() {
        guard let proj = session.buildings.projection, let c = session.viewCamera.centre(in: proj) else { return frame() }
        centre = c
        scale = 1 / session.viewCamera.metresPerPoint
    }

    private func give() {
        guard let proj = session.buildings.projection else { return }
        session.viewCamera.set(centre: centre, in: proj, metresPerPoint: 1 / scale)
    }
}
