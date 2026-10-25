import SwiftUI

/// The map drawn: OpenStreetMap under the grid of z15 tiles, each coloured
/// by what the workspace has of it, a selection box over it.
struct MapCanvas: View {
    let workspace: Workspace
    let camera: MapCamera
    let raster: RasterTiles
    var box: (CGPoint, CGPoint)?

    var body: some View {
        // Read here, so the map is drawn again as OpenStreetMap's tiles come.
        let _ = raster.images.count
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
                if r.width > 90 {
                    ctx.draw(Text(verbatim: t.name).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.85)),
                             at: CGPoint(x: r.minX + 5, y: r.minY + 4), anchor: .topLeading)
                }
            }
        }
    }
}
