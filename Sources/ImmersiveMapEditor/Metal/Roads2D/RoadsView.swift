import AppKit
import MetalKit
import Observation

/// The Roads view: a top view of the road document in Metal. It only turns
/// AppKit's events into the tool's calls, pans and zooms the view, and maps
/// keys to the editor's commands. Picking is RoadHitTest's, editing the
/// tools' and the editor's, drawing RoadsRenderer's.
final class RoadsView: MTKView {
    var model: RoadEditor? {
        didSet {
            watch()
            frameAll()
        }
    }
    private(set) var transform = ViewTransform2D()
    /// The working tile: the view shows it alone, and only what lies in it
    /// is picked and edited.
    var focus: TileKey? {
        didSet { needsDisplay = true }
    }
    /// The working tile in the document's metres, when the document holds it.
    var focusRect: (Vec2, Vec2)? {
        guard let model, let focus, (model.doc.tiles.x0...model.doc.tiles.x1).contains(focus.x),
              (model.doc.tiles.y0...model.doc.tiles.y1).contains(focus.y) else { return nil }
        return model.doc.projection.tileRect(x: focus.x, y: focus.y)
    }
    /// Whether the press the drag and release belong to began in the tile.
    private var editing = false
    private var renderer: RoadsRenderer?
    private var tool: RoadToolHandler = SelectTool()
    private var toolKind = Tool.select
    private var panning: NSPoint?
    private var spaceDown = false
    /// Handles show from this scale up, so a whole block is not a cloud of them.
    private let handleScale = 2.5

    init() {
        super.init(frame: .zero, device: nil)
        renderer = RoadsRenderer(view: self)
        delegate = renderer
        isPaused = true
        enableSetNeedsDisplay = true
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    /// Draws again whenever what the view shows of the model changes
    /// (Observation: the reads below are what is tracked).
    private func watch() {
        guard let model else { return }
        withObservationTracking {
            _ = (model.revision, model.selection, model.tool, model.layers.buildings, model.layers.centreLines,
                 model.layers.markings, model.layers.handles, model.layers.satellite, model.layers.imagery,
                 model.layers.satelliteOpacity, model.layers.roadwayOpacity)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.needsDisplay = true
                self?.watch()
            }
        }
    }

    /// Frames the working tile, or the document's tiles with none.
    func frameAll() {
        guard let model else { return }
        if let focus, (model.doc.tiles.x0...model.doc.tiles.x1).contains(focus.x),
           (model.doc.tiles.y0...model.doc.tiles.y1).contains(focus.y) {
            return frame(tiles: [focus])
        }
        let t = model.doc.tiles, proj = model.doc.projection
        transform.frame(proj.tileRect(x: t.x0, y: t.y1).0, proj.tileRect(x: t.x1, y: t.y0).1, in: bounds.size)
        needsDisplay = true
    }

    /// Frames some tiles of the document (the ones picked on the map).
    func frame(tiles: [TileKey]) {
        guard let model, !tiles.isEmpty else { return frameAll() }
        let proj = model.doc.projection
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        transform.frame(proj.tileRect(x: xs.min()!, y: ys.max()!).0, proj.tileRect(x: xs.max()!, y: ys.min()!).1, in: bounds.size)
        needsDisplay = true
    }

    // MARK: The tool

    /// The handler of the editor's tool, made again when the tool changes.
    private func currentTool() -> RoadToolHandler {
        if let model, model.tool != toolKind {
            toolKind = model.tool
            tool = toolKind.makeHandler()
        }
        return tool
    }

    private func context() -> ToolContext? {
        guard let model else { return nil }
        return ToolContext(editor: model, hits: hits(model))
    }

    private func hits(_ model: RoadEditor) -> RoadHitTest {
        RoadHitTest(doc: model.doc, selection: model.selection, tolerance: 7 / transform.scale,
                    handlesShown: model.layers.handles && transform.scale >= handleScale, markingsShown: model.layers.markings,
                    limit: focusRect)
    }

    private func pointer(_ event: NSEvent) -> Pointer {
        let f = event.modifierFlags
        return Pointer(at: transform.world(convert(event.locationInWindow, from: nil), in: bounds.size),
                       clicks: event.clickCount, shift: f.contains(.shift), option: f.contains(.option),
                       command: f.contains(.command))
    }

    /// What the renderer draws over the document.
    func overlay() -> Mesh {
        guard let model else { return Mesh() }
        return RoadOverlay.mesh(model, hits: hits(model), transform: transform, size: bounds.size, preview: currentTool().preview)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if spaceDown {
            panning = event.locationInWindow
            return
        }
        guard let ctx = context() else { return }
        // A press outside the working tile edits nothing.
        let p = pointer(event)
        editing = ctx.hits.within(p.at)
        guard editing else { return }
        currentTool().down(p, ctx)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if pan(event) { return }
        guard editing, let ctx = context() else { return }
        currentTool().drag(pointer(event), ctx)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if panning != nil {
            panning = nil
            return
        }
        guard editing, let ctx = context() else { return }
        editing = false
        currentTool().up(pointer(event), ctx)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        currentTool().hover(pointer(event).at)
        if case .draft = tool.preview { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    /// Right and other buttons pan, as does the left one while space is held.
    private func pan(_ event: NSEvent) -> Bool {
        guard let last = panning else { return false }
        let now = event.locationInWindow
        transform.pan(by: CGSize(width: now.x - last.x, height: now.y - last.y))
        panning = now
        needsDisplay = true
        return true
    }

    override func rightMouseDown(with event: NSEvent) { panning = event.locationInWindow }
    override func rightMouseDragged(with event: NSEvent) { _ = pan(event) }
    override func rightMouseUp(with event: NSEvent) { panning = nil }
    override func otherMouseDown(with event: NSEvent) { panning = event.locationInWindow }
    override func otherMouseDragged(with event: NSEvent) { _ = pan(event) }
    override func otherMouseUp(with event: NSEvent) { panning = nil }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            transform.pan(by: CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY))
        } else {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
            transform.zoom(by: exp(dy), at: convert(event.locationInWindow, from: nil), in: bounds.size)
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        transform.zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil), in: bounds.size)
        needsDisplay = true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let model, let ctx = context() else { return }
        let shift = event.modifierFlags.contains(.shift)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        let tool = currentTool()
        switch event.keyCode {
        case 51, 117:       // delete, forward delete
            if !tool.back() { model.deleteSelection() }
        case 36, 76:        // return, enter
            _ = tool.commit(ctx)
        case 53:            // escape
            if tool.cancel() {} else if model.tool != .select { model.tool = .select } else { model.selection = [] }
        case 123: model.nudge(Vec2(shift ? -1 : -0.1, 0))
        case 124: model.nudge(Vec2(shift ? 1 : 0.1, 0))
        case 125: model.nudge(Vec2(0, shift ? -1 : -0.1))
        case 126: model.nudge(Vec2(0, shift ? 1 : 0.1))
        case 49:            // space: pan while held
            spaceDown = true
            NSCursor.openHand.set()
        default:
            switch (event.charactersIgnoringModifiers ?? "").lowercased() {
            case "s": model.straighten(keep: shift)
            case "r": model.roundCorners()
            case "d": model.simplifySelection()
            case "[": model.turn(shift ? 5 : 1)
            case "]": model.turn(shift ? -5 : -1)
            case "f": frameAll()
            case "h": model.layers.handles.toggle()
            case "i": model.layers.satellite.toggle()
            case "x": model.flipZigzags()
            case let key:
                if let next = Tool.allCases.first(where: { $0.key.lowercased() == key }) {
                    model.tool = next
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
}
