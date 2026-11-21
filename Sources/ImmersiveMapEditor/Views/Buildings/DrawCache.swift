import Geometry
import SwiftUI

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
        let monument: Bool
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
            built[b.id] = Drawn(path: p, bounds: p.boundingRect, note: note, isPart: b.isPart, monument: b.monument, label: label)
        }
        tiles[key] = built
        order.append(key)
        if order.count > 4 { tiles[order.removeFirst()] = nil }
        return built
    }

    /// The catalog's buildings in batches, one a look: outlines then
    /// parts, each plain, named, notable, a landmark's (`marked`), a
    /// landmark's with its 3D model (`modelled`), one the agent gave up on
    /// (`skipped`) or picked; made again only when the tile or one of those
    /// sets changes.
    func batches(of catalog: OsmBuildings, picked: Set<String>, marked: Set<String>, modelled: Set<String>, skipped: Set<String>) -> [Batch] {
        let drawn = drawn(of: catalog)
        let key = "\(catalog.tile?.name ?? "")/\(catalog.all.count)/\(picked.count):\(picked.hashValue)/\(marked.count):\(marked.hashValue)/\(modelled.count):\(modelled.hashValue)/\(skipped.count):\(skipped.hashValue)"
        if key == batchKey { return batchesKept }
        enum Look: Int, CaseIterable { case plain, named, notable, monument, marked, skipped, modelled, picked }
        var paths: [Bool: [Look: Path]] = [false: [:], true: [:]]
        for b in catalog.all {
            guard let d = drawn[b.id] else { continue }
            let look: Look = picked.contains(b.id) ? .picked : modelled.contains(b.id) ? .modelled : skipped.contains(b.id) ? .skipped : marked.contains(b.id) ? .marked : d.monument ? .monument
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
                // A landmark the agent gave up on red: tried, no references found.
                case .skipped: Color(red: 0.86, green: 0.25, blue: 0.22).opacity(0.6)
                // A landmark with its 3D model green: done, where orange still waits.
                case .modelled: Color(red: 0.36, green: 0.68, blue: 0.30).opacity(0.6)
                // A monument amber: not a building, a thing on a pedestal.
                case .monument: Color(red: 0.85, green: 0.62, blue: 0.2).opacity(0.7)
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
