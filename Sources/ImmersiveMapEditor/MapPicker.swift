import ImageIO
import Observation
import SwiftUI

/// Where the Map view looks: its centre in Web Mercator units (0...1, Y
/// down) and its zoom.
@Observable
@MainActor
final class MapCamera {
    var centre = SIMD2<Double>(0.5, 0.5)
    var zoom = 14.0

    var pointsPerUnit: Double { 256 * pow(2, zoom) }

    func unit(_ p: CGPoint, in size: CGSize) -> SIMD2<Double> {
        centre + (SIMD2(p.x, p.y) - SIMD2(size.width, size.height) / 2) / pointsPerUnit
    }

    func point(_ u: SIMD2<Double>, in size: CGSize) -> CGPoint {
        let s = (u - centre) * pointsPerUnit + SIMD2(size.width, size.height) / 2
        return CGPoint(x: s.x, y: s.y)
    }

    func tile(at p: CGPoint, in size: CGSize) -> TileKey {
        let u = unit(p, in: size)
        let n = pow(2, Double(Workspace.zoom))
        return TileKey(z: Workspace.zoom, x: Int((u.x * n).rounded(.down)), y: Int((u.y * n).rounded(.down)))
    }

    func rect(_ t: TileKey, in size: CGSize) -> CGRect {
        let n = pow(2, Double(t.z))
        let a = point(SIMD2(Double(t.x) / n, Double(t.y) / n), in: size)
        let b = point(SIMD2(Double(t.x + 1) / n, Double(t.y + 1) / n), in: size)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    /// Zooms toward a point of the view: the point under it stays under it.
    func zoom(to z: Double, keeping p: CGPoint, in size: CGSize) {
        let before = unit(p, in: size)
        zoom = min(19, max(3, z))
        centre += before - unit(p, in: size)
    }

    /// Over the tiles the workspace has, or Moscow's centre.
    func frame(_ workspace: Workspace) {
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
    }

    /// The raster tiles in view, at the zoom drawn.
    func rasterTiles(in size: CGSize) -> [(Int, Int, Int)] {
        let z = min(19, max(2, Int(zoom.rounded())))
        let n = pow(2, Double(z))
        let lo = unit(.zero, in: size), hi = unit(CGPoint(x: size.width, y: size.height), in: size)
        let x0 = max(0, Int((lo.x * n).rounded(.down))), x1 = min(Int(n) - 1, Int((hi.x * n).rounded(.down)))
        let y0 = max(0, Int((lo.y * n).rounded(.down))), y1 = min(Int(n) - 1, Int((hi.y * n).rounded(.down)))
        guard x1 >= x0, y1 >= y0, (x1 - x0 + 1) * (y1 - y0 + 1) < 400 else { return [] }
        return (y0...y1).flatMap { y in (x0...x1).map { (z, $0, y) } }
    }
}

/// OpenStreetMap's raster tiles, from memory, from the disk cache, or
/// fetched with the User-Agent the usage policy asks for, only those on
/// screen.
@Observable
@MainActor
final class RasterTiles {
    private(set) var images: [String: CGImage] = [:]
    @ObservationIgnored private var loading = Set<String>()
    @ObservationIgnored private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ImmersiveMapEditor/osm")
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = ["User-Agent": "ImmersiveMapEditor/0.1 (+https://github.com/artembobkin/ImmersiveMapEditor)"]
        return URLSession(configuration: config)
    }()

    /// The tile if it is here, else nil and it is on its way.
    func image(_ z: Int, _ x: Int, _ y: Int) -> CGImage? {
        let key = "\(z)/\(x)/\(y)"
        if let i = images[key] { return i }
        if !loading.contains(key) {
            loading.insert(key)
            Task { await load(key) }
        }
        return nil
    }

    /// Every tile of the list, waited for.
    func prefetch(_ tiles: [(Int, Int, Int)]) async {
        await withTaskGroup(of: Void.self) { group in
            for (z, x, y) in tiles where images["\(z)/\(x)/\(y)"] == nil {
                group.addTask { await self.load("\(z)/\(x)/\(y)") }
            }
        }
    }

