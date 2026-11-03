import Geometry
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
    /// The outlines as paths in the tile's metres, built once a tile, and
    /// the labels' sizes, measured once a name: a path a frame for two
    /// thousand buildings, and every label resolved and measured again,
    /// made a drag lag (the user, 2026-11-03).
    @State private var cache = DrawCache()
    /// Whether the camera is the tile framed by the view itself, not moved
    /// by the user nor taken from another view: then a change of the view's
    /// size frames the tile again (the user, 2026-11-03: the first frame
    /// was fitted to a size the view did not have yet).
    @State private var framedByItself = false

    var body: some View {
        let catalog = session.buildings
        let candidates = session.candidateBuildings
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.9, green: 0.89, blue: 0.87)))
            // The map drawn in the tile's metres through the context's
            // transform (north up), the line widths divided by the scale to
            // stay in points.
            var map = ctx
            map.translateBy(x: size.width / 2 - centre.x * scale, y: size.height / 2 + centre.y * scale)
            map.scaleBy(x: scale, y: -scale)
            let lo = world(CGPoint(x: 0, y: size.height), in: size), hi = world(CGPoint(x: size.width, y: 0), in: size)
            let visible = CGRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)
            if let (lo, hi) = catalog.square {
                map.stroke(Path(CGRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)), with: .color(.purple.opacity(0.7)), lineWidth: 1.5 / scale)
            }
            // The buildings in a dozen batches, one a look (plain, named,
            // notable, a landmark's, picked; outlines then parts), each one
            // path filled and stroked once: two thousand fills and strokes
            // a frame, each building's kind read off its tags again, made
            // a drag lag (the user, 2026-11-03).
            for batch in cache.batches(of: catalog, picked: catalog.picked, marked: candidates) {
                map.fill(batch.path, with: .color(batch.fill))
                map.stroke(batch.path, with: .color(batch.stroke), lineWidth: batch.width / scale)
            }
            if catalog.showNames { names(in: ctx, of: catalog.all, drawn: cache.drawn(of: catalog), visible: visible) }
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
            // A landmark's building picks the whole landmark, every building
            // of it: it is the landmark one means (the user, 2026-11-03).
            let ids = session.landmark(holding: b.id).map { Set($0.buildings) } ?? [b.id]
            if shift {
                if catalog.picked.contains(b.id) { catalog.picked.subtract(ids) } else { catalog.picked.formUnion(ids) }
            } else {
                catalog.picked = ids
            }
        }
        .gesture(DragGesture(minimumDistance: 3).onChanged { v in
            if dragFrom == nil { dragFrom = centre }
            framedByItself = false
            centre = dragFrom! + Vec2(-v.translation.width, v.translation.height) / scale
        }.onEnded { _ in dragFrom = nil })
        .simultaneousGesture(MagnifyGesture().onChanged { v in
            if magnifyFrom == nil { magnifyFrom = scale }
            framedByItself = false
            zoom(to: magnifyFrom! * v.magnification, keeping: v.startLocation)
        }.onEnded { _ in magnifyFrom = nil })
        .onScrollWheel { dy, p in
            framedByItself = false
            zoom(to: scale * pow(2, dy), keeping: p)
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            // Not while dragging: the building under the pointer is looked
            // up among two thousand, and the status line drawn, at every move.
            case .active(let p): if dragFrom == nil { catalog.hovered = catalog.building(at: world(p))?.id }
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            size = $0
            if framedByItself { frame() }
        }
        .onChange(of: catalog.square.map { "\($0.0)" }, initial: true) { take() }
        // Another tile read: framed, or where the other views looked, once
        // its OSM is in (the user, 2026-11-03: the last tile's camera showed
        // the new one at the foot of the view).
        .onChange(of: catalog.loading) { if !catalog.loading { take() } }
        .overlay {
            if catalog.loading {
                ProgressView("Reading the tile's OSM…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
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
    private func names(in ctx: GraphicsContext, of buildings: [OsmBuilding], drawn: [String: DrawCache.Drawn], visible: CGRect) {
        var halo = ctx
        halo.addFilter(.shadow(color: .white.opacity(0.7), radius: 1))
        let bounds = CGRect(origin: .zero, size: size)
        for b in buildings {
            guard let d = drawn[b.id], let (name, centroid) = d.label, d.bounds.intersects(visible) else { continue }
            let at = screen(centroid)
            guard bounds.contains(at) else { continue }
            let text = Text(name).font(.system(size: 9, weight: .medium)).foregroundStyle(Color(red: 0.08, green: 0.26, blue: 0.28))
            let box = cache.size(of: name) { ctx.resolve(text).measure(in: CGSize(width: 240, height: 12)) }
            let rect = CGRect(x: at.x - box.width / 2, y: at.y - box.height / 2, width: box.width, height: box.height)
            // Whole inside the outline: its corners and the middles of its
            // long sides, in the tile's metres.
            let probes = [rect.minX, rect.midX, rect.maxX].flatMap { x in [rect.minY, rect.maxY].map { CGPoint(x: x, y: $0) } }
            guard probes.allSatisfy({ b.contains(world($0)) }) else { continue }
            halo.draw(text, in: rect)
        }
    }

    /// A screen point in the tile's metres (north up).
    private func world(_ p: CGPoint) -> Vec2 { world(p, in: size) }

    private func world(_ p: CGPoint, in size: CGSize) -> Vec2 {
        centre + Vec2(p.x - size.width / 2, size.height / 2 - p.y) / scale
    }

    private func screen(_ w: Vec2) -> CGPoint {
        CGPoint(x: (w.x - centre.x) * scale + size.width / 2, y: size.height / 2 - (w.y - centre.y) * scale)
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
        framedByItself = true
    }

    /// Where the other views looked, else the tile framed.
    private func take() {
        guard let proj = session.buildings.projection, let c = session.viewCamera.centre(in: proj) else { return frame() }
        // The camera this view gave itself leaves its framing as it is.
        let s = 1 / session.viewCamera.metresPerPoint
        if abs(c.x - centre.x) > 0.01 || abs(c.y - centre.y) > 0.01 || abs(s - scale) > 1e-6 { framedByItself = false }
        centre = c
        scale = s
    }

    private func give() {
        guard let proj = session.buildings.projection else { return }
        session.viewCamera.set(centre: centre, in: proj, metresPerPoint: 1 / scale)
    }
}

/// What the Buildings view draws from, kept between frames: a reference,
/// so filling it while drawing changes no state of the view.
@MainActor
final class DrawCache {
    /// What is drawn of one building, made once a tile: its path in the
    /// tile's metres (north up), every outer ring wound counter-clockwise
    /// and every hole clockwise, so the nonzero rule fills a batch of many
    /// buildings right, holes and overlaps alike; its bounds; its note; and
    /// its label, the name and the centroid it sits on, for a known
    /// outline whose centroid is inside it.
    struct Drawn {
        let path: Path
        let bounds: CGRect
        let note: BuildingNote
        let isPart: Bool
        let label: (String, Vec2)?
    }

    /// Buildings drawn alike, as one path: filled and stroked once.
    struct Batch {
        let path: Path
        let fill: Color
        let stroke: Color
        /// The line width in points.
        let width: Double
    }

    /// The last few tiles' buildings, by tile and count, so a tile come
    /// back to is drawn at once.
    private var tiles: [String: [String: Drawn]] = [:]
    private var order: [String] = []
    private var batchKey = ""
    private var batchesKept: [Batch] = []
    private var sizes: [String: CGSize] = [:]

    /// Every building of the catalog as drawn, by its id.
    func drawn(of catalog: OsmBuildings) -> [String: Drawn] {
        let key = "\(catalog.tile?.name ?? "")/\(catalog.all.count)"
        if let kept = tiles[key] { return kept }
        var built: [String: Drawn] = [:]
        for b in catalog.all {
            var p = Path()
            for rings in b.polygons {
                for (k, ring) in rings.enumerated() where ring.count >= 3 {
                    // The outer ring counter-clockwise, the holes clockwise.
                    let ccw = signedArea(ring) > 0
                    let wound = (k == 0) == ccw ? ring : ring.reversed()
                    p.addLines(wound.map { CGPoint(x: $0.x, y: $0.y) })
                    p.closeSubpath()
                }
            }
            let note = b.note
            var label: (String, Vec2)?
            if !b.isPart, note != .plain, let name = b.name, case let c = b.centroid, b.contains(c) { label = (name, c) }
            built[b.id] = Drawn(path: p, bounds: p.boundingRect, note: note, isPart: b.isPart, label: label)
        }
        tiles[key] = built
        order.append(key)
        if order.count > 4 { tiles[order.removeFirst()] = nil }
        return built
    }

    /// The catalog's buildings in batches, one a look: outlines then
    /// parts, each plain, named, notable, a landmark's (`marked`) or
    /// picked; made again only when the tile, the picked or the marked
    /// change.
    func batches(of catalog: OsmBuildings, picked: Set<String>, marked: Set<String>) -> [Batch] {
        let drawn = drawn(of: catalog)
        let key = "\(catalog.tile?.name ?? "")/\(catalog.all.count)/\(picked.count):\(picked.hashValue)/\(marked.count):\(marked.hashValue)"
        if key == batchKey { return batchesKept }
        enum Look: Int, CaseIterable { case plain, named, notable, marked, picked }
        var paths: [Bool: [Look: Path]] = [false: [:], true: [:]]
        for b in catalog.all {
            guard let d = drawn[b.id] else { continue }
            let look: Look = picked.contains(b.id) ? .picked : marked.contains(b.id) ? .marked
                : d.note == .notable ? .notable : d.note == .named ? .named : .plain
            paths[d.isPart]![look, default: Path()].addPath(d.path)
        }
        var out: [Batch] = []
        for part in [false, true] {
            for look in Look.allCases {
                guard let path = paths[part]?[look], !path.isEmpty else { continue }
                let fill: Color = switch look {
                case .picked: .accentColor.opacity(0.55)
                case .marked: .orange.opacity(0.45)
                case .notable: BuildingsView.tint(.notable, part: part)
                case .named: BuildingsView.tint(.named, part: part)
                case .plain: BuildingsView.tint(.plain, part: part)
                }
                out.append(Batch(path: path, fill: fill, stroke: look == .picked ? .accentColor : Color(white: 0.35),
                                 width: look == .picked ? 2 : (part ? 0.5 : 1)))
            }
        }
        batchKey = key
        batchesKept = out
        return out
    }

    /// A label's size, measured once.
    func size(of name: String, measure: () -> CGSize) -> CGSize {
        if let s = sizes[name] { return s }
        let s = measure()
        sizes[name] = s
        return s
    }
}
