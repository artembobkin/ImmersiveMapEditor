import AppKit
import Combine

/// The map to pick tiles on: OpenStreetMap's own raster tiles under the
/// grid of z15 tiles, each coloured by what TilePipeline has of it.
///
/// Drag to move, scroll or pinch to zoom at the cursor (as in the engine).
/// A click picks or drops a tile, shift-drag picks a box of them, a
/// double-click shows a built tile in 3D.
///
/// The raster tiles come from tile.openstreetmap.org, as its usage policy
/// asks: a User-Agent naming the app, kept on disk and in memory, fetched
/// only for what is on screen, attributed on the map.
final class MapPicker: NSView {
    let workspace: Workspace
    /// The view's centre in Web Mercator units (0...1, Y down) and its zoom.
    private var centre = SIMD2<Double>(0.5, 0.5)
    private var zoom = 14.0
    private var lastDrag: NSPoint?
    private var moved = false
    private var box: (NSPoint, NSPoint)?
    private var watching: AnyCancellable?
    private let raster = RasterTiles()

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(frame: .zero)
        raster.changed = { [weak self] in self?.needsDisplay = true }
        watching = workspace.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
        frameWork()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Coordinates

    private var pointsPerUnit: Double { 256 * pow(2, zoom) }

    private func unit(_ p: NSPoint) -> SIMD2<Double> {
        centre + (SIMD2(p.x, p.y) - SIMD2(bounds.width, bounds.height) / 2) / pointsPerUnit
    }

    private func point(_ u: SIMD2<Double>) -> NSPoint {
        let s = (u - centre) * pointsPerUnit + SIMD2(bounds.width, bounds.height) / 2
        return NSPoint(x: s.x, y: s.y)
    }

    private func tile(at p: NSPoint) -> TileKey {
        let u = unit(p)
        let n = pow(2, Double(Workspace.zoom))
        return TileKey(z: Workspace.zoom, x: Int((u.x * n).rounded(.down)), y: Int((u.y * n).rounded(.down)))
    }