    private func load(_ key: String) async {
        defer { loading.remove(key) }
        let file = folder.appendingPathComponent("\(key).png")
        var data = try? Data(contentsOf: file)
        if data == nil, let url = URL(string: "https://tile.openstreetmap.org/\(key).png"),
           let (fetched, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fetched.write(to: file)
            data = fetched
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        images[key] = image
    }
}

/// The map drawn: OpenStreetMap under the grid of z15 tiles, each coloured
/// by what the workspace has of it, a selection box over it.
struct MapCanvas: View {
    let workspace: Workspace
    let camera: MapCamera
    let raster: RasterTiles
    var box: (CGPoint, CGPoint)?

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.9, green: 0.89, blue: 0.87)))
            for (z, x, y) in camera.rasterTiles(in: size) {
                if let image = raster.image(z, x, y) {
                    let r = camera.rect(TileKey(z: z, x: x, y: y), in: size).insetBy(dx: -0.3, dy: -0.3)
                    ctx.draw(Image(decorative: image, scale: 1), in: r)
                }
            }
            // A veil, so the grid's colours read over the map.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.25)))
            grid(&ctx, size)
            if let (a, b) = box {
                let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                ctx.fill(Path(r), with: .color(.blue.opacity(0.15)))
                ctx.stroke(Path(r), with: .color(.blue), lineWidth: 1)
            }
            ctx.draw(Text("© OpenStreetMap contributors").font(.system(size: 11)).foregroundStyle(.secondary),
                     at: CGPoint(x: size.width - 6, y: size.height - 4), anchor: .bottomTrailing)
        }
    }

    private func grid(_ ctx: inout GraphicsContext, _ size: CGSize) {
        guard camera.zoom >= 11 else { return }
        let z = Workspace.zoom
        let n = pow(2, Double(z))
        let lo = camera.unit(.zero, in: size), hi = camera.unit(CGPoint(x: size.width, y: size.height), in: size)
        let x0 = Int((lo.x * n).rounded(.down)), x1 = Int((hi.x * n).rounded(.down))
        let y0 = Int((lo.y * n).rounded(.down)), y1 = Int((hi.y * n).rounded(.down))
        guard x1 >= x0, y1 >= y0, (x1 - x0 + 1) * (y1 - y0 + 1) < 5000 else { return }
        let shown = Set(workspace.shown)
        for y in y0...y1 {
            for x in x0...x1 {
                let t = TileKey(z: z, x: x, y: y)
                let r = camera.rect(t, in: size)
                if workspace.built.contains(t) {
                    ctx.fill(Path(r), with: .color(.green.opacity(0.28)))
                } else if workspace.fetched.contains(t) {
                    ctx.fill(Path(r), with: .color(.yellow.opacity(0.3)))
                }
                let picked = workspace.selection.contains(t)
                if picked { ctx.fill(Path(r), with: .color(.blue.opacity(0.3))) }
                ctx.stroke(Path(r), with: .color(.black.opacity(0.25)), lineWidth: 1)
                if workspace.document(holding: t) != nil {
                    ctx.stroke(Path(r.insetBy(dx: 2, dy: 2)), with: .color(.purple.opacity(0.8)), lineWidth: 1.5)
                }
                if picked { ctx.stroke(Path(r.insetBy(dx: 1, dy: 1)), with: .color(.blue), lineWidth: 2.5) }
                if shown.contains(t) {
                    ctx.stroke(Path(r.insetBy(dx: 4, dy: 4)), with: .color(.orange),
                               style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                if r.width > 70 {
                    ctx.draw(Text(verbatim: "\(x)/\(y)").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.85)),
                             at: CGPoint(x: r.minX + 5, y: r.minY + 4), anchor: .topLeading)
                }
            }
        }
    }
}

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
                    workspace.shown = [t]
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
