import SwiftUI

/// The Buildings view: the tile's buildings of OpenStreetMap from straight
/// above, their outlines and parts, to pick some (click, shift-click; a
/// double-click a whole building with its parts) and see their tags, and to
/// mark them a landmark. The buildings known by name are tinted, the notable
/// ones (an article, a heritage tag, a church or theatre) deeper, and named
/// on the map (`BuildingNote`; the user, 2026-11-01). Drag to move, scroll or
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
                    : Self.tint(b.note, part: b.isPart)
                ctx.fill(shape, with: .color(fill), style: FillStyle(eoFill: true))
                ctx.stroke(shape, with: .color(picked ? .accentColor : Color(white: 0.35)), lineWidth: picked ? 2 : (b.isPart ? 0.5 : 1))
            }
            if catalog.showNames { names(in: ctx, of: catalog.all) }
        }
        .contentShape(Rectangle())
        // A double-click: a landmark's building opens the landmark, its model
        // (the user, 2026-11-01); any other picks the whole building, its
        // outline and every part.
        .onTapGesture(count: 2, coordinateSpace: .local) { p in
            if let b = catalog.building(at: world(p)), let holder = session.landmark(holding: b.id),
               holder.tile == session.workspace.tile?.name {
                session.pickedLandmark = holder.id
                return
            }
            let ids = Set(catalog.whole(at: world(p)).map(\.id))
            catalog.picked = shift ? catalog.picked.union(ids) : ids
        }
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
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p): catalog.hovered = catalog.building(at: world(p))?.id
            case .ended: catalog.hovered = nil
            }
        }
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

    /// A building's colour by how much it matters: grey for the plain ones,
    /// teal for the named, deeper for the notable; a part the same, lighter.
    static func tint(_ note: BuildingNote, part: Bool) -> Color {
        let colour: Color = switch note {
        case .plain: Color(white: part ? 0.62 : 0.72)
        case .named: Color(red: 0.64, green: 0.80, blue: 0.80)
        case .notable: Color(red: 0.30, green: 0.65, blue: 0.68)
        }
        return part ? colour.opacity(0.5) : colour
    }

    /// The names of the known buildings on the map, each only where it fits
    /// whole inside its building at this zoom, small and in the building's
    /// own colour (the user, 2026-11-01: names floating over the map, large,
    /// belonged to nothing). Any building's name is in the status line
    /// under the pointer.
    private func names(in ctx: GraphicsContext, of buildings: [OsmBuilding]) {
        var halo = ctx
        halo.addFilter(.shadow(color: .white.opacity(0.7), radius: 1))
        let bounds = CGRect(origin: .zero, size: size)
        for b in buildings where !b.isPart && b.note != .plain {
            guard let name = b.name else { continue }
            let at = screen(b.centroid)
            guard bounds.contains(at), b.contains(b.centroid) else { continue }
            let text = ctx.resolve(Text(name).font(.system(size: 9, weight: .medium)).foregroundStyle(Color(red: 0.08, green: 0.26, blue: 0.28)))
            let box = text.measure(in: CGSize(width: 240, height: 12))
            let rect = CGRect(x: at.x - box.width / 2, y: at.y - box.height / 2, width: box.width, height: box.height)
            // Whole inside the outline: its corners and the middles of its
            // long sides, in the tile's metres.
            let probes = [rect.minX, rect.midX, rect.maxX].flatMap { x in [rect.minY, rect.maxY].map { CGPoint(x: x, y: $0) } }
            guard probes.allSatisfy({ b.contains(world($0)) }) else { continue }
            halo.draw(text, in: rect)
        }
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