    private func rect(_ t: TileKey) -> NSRect {
        let n = pow(2, Double(t.z))
        let a = point(SIMD2(Double(t.x) / n, Double(t.y) / n)), b = point(SIMD2(Double(t.x + 1) / n, Double(t.y + 1) / n))
        return NSRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    /// Over the tiles TilePipeline has, or Moscow's centre.
    func frameWork() {
        let tiles = workspace.shown.isEmpty ? Array(workspace.built.union(workspace.fetched)) : workspace.shown
        let n = pow(2, Double(Workspace.zoom))
        if tiles.isEmpty {
            let lat = 55.7539 * .pi / 180
            centre = SIMD2((37.6208 + 180) / 360, (1 - asinh(tan(lat)) / .pi) / 2)
            zoom = 13
        } else {
            let xs = tiles.map { Double($0.x) }, ys = tiles.map { Double($0.y) }
            centre = SIMD2((xs.min()! + xs.max()! + 1) / 2 / n, (ys.min()! + ys.max()! + 1) / 2 / n)
            zoom = 14
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirty: NSRect) {
        NSColor(calibratedRed: 0.9, green: 0.89, blue: 0.87, alpha: 1).setFill()
        bounds.fill()
        let z = min(19, max(2, Int(zoom.rounded())))
        let n = pow(2, Double(z))
        let lo = unit(.zero), hi = unit(NSPoint(x: bounds.width, y: bounds.height))
        let x0 = max(0, Int((lo.x * n).rounded(.down))), x1 = min(Int(n) - 1, Int((hi.x * n).rounded(.down)))
        let y0 = max(0, Int((lo.y * n).rounded(.down))), y1 = min(Int(n) - 1, Int((hi.y * n).rounded(.down)))
        if x1 >= x0 && y1 >= y0 && (x1 - x0 + 1) * (y1 - y0 + 1) < 400 {
            for y in y0...y1 {
                for x in x0...x1 {
                    let r = rect(TileKey(z: z, x: x, y: y))
                    raster.image(z: z, x: x, y: y)?.draw(in: r.insetBy(dx: -0.3, dy: -0.3))
                }
            }
        }
        // A veil, so the grid's colours read over the map.
        NSColor(white: 1, alpha: 0.25).setFill()
        bounds.fill(using: .sourceOver)
        drawGrid()
        if let (a, b) = box {
            let r = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            r.fill(using: .sourceOver)
            NSColor.systemBlue.setStroke()
            NSBezierPath(rect: r).stroke()
        }
        let credit = "© OpenStreetMap contributors" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray,
                                                    .backgroundColor: NSColor(white: 1, alpha: 0.7)]
        let size = credit.size(withAttributes: attrs)
        credit.draw(at: NSPoint(x: bounds.width - size.width - 6, y: bounds.height - size.height - 4), withAttributes: attrs)
    }

    private func drawGrid() {
        guard zoom >= 11 else { return }
        let z = Workspace.zoom
        let n = pow(2, Double(z))
        let lo = unit(.zero), hi = unit(NSPoint(x: bounds.width, y: bounds.height))
        let x0 = Int((lo.x * n).rounded(.down)), x1 = Int((hi.x * n).rounded(.down))
        let y0 = Int((lo.y * n).rounded(.down)), y1 = Int((hi.y * n).rounded(.down))
        guard (x1 - x0 + 1) * (y1 - y0 + 1) < 5000 else { return }
        let shown = Set(workspace.shown)
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                                                    .foregroundColor: NSColor(white: 0.15, alpha: 0.9)]
        for y in y0...y1 {
            for x in x0...x1 {
                let t = TileKey(z: z, x: x, y: y)
                let r = rect(t)
                let fill: NSColor? = workspace.built.contains(t) ? .systemGreen.withAlphaComponent(0.28)
                    : workspace.fetched.contains(t) ? .systemYellow.withAlphaComponent(0.3) : nil
                if let fill {
                    fill.setFill()
                    r.fill(using: .sourceOver)
                }
                if workspace.selection.contains(t) {
                    NSColor.systemBlue.withAlphaComponent(0.3).setFill()
                    r.fill(using: .sourceOver)
                }
                NSColor(white: 0.2, alpha: 0.25).setStroke()
                NSBezierPath(rect: r).stroke()
                if workspace.document(holding: t) != nil {
                    NSColor.systemPurple.withAlphaComponent(0.8).setStroke()
                    let p = NSBezierPath(rect: r.insetBy(dx: 2, dy: 2))
                    p.lineWidth = 1.5
                    p.stroke()
                }
                if workspace.selection.contains(t) {
                    NSColor.systemBlue.setStroke()
                    let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
                    p.lineWidth = 2.5
                    p.stroke()
                }
                if shown.contains(t) {
                    NSColor.systemOrange.setStroke()
                    let p = NSBezierPath(rect: r.insetBy(dx: 4, dy: 4))
                    p.lineWidth = 2
                    p.setLineDash([6, 4], count: 2, phase: 0)
                    p.stroke()
                }
                if r.width > 70 {
                    ("\(x)/\(y)" as NSString).draw(at: NSPoint(x: r.minX + 5, y: r.minY + 4), withAttributes: label)
                }
            }
        }
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        lastDrag = p
        moved = false
        if event.modifierFlags.contains(.shift) { box = (p, p) }
        if event.clickCount == 2 {
            let t = tile(at: p)
            if workspace.built.contains(t) {
                workspace.shown = [t]
                workspace.viewMode = .tiles
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let last = lastDrag else { return }
        if abs(p.x - last.x) + abs(p.y - last.y) > 0 { moved = true }
        if let (a, _) = box {
            box = (a, p)
        } else {
            centre -= SIMD2(p.x - last.x, p.y - last.y) / pointsPerUnit
            lastDrag = p
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let (a, b) = box {
            let ta = tile(at: a), tb = tile(at: b)
            for y in min(ta.y, tb.y)...max(ta.y, tb.y) {
                for x in min(ta.x, tb.x)...max(ta.x, tb.x) { workspace.selection.insert(TileKey(z: ta.z, x: x, y: y)) }
            }
            box = nil
        } else if !moved && event.clickCount == 1 {
            let t = tile(at: p)
            if workspace.selection.contains(t) { workspace.selection.remove(t) } else { workspace.selection.insert(t) }
        }
        lastDrag = nil
        needsDisplay = true
    }

    /// Zooms toward the cursor: the point under it stays under it.
    private func zoom(by dz: Double, at p: NSPoint) {
        let before = unit(p)
        zoom = min(19, max(3, zoom + dz))
        centre += before - unit(p)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 6
        zoom(by: dy, at: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        zoom(by: log2(1 + event.magnification), at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "f" { frameWork() } else { super.keyDown(with: event) }
    }
}

/// OpenStreetMap's raster tiles, from memory, from the disk cache, or
/// fetched (a few at a time, with the User-Agent the usage policy asks for).
final class RasterTiles {
    var changed: () -> Void = {}
    private let memory = NSCache<NSString, NSImage>()
    private var loading = Set<String>()
    private let folder: URL
    private let session: URLSession

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImmersiveMapEditor/osm")
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = ["User-Agent": "ImmersiveMapEditor/0.1 (+https://github.com/artembobkin/ImmersiveMapEditor)"]
        session = URLSession(configuration: config)
        memory.countLimit = 600
    }

    func image(z: Int, x: Int, y: Int) -> NSImage? {
        let key = "\(z)/\(x)/\(y)"
        if let i = memory.object(forKey: key as NSString) { return i }
        let file = folder.appendingPathComponent("\(key).png")
        if let i = NSImage(contentsOf: file) {
            memory.setObject(i, forKey: key as NSString)
            return i
        }
        guard !loading.contains(key), let url = URL(string: "https://tile.openstreetmap.org/\(key).png") else { return nil }
        loading.insert(key)
        session.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(key)
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200, let i = NSImage(data: data) else { return }
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file)
                self.memory.setObject(i, forKey: key as NSString)
                self.changed()
            }
        }.resume()
        return nil
    }
}
