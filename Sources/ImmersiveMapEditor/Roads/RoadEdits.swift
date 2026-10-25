import Foundation
import Geometry
import simd

/// The edits of the Roads view as plain operations on a plan: no state, no
/// undo, no saving (RoadEditor wraps them in those), so each can be checked
/// on its own. Each takes the selection it works on, by ids. The mutating
/// ones change the plan's objects in place: RoadEditor gives them a copy.
/// What an object is, its objects decide (RoadObject).
extension RoadPlan {
    // MARK: Points

    func points(_ owner: String, _ ring: Int) -> [Vec2] {
        guard let rings = object(owner)?.rings, ring < rings.count else { return [] }
        return rings[ring]
    }

    func setPoints(_ owner: String, _ ring: Int, _ pts: [Vec2]) {
        guard let o = object(owner), ring < o.rings.count else { return }
        o.rings[ring] = pts
    }

    func isClosed(_ owner: String) -> Bool { object(owner)?.closedRings ?? false }

    /// The centre of what is selected.
    func centre(of selection: Set<Item>) -> Vec2? {
        var pts: [Vec2] = []
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index):
                let ring = points(owner, ring)
                if index < ring.count { pts.append(ring[index]) }
            case .object(let id):
                if let o = object(id) { pts.append(o.anchor) }
            }
        }
        return pts.isEmpty ? nil : pts.reduce(.zero, +) / Double(pts.count)
    }

    /// The box around what is selected as it is drawn, nil when nothing is.
    func bounds(of selection: Set<Item>) -> (Vec2, Vec2)? {
        var pts: [Vec2] = []
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index):
                let ring = points(owner, ring)
                if index < ring.count { pts.append(ring[index]) }
            case .object(let id):
                pts += object(id)?.outline.flatMap { $0 } ?? []
            }
        }
        guard let first = pts.first else { return nil }
        return pts.reduce((first, first)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
    }

    // MARK: Moving, turning, scaling

    /// A copy with everything selected moved by `f`: a point alone, an
    /// object whole, turned by `turn` degrees and its sizes times `scale`.
    func transformed(_ selection: Set<Item>, turn: Double = 0, scale: Double = 1, _ f: (Vec2) -> Vec2) -> RoadPlan {
        let next = copy()
        for id in selection.objects { next.object(id)?.transform(f, turn: turn, scale: scale) }
        // Points from the original, into the rings as moved so far: several
        // points of one ring move together.
        for case let .vertex(owner, ring, index) in selection {
            var pts = next.points(owner, ring)
            let from = points(owner, ring)
            guard index < pts.count, index < from.count else { continue }
            pts[index] = f(from[index])
            next.setPoints(owner, ring, pts)
        }
        return next
    }

    func moved(_ selection: Set<Item>, by d: Vec2) -> RoadPlan { transformed(selection) { $0 + d } }

    func rotated(_ selection: Set<Item>, by degrees: Double, around pivot: Vec2) -> RoadPlan {
        transformed(selection, turn: degrees) { $0.rotated(degrees, around: pivot) }
    }

    /// Everything selected `factor` times as large about `pivot`, the
    /// objects' sizes too.
    func scaled(_ selection: Set<Item>, by factor: Double, around pivot: Vec2) -> RoadPlan {
        transformed(selection, scale: factor) { pivot + ($0 - pivot) * factor }
    }

    /// Each selected object turned about itself.
    func turn(_ selection: Set<Item>, by degrees: Double) {
        for id in selection.objects { object(id)?.turn(by: degrees) }
    }

    // MARK: Editing points

    /// A new point on edge `index`→`index + 1` of a ring or line.
    func insert(_ p: Vec2, _ owner: String, _ ring: Int, after index: Int) {
        var pts = points(owner, ring)
        pts.insert(p, at: min(index + 1, pts.count))
        setPoints(owner, ring, pts)
    }

    /// What is selected deleted: objects, and points (a ring keeps its
    /// object's fewest; fewer and the hole, or the object, goes).
    mutating func delete(_ selection: Set<Item>) {
        var dead = Set(selection.objects)
        for (owner, ring, indices) in selection.rings {
            guard let o = object(owner), !dead.contains(owner), ring < o.rings.count else { continue }
            var pts = o.rings[ring]
            for i in indices.reversed() where i < pts.count { pts.remove(at: i) }
            if pts.count >= o.minimumPoints {
                o.rings[ring] = pts
            } else if ring == 0 {
                dead.insert(owner)
            } else {
                o.rings.remove(at: ring)
            }
        }
        remove(dead)
    }

    /// The run of a ring a straighten or simplify works on: from the first to
    /// the last selected point, the shorter way round a closed ring when two
    /// points are selected, else the way that holds them all.
    func run(_ owner: String, _ ring: Int, _ indices: [Int]) -> [Int]? {
        let n = points(owner, ring).count
        guard indices.count >= 2, indices.allSatisfy({ $0 < n }) else { return nil }
        if !isClosed(owner) { return Array(indices.first!...indices.last!) }
        if indices.count == 2 {
            let (a, b) = (indices[0], indices[1])
            let forward = b - a, backward = n - forward
            return forward <= backward ? Array(a...b) : (0...backward).map { (b + $0) % n }
        }
        // The largest gap between selected points is where the run is open.
        var gapAt = indices.count - 1, gap = indices[0] + n - indices.last!
        for i in 0..<(indices.count - 1) where indices[i + 1] - indices[i] > gap {
            gap = indices[i + 1] - indices[i]
            gapAt = i
        }
        let start = indices[(gapAt + 1) % indices.count], end = indices[gapAt]
        return (0...((end - start + n) % n)).map { (start + $0) % n }
    }

    func runs(_ selection: Set<Item>) -> [(String, Int, [Int])] {
        selection.rings.compactMap { g in run(g.0, g.1, g.2).map { (g.0, g.1, $0) } }
    }

    /// The points between the ends of each selected run dropped: a straight
    /// edge. With `keep`, they stay, moved onto it. False when no run is
    /// selected.
    @discardableResult
    func straighten(_ selection: Set<Item>, keep: Bool = false) -> Bool {
        let work = runs(selection)
        for (owner, ring, run) in work {
            var pts = points(owner, ring)
            let a = pts[run.first!], b = pts[run.last!]
            let inner = Array(run.dropFirst().dropLast())
            if keep {
                for i in inner { pts[i] = nearestOnSegment(pts[i], a, b).0 }
            } else {
                for i in inner.sorted(by: >) { pts.remove(at: i) }
            }
            setPoints(owner, ring, pts)
        }
        return !work.isEmpty
    }

    /// Each selected corner rounded with `radius`. False when none is.
    @discardableResult
    func roundCorners(_ selection: Set<Item>, radius: Double) -> Bool {
        let groups = selection.rings
        for (owner, ring, indices) in groups {
            var pts = points(owner, ring)
            for i in indices.sorted(by: >) where i < pts.count {
                let n = pts.count
                if !isClosed(owner) && (i == 0 || i == n - 1) { continue }
                pts.replaceSubrange(i...i, with: fillet(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n], radius: radius))
            }
            setPoints(owner, ring, pts)
        }
        return !groups.isEmpty
    }

    /// The selected runs, or whole selected areas, simplified within
    /// `tolerance`. Returns the points before and after, nil when nothing
    /// fit to simplify is selected.
    func simplify(_ selection: Set<Item>, tolerance: Double) -> (Int, Int)? {
        let whole = selection.objects.compactMap { object($0) }.filter(\.closedRings), work = runs(selection)
        guard !whole.isEmpty || !work.isEmpty else { return nil }
        var before = 0, after = 0
        for o in whole {
            o.rings = o.rings.map { ring in
                before += ring.count
                let s = ImmersiveMapEditor.simplify(ring + [ring[0]], tolerance: tolerance).dropLast()
                after += s.count
                return s.count >= o.minimumPoints ? Array(s) : ring
            }
        }
        for (owner, ring, run) in work {
            var pts = points(owner, ring)
            let kept = ImmersiveMapEditor.simplify(run.map { pts[$0] }, tolerance: tolerance)
            before += run.count
            after += kept.count
            let dropped = Set(run).subtracting(Set(run.filter { kept.contains(pts[$0]) }))
            pts = pts.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
            setPoints(owner, ring, pts)
        }
        return (before, after)
    }
}
