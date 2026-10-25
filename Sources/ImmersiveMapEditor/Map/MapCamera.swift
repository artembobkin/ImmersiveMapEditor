import Foundation
import Observation

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
        let tiles = workspace.selection.isEmpty ? Array(workspace.built.union(workspace.fetched)) : Array(workspace.selection)
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
