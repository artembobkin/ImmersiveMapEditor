import Foundation
import Geometry
import GLTF

/// Windows where the atlas shows none: on the model's own rhythm, from its
/// geometry, or on a grid of bays (the recipe's or the ordinary building's).
extension Imported {
    /// Windows on the model's own rhythm, from its geometry: the sides of its
    /// pilasters and piers (faces square to the wall within `pierReach` in
    /// front of it) give the bays, a window centred between two neighbours;
    /// the tops and soffits of its cornices and string courses (faces looking
    /// up or down there) give the storeys, a window in each. nil if the wall
    /// has fewer than two bays and one storey of that rhythm.
    static func geometryWindows(_ faces: [Face], _ members: [Int]) -> Wall? {
        let wall = members.map { faces[$0] }
        let n = wall[0].normal
        if abs(n.z) > 0.1 { return nil }
        let up = V3(0, 0, 1)
        let along = V3(-n.y, n.x, 0).normalized
        let origin = wall[0].corners[0]
        let outline = Geometry.unaryUnion(wall.filter { $0.area > 1e-6 }.map { f in
            Geometry.polygon(f.corners.map { P2(($0 - origin).dot(along), ($0 - origin).z) })
        })
        if outline.isEmpty || outline.area < 25 { return nil }
        let (x0, y0, x1, y1) = outline.bounds
        let inside = Set(members)
        var piers: [Double] = [], levels: [Double] = []
        for (i, f) in faces.enumerated() where !inside.contains(i) {
            let pts = f.corners.map { c -> (Double, Double, Double) in
                let d = c - origin
                return (d.dot(along), d.z, d.dot(n))
            }
            if !pts.allSatisfy({ -0.05 <= $0.2 && $0.2 <= pierReach }) { continue }
            if !pts.allSatisfy({ x0 - 0.5 <= $0.0 && $0.0 <= x1 + 0.5 }) { continue }
            if abs(f.normal.dot(along)) > 0.9 {
                let us = pts.map(\.0), zs = pts.map(\.1)
                if zs.max()! - zs.min()! > 2.0 { piers.append(us.reduce(0, +) / Double(us.count)) }
            } else if abs(f.normal.z) > 0.9 {
                levels.append(pts.map(\.1).reduce(0, +) / Double(pts.count))
            }
        }
        func cluster(_ values: [Double], _ gap: Double) -> [Double] {
            var out: [[Double]] = []
            for v in values.sorted() {
                if let last = out.last?.last, v - last < gap {
                    out[out.count - 1].append(v)
                } else {
                    out.append([v])
                }
            }
            return out.map { $0.reduce(0, +) / Double($0.count) }
        }
        piers = cluster(piers, 0.6)
        levels = [y0] + cluster(levels, 0.8).filter { y0 + 2.5 < $0 && $0 < y1 - 1.0 } + [y1]
        levels = cluster(levels, 2.5)
        let ((wlo, _), _) = windowSize
        let inner = outline.buffer(-0.3)
        var rects: [Geometry] = []
        for (a, c) in zip(piers, piers.dropFirst()) {
            let gap = c - a
            if !(1.8 <= gap && gap <= 9.0) { continue }
            let w = min(max(gap * 0.45, wlo), 3.0)
            let mid = (a + c) / 2
            for (lo, hi) in zip(levels, levels.dropFirst()) {
                let storey = hi - lo
                if storey < 2.6 { continue }
                let h = min(storey * 0.55, 4.0)
                let sill = lo + (storey - h) * 0.45
                let r = Geometry.box(mid - w / 2, sill, mid + w / 2, sill + h)
                if inner.contains(r) { rects.append(r) }
            }
        }
        if rects.count < 2 { return nil }
        return Wall(origin: origin, along: along, up: up, n: n, outline: outline, rects: rects)
    }

    /// For a flat wall whose atlas shows no windows the detector can read:
    /// the window grid of an ordinary building, storeys of about a floor,
    /// bays of a bay, windows of the ordinary size, those that fit whole in
    /// the wall. With `bays` (the recipe's), its pitch, storey, window and
    /// plinth instead. nil if the wall is too small for one row.
    static func gridWindows(_ faces: [Face], _ bays: [String: Any]?) -> Wall? {
        let n = faces[0].normal
        if abs(n.z) > 0.1 { return nil }
        let up = V3(0, 0, 1)
        let along = V3(-n.y, n.x, 0).normalized
        let origin = faces[0].corners[0]
        let tris = faces.map { f in Geometry.polygon(f.corners.map { P2(($0 - origin).dot(along), ($0 - origin).dot(up)) }) }
        let outline = Geometry.unaryUnion(tris.filter { $0.area > 1e-6 })
        if outline.isEmpty || outline.area < 25 { return nil }
        var (x0, y0, x1, y1) = outline.bounds
        if y1 - y0 < 3.5 || x1 - x0 < 3.0 { return nil }
        let spec = bays ?? [:]
        func number(_ key: String, _ fallback: Double) -> Double { (spec[key] as? NSNumber)?.doubleValue ?? fallback }
        let plinth = number("plinth", 0)
        let floors = max(1, Int(((y1 - y0 - plinth) / number("storey", Facade.floor)).rounded(.toNearestOrEven)))
        let storey = (y1 - y0 - plinth) / Double(floors)
        let count = Int(((x1 - x0 - 2 * Facade.corner) / number("pitch", Facade.bay)).rounded(.down))
        if count < 1 { return nil }
        let pitch = (x1 - x0 - 2 * Facade.corner) / Double(count)
        let size = (spec["window"] as? [NSNumber])?.map(\.doubleValue) ?? [Facade.windowWidth, Facade.windowHeight]
        let w = size[0]
        let h = min(size[1], storey * 0.7)
        y0 += plinth
        _ = y1
        let inner = outline.buffer(-0.3)
        var rects: [Geometry] = []
        for k in 0..<floors {
            let sill = y0 + Double(k) * storey + max(0.6, (storey - h) * 0.55)
            for j in 0..<count {
                let cx = x0 + Facade.corner + (Double(j) + 0.5) * pitch
                let r = Geometry.box(cx - w / 2, sill, cx + w / 2, sill + h)
                if inner.contains(r) { rects.append(r) }
            }
        }
        if rects.isEmpty { return nil }
        return Wall(origin: origin, along: along, up: up, n: n, outline: outline, rects: rects)
    }
}
