import AppKit
import Combine
import MetalKit

/// The map: a top view of the road document, drawn on demand, and every
/// mouse and key gesture of the tools.
final class MapView: MTKView {
    var model: EditorModel? {
        didSet { observe() }
    }
    var renderer: Renderer?
    /// The view's centre in metres and its scale in points per metre.
    var centre = Vec2.zero
    var scale = 1.0
    /// Handles show from this scale up, so a whole block is not a cloud of them.
    let handleScale = 2.5

    private var watching: AnyCancellable?
    private var gesture: Gesture = .none
    private var draft: [Vec2] = []
    private var hover: Vec2?
    private var spaceDown = false

    private enum Gesture {
        case none
        case press(at: Vec2, hit: Item?)
        case move(from: Vec2, start: RoadDocument, began: Bool)
        case rotate(pivot: Vec2, from: Double, start: RoadDocument, began: Bool)
        case box(from: Vec2, to: Vec2)
        case pan(last: NSPoint)
        case place(from: Vec2, to: Vec2)
    }

    init() {
        super.init(frame: .zero, device: nil)
        renderer = Renderer(view: self)
        delegate = renderer
        isPaused = true
        enableSetNeedsDisplay = true
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    private func observe() {
        watching = model?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
        frameAll()
    }

    // MARK: Coordinates

    func world(_ p: NSPoint) -> Vec2 {
        centre + (Vec2(p.x, p.y) - Vec2(bounds.width, bounds.height) / 2) / scale
    }

    func world(_ event: NSEvent) -> Vec2 { world(convert(event.locationInWindow, from: nil)) }

    func frameAll() {
        guard let model else { return }
        let t = model.doc.tiles
        let proj = model.doc.projection
        let (a, _) = proj.tileRect(x: t.x0, y: t.y1)
        let (_, b) = proj.tileRect(x: t.x1, y: t.y0)
        centre = (a + b) / 2
        let w = max(bounds.width, 400), h = max(bounds.height, 300)
        scale = min(w / (b.x - a.x), h / (b.y - a.y)) * 0.95
        needsDisplay = true
    }

    private func zoom(by factor: Double, at p: NSPoint) {
        let before = world(p)
        scale = min(max(scale * factor, 0.05), 400)
        centre += before - world(p)
        needsDisplay = true
    }

    // MARK: Picking

    private var tolerance: Double { 7 / scale }
    private var handlesShown: Bool { (model?.showHandles ?? false) && scale >= handleScale }

    /// The rings and lines whose points can be picked: every area and line
    /// or zigzag marking when handles show, else only selected ones.
    private func pickable() -> [(Owner, Int, [Vec2])] {
        guard let model else { return [] }
        var out: [(Owner, Int, [Vec2])] = []
        let owners = Set(model.selection.compactMap { item -> Owner? in
            switch item {
            case .vertex(let o, _, _): o
            case .area(let a): .area(a)
            case .marking(let m): .marking(m)
            default: nil
            }
        })
        for (i, a) in model.doc.areas.enumerated() where handlesShown || owners.contains(.area(i)) {
            for (r, ring) in a.rings.enumerated() { out.append((.area(i), r, ring)) }
        }
        for (i, m) in model.doc.markings.enumerated() where !m.points.isEmpty && (handlesShown || owners.contains(.marking(i))) {
            out.append((.marking(i), 0, m.points))
        }
        return out
    }

    private func hitVertex(_ p: Vec2) -> Item? {
        var best: (Double, Item)?
        for (owner, ring, pts) in pickable() {
            for (i, q) in pts.enumerated() {
                let d = (q - p).length
                if d < tolerance && d < (best?.0 ?? .infinity) { best = (d, .vertex(owner, ring: ring, index: i)) }
            }
        }
        return best?.1
    }

    private func hitMarking(_ p: Vec2) -> Item? {
        guard let model, model.showMarkings else { return nil }
        for (i, m) in model.doc.markings.enumerated().reversed() {
            switch m.kind {
            case "zebra":
                if winding(MarkingShapes.zebraZone(m), p) != 0 { return .marking(i) }
            case "letter":
                if (m.centre - p).length < 1.6 + tolerance { return .marking(i) }
            default:
                let pts = m.kind == "zigzag" ? MarkingShapes.zigzag(m) : m.points
                for k in 0..<max(0, pts.count - 1) where (nearestOnSegment(p, pts[k], pts[k + 1]).0 - p).length < tolerance + 0.2 {
                    return .marking(i)
                }
            }
        }
        return nil
    }

    private func hitShelter(_ p: Vec2) -> Item? {
        guard let model else { return nil }
        return model.doc.shelters.indices.reversed().first { winding(MarkingShapes.shelterRect(model.doc.shelters[$0]), p) != 0 }
            .map { .shelter($0) }
    }

    /// The nearest edge of an area or a line within reach: its ring, the
    /// index of its first point and the nearest point on it.
    private func hitEdge(_ p: Vec2) -> (Owner, Int, Int, Vec2)? {
        guard let model else { return nil }
        var best: (Double, (Owner, Int, Int, Vec2))?
        func scan(_ owner: Owner, _ ring: Int, _ pts: [Vec2], closed: Bool) {
            let n = pts.count
            for i in 0..<(closed ? n : n - 1) {
                let (q, _) = nearestOnSegment(p, pts[i], pts[(i + 1) % n])
                let d = (q - p).length
                if d < tolerance && d < (best?.0 ?? .infinity) { best = (d, (owner, ring, i, q)) }
            }
        }
        for (i, a) in model.doc.areas.enumerated() {
            for (r, ring) in a.rings.enumerated() { scan(.area(i), r, ring, closed: true) }
        }
        for (i, m) in model.doc.markings.enumerated() where m.kind == "line" {
            scan(.marking(i), 0, m.points, closed: false)
        }
        return best?.1
    }

    private func hitArea(_ p: Vec2) -> Item? {
        guard let model else { return nil }
        return model.doc.areas.indices.reversed().first { a in
            model.doc.areas[a].rings.reduce(0) { $0 + winding($1, p) } != 0
        }.map { .area($0) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model else { return }
        let p = world(event)
        if spaceDown {
            gesture = .pan(last: event.locationInWindow)
            return
        }
        switch model.tool {
        case .select:
            if event.clickCount == 2, let (owner, ring, index, q) = hitEdge(p) {
                model.insertPoint(owner, ring, after: index, at: q)
                gesture = .none
                return
            }
            var hit = hitVertex(p) ?? hitMarking(p) ?? hitShelter(p)
            // A whole area only with command: a click on the roadway must not
            // pick up the whole network.
            if hit == nil && event.modifierFlags.contains(.command) { hit = hitArea(p) }
            if let hit {
                if event.modifierFlags.contains(.shift) {
                    if model.selection.contains(hit) { model.selection.remove(hit) } else { model.selection.insert(hit) }
                } else if !model.selection.contains(hit) {
                    model.selection = [hit]
                }
                if event.modifierFlags.contains(.option), let pivot = model.selectionCentre {
                    gesture = .rotate(pivot: pivot, from: (p - pivot).angle, start: model.doc, began: false)
                } else {
                    gesture = .move(from: p, start: model.doc, began: false)
                }
            } else {
                if !event.modifierFlags.contains(.shift) { model.selection = [] }
                gesture = .box(from: p, to: p)
            }
        case .addArea, .cutArea, .line:
            if model.tool != .line, draft.count >= 3, (draft[0] - p).length < tolerance {
                finishDraft()
            } else if event.clickCount == 2 && model.tool == .line {
                finishDraft()
            } else {
                draft.append(p)
            }
        case .zebra, .zigzag:
            gesture = .place(from: p, to: p)
        case .letter:
            model.addMarking(.init(id: "", kind: "letter", centre: p, heading: 90))
        case .shelter:
            model.addShelter(at: p, heading: 0)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let p = world(event)
        switch gesture {
        case let .move(from, start, began):
            if !began { model.beginGesture("Move") }
            var d = p - from
            if event.modifierFlags.contains(.shift) {
                // Along the nearest 15 degree direction.
                let a = (d.angle / 15).rounded() * 15
                d = Vec2.fromAngle(a) * d.length
            }
            model.moveSelection(by: d, from: start)
            gesture = .move(from: from, start: start, began: true)
        case let .rotate(pivot, from, start, began):
            if !began { model.beginGesture("Rotate") }
            var a = (p - pivot).angle - from
            if event.modifierFlags.contains(.shift) { a = (a / 5).rounded() * 5 }
            model.rotateSelection(by: a, around: pivot, from: start)
            gesture = .rotate(pivot: pivot, from: from, start: start, began: true)
        case let .box(from, _):
            gesture = .box(from: from, to: p)
        case let .pan(last):
            let now = event.locationInWindow
            centre -= Vec2(now.x - last.x, now.y - last.y) / scale
            gesture = .pan(last: now)
        case let .place(from, _):
            gesture = .place(from: from, to: p)
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        switch gesture {
        case let .box(from, to):
            selectBox(from, to, adding: event.modifierFlags.contains(.shift))
        case let .place(from, to):
            let d = to - from
            if d.length > 1 {
                if model.tool == .zebra {
                    // Dragged across the road: the bars run square to the drag.
                    model.addMarking(.init(id: "", kind: "zebra", centre: (from + to) / 2,
                                           heading: d.angle - 90, span: d.length))
                } else {
                    model.addMarking(.init(id: "", kind: "zigzag", points: [from, to]))
                }
            }
        default:
            break
        }
        gesture = .none
        needsDisplay = true
    }

    private func selectBox(_ a: Vec2, _ b: Vec2, adding: Bool) {
        guard let model else { return }
        let lo = simd_min(a, b), hi = simd_max(a, b)
        func inside(_ p: Vec2) -> Bool { p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y }
        var picked: Set<Item> = []
        for (owner, ring, pts) in pickable() {
            for (i, q) in pts.enumerated() where inside(q) { picked.insert(.vertex(owner, ring: ring, index: i)) }
        }
        for (i, m) in model.doc.markings.enumerated() where m.points.isEmpty && inside(m.centre) {
            picked.insert(.marking(i))
        }
        for (i, s) in model.doc.shelters.enumerated() where inside(s.position) { picked.insert(.shelter(i)) }
        model.selection = adding ? model.selection.union(picked) : picked
    }

    override func mouseMoved(with event: NSEvent) {
        hover = world(event)
        if !draft.isEmpty { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func rightMouseDown(with event: NSEvent) { gesture = .pan(last: event.locationInWindow) }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { gesture = .none }
    override func otherMouseDown(with event: NSEvent) { gesture = .pan(last: event.locationInWindow) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { gesture = .none }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            centre += Vec2(-event.scrollingDeltaX, event.scrollingDeltaY) / scale
            needsDisplay = true
        } else {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
            zoom(by: exp(dy), at: convert(event.locationInWindow, from: nil))
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    // MARK: Keys

    private func finishDraft() {
        guard let model else { return }
        switch model.tool {
        case .addArea: model.addArea(draft, op: "add")
        case .cutArea: model.addArea(draft, op: "cut")
        case .line where draft.count >= 2:
            model.addMarking(.init(id: "", kind: "line", style: "dashed", points: draft))
        default: break
        }
        draft = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let model else { return }
        let shift = event.modifierFlags.contains(.shift)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117:       // delete, forward delete
            if !draft.isEmpty { draft.removeLast() } else { model.deleteSelection() }
        case 36, 76:        // return, enter
            finishDraft()
        case 53:            // escape
            if !draft.isEmpty { draft = [] } else if model.tool != .select { model.tool = .select } else { model.selection = [] }
        case 123: model.nudge(Vec2(shift ? -1 : -0.1, 0))
        case 124: model.nudge(Vec2(shift ? 1 : 0.1, 0))
        case 125: model.nudge(Vec2(0, shift ? -1 : -0.1))
        case 126: model.nudge(Vec2(0, shift ? 1 : 0.1))
        case 49:            // space: pan while held
            spaceDown = true
            NSCursor.openHand.set()
        default:
            let key = (event.charactersIgnoringModifiers ?? "").lowercased()
            switch key {
            case "s": model.straighten(keep: shift)
            case "r": model.roundCorners()
            case "d": model.simplifySelection()
            case "[": model.turn(shift ? 5 : 1)
            case "]": model.turn(shift ? -5 : -1)
            case "f": frameAll()
            case "h": model.showHandles.toggle()
            case "x": flipZigzags()
            default:
                if let tool = Tool.allCases.first(where: { $0.key.lowercased() == key }) {
                    draft = []
                    model.tool = tool
                } else {
                    super.keyDown(with: event)
                }
            }
        }
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceDown = false
            NSCursor.arrow.set()
        }
    }

    private func flipZigzags() {
        guard let model else { return }
        let ms = model.selection.compactMap { if case .marking(let m) = $0, model.doc.markings[m].kind == "zigzag" { m } else { nil } }
        guard !ms.isEmpty else { return }
        model.change("Flip Zigzag") { doc in for m in ms { doc.markings[m].side *= -1 } }
    }

    // MARK: The overlay

    /// What changes with every gesture: handles, the selection, drafts and
    /// the selection box. Built for each frame, for the points in view only.
    func overlay() -> Mesh {
        var m = Mesh()
        guard let model else { return m }
        let lo = world(NSPoint(x: 0, y: 0)), hi = world(NSPoint(x: bounds.width, y: bounds.height))
        func visible(_ p: Vec2) -> Bool { p.x >= lo.x - 2 && p.x <= hi.x + 2 && p.y >= lo.y - 2 && p.y <= hi.y + 2 }

        let selected = model.selection
        for (owner, ring, pts) in pickable() {
            if case .marking = owner {
                m.pixelPolyline(pts, width: 1, Colours.draft)
            }
            for (i, p) in pts.enumerated() where visible(p) {
                let on = selected.contains(.vertex(owner, ring: ring, index: i))
                m.pixelSquare(p, size: on ? 9 : 7, Colours.handleEdge)
                m.pixelSquare(p, size: on ? 7 : 5, on ? Colours.selected : Colours.handle)
            }
        }
        for item in selected {
            switch item {
            case .marking(let i):
                let k = model.doc.markings[i]
                switch k.kind {
                case "zebra": m.pixelPolyline(MarkingShapes.zebraZone(k), closed: true, width: 2, Colours.selected)
                case "letter":
                    for r in MarkingShapes.letterRings(k) { m.pixelPolyline(r, closed: true, width: 2, Colours.selected) }
                case "zigzag": m.pixelPolyline(MarkingShapes.zigzag(k), width: 2, Colours.selected)
                default: m.pixelPolyline(k.points, width: 2, Colours.selected)
                }
                // Its heading.
                if k.kind == "zebra" || k.kind == "letter" {
                    m.pixelLine(k.centre, k.centre + Vec2.fromAngle(k.heading) * (24 / scale), width: 2, Colours.selected)
                }
            case .shelter(let i):
                m.pixelPolyline(MarkingShapes.shelterRect(model.doc.shelters[i]), closed: true, width: 2.5, Colours.selected)
            case .area(let i):
                for r in model.doc.areas[i].rings { m.pixelPolyline(r, closed: true, width: 2, Colours.selected) }
            default:
                break
            }
        }
        if model.showCentreLines {
            for p in model.context.crossings where visible(p) { m.pixelSquare(p, size: 5, Colours.crossing) }
            for p in model.context.stops where visible(p) { m.pixelSquare(p, size: 7, Colours.stop) }
        }
        if !draft.isEmpty {
            let pts = draft + (hover.map { [$0] } ?? [])
            m.pixelPolyline(pts, closed: model.tool != .line, width: 2, Colours.draft)
            for p in draft { m.pixelSquare(p, size: 7, Colours.draft) }
        }
        switch gesture {
        case let .box(a, b):
            m.pixelPolyline([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, width: 1, Colours.draft)
        case let .place(a, b):
            m.pixelLine(a, b, width: 2, Colours.draft)
        default:
            break
        }
        return m
    }
}
