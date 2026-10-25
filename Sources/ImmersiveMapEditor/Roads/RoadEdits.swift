import Foundation
import simd
import Geometry

/// The edits of the Roads view as plain operations on a document: no
/// state, no undo, no saving (RoadEditor wraps them in those), so each can
/// be checked on its own. Each takes the selection it works on.
extension RoadPlan {
    // MARK: Points

    func points(_ owner: Owner, _ ring: Int) -> [Vec2] {
        switch owner {
        case .area(let a): areas[a].rings[ring]
        case .marking(let m): markings[m].points
        }
    }

    mutating func setPoints(_ owner: Owner, _ ring: Int, _ pts: [Vec2]) {
        switch owner {
        case .area(let a): areas[a].rings[ring] = pts
        case .marking(let m): markings[m].points = pts
        }
    }

    static func isClosed(_ owner: Owner) -> Bool {
        if case .area = owner { return true }
        return false
    }

    /// The centre of what is selected.
    func centre(of selection: Set<Item>) -> Vec2? {
        var pts: [Vec2] = []
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index): pts.append(points(owner, ring)[index])
            case .marking(let m): pts.append(markings[m].anchor)
            case .shelter(let s): pts.append(shelters[s].position)
            case .area(let a): pts.append(contentsOf: areas[a].rings[0])
            }
        }
        return pts.isEmpty ? nil : pts.reduce(.zero, +) / Double(pts.count)
    }

    // MARK: Moving and turning

    /// Everything selected moved by `f`, markings and shelters turned by
    /// `turn` degrees with it (0 for a move), the markings' sizes times
    /// `scale` (1 for a move or a turn).
    func transformed(_ selection: Set<Item>, turn: Double = 0, scale: Double = 1, _ f: (Vec2) -> Vec2) -> RoadPlan {
        var next = self
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index):
                // From the original, into the ring as moved so far: several
                // points of one ring move together.
                var pts = next.points(owner, ring)
                pts[index] = f(points(owner, ring)[index])
                next.setPoints(owner, ring, pts)
            case .marking(let m):
                next.markings[m].centre = f(markings[m].centre)
                next.markings[m].points = markings[m].points.map(f)
                next.markings[m].heading = markings[m].heading + turn
                if scale != 1 {
                    // Its size with it: a zebra's width and bars' length, a
                    // letter's height, a zigzag's teeth. A bar stays a bar.
                    let k = markings[m]
                    next.markings[m].span = max(1, k.span * scale)
                    next.markings[m].length = max(0.5, k.length * scale)
                    next.markings[m].size = max(0.3, k.size * scale)
                    next.markings[m].step = max(0.5, k.step * scale)
                    next.markings[m].depth = k.depth * scale
                }
            case .shelter(let s):
                next.shelters[s].position = f(shelters[s].position)
                next.shelters[s].heading = shelters[s].heading + turn
            case .area(let a):
                next.areas[a].rings = areas[a].rings.map { $0.map(f) }
            }
        }
        return next
    }

    func moved(_ selection: Set<Item>, by d: Vec2) -> RoadPlan { transformed(selection) { $0 + d } }

    func rotated(_ selection: Set<Item>, by degrees: Double, around pivot: Vec2) -> RoadPlan {
        transformed(selection, turn: degrees) { $0.rotated(degrees, around: pivot) }
    }

    /// Everything selected `factor` times as large about `pivot`, the
    /// markings' sizes too.
    func scaled(_ selection: Set<Item>, by factor: Double, around pivot: Vec2) -> RoadPlan {
        transformed(selection, scale: factor) { pivot + ($0 - pivot) * factor }
    }

    /// The box around what is selected as it is drawn (a marking's shape,
    /// not only its anchor), nil when nothing is.
    func bounds(of selection: Set<Item>) -> (Vec2, Vec2)? {
        var pts: [Vec2] = []
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index): pts.append(points(owner, ring)[index])
            case .marking(let m):
                let k = markings[m]
                switch k.kind {
                case "zebra": pts += MarkingShapes.zebraZone(k)
                case "letter": pts += MarkingShapes.letterRings(k).flatMap { $0 }
                case "zigzag": pts += MarkingShapes.zigzag(k)
                default: pts += k.points
                }
            case .shelter(let s): pts += MarkingShapes.shelterRect(shelters[s])
            case .area(let a): pts += areas[a].rings[0]
            }
        }
        guard let first = pts.first else { return nil }
        return pts.reduce((first, first)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
    }

    /// Each selected marking and shelter turned about itself.
    mutating func turn(_ selection: Set<Item>, by degrees: Double) {
        for m in selection.markings {
            let c = markings[m].anchor
            markings[m].heading += degrees
            markings[m].points = markings[m].points.map { $0.rotated(degrees, around: c) }
        }
        for s in selection.shelters { shelters[s].heading += degrees }
    }

    // MARK: Editing points

    /// A new point on edge `index`→`index + 1` of a ring or line.
    mutating func insert(_ p: Vec2, _ owner: Owner, _ ring: Int, after index: Int) {
        var pts = points(owner, ring)
        pts.insert(p, at: index + 1)
        setPoints(owner, ring, pts)
    }

    /// What is selected deleted: points (a ring keeps three, a line two;
    /// fewer and the hole, area or marking goes), markings, shelters, areas.
    mutating func delete(_ selection: Set<Item>) {
        var deadAreas = Set(selection.areas), deadMarkings = Set(selection.markings)
        let deadShelters = Set(selection.shelters)
        var deadHoles: [Int: Set<Int>] = [:]
        for (owner, ring, indices) in selection.rings {
            var pts = points(owner, ring)
            for i in indices.reversed() { pts.remove(at: i) }
            switch owner {
            case .area(let a):
                if pts.count >= 3 {
                    areas[a].rings[ring] = pts
                } else if ring == 0 {
                    deadAreas.insert(a)
                } else {
                    deadHoles[a, default: []].insert(ring)
                }
            case .marking(let m):
                // A line keeps two points, a zigzag both of its own.
                if pts.count >= 2 && markings[m].kind == "line" {
                    markings[m].points = pts
                } else {
                    deadMarkings.insert(m)
                }
            }
        }
        for (a, holes) in deadHoles {
            areas[a].rings = areas[a].rings.enumerated().filter { !holes.contains($0.offset) }.map(\.element)
        }
        areas = areas.enumerated().filter { !deadAreas.contains($0.offset) }.map(\.element)
        markings = markings.enumerated().filter { !deadMarkings.contains($0.offset) }.map(\.element)
        shelters = shelters.enumerated().filter { !deadShelters.contains($0.offset) }.map(\.element)
    }

    /// The run of a ring a straighten or simplify works on: from the first to
    /// the last selected point, the shorter way round a closed ring when two
    /// points are selected, else the way that holds them all.
    func run(_ owner: Owner, _ ring: Int, _ indices: [Int]) -> [Int]? {
        let n = points(owner, ring).count
        guard indices.count >= 2 else { return nil }
        if !Self.isClosed(owner) { return Array(indices.first!...indices.last!) }
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

    func runs(_ selection: Set<Item>) -> [(Owner, Int, [Int])] {
        selection.rings.compactMap { g in run(g.0, g.1, g.2).map { (g.0, g.1, $0) } }
    }

    /// The points between the ends of each selected run dropped: a straight
    /// edge. With `keep`, they stay, moved onto it. False when no run is
    /// selected.
    @discardableResult
    mutating func straighten(_ selection: Set<Item>, keep: Bool = false) -> Bool {
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
    mutating func roundCorners(_ selection: Set<Item>, radius: Double) -> Bool {
        let groups = selection.rings
        for (owner, ring, indices) in groups {
            var pts = points(owner, ring)
            for i in indices.sorted(by: >) {
                let n = pts.count
                if !Self.isClosed(owner) && (i == 0 || i == n - 1) { continue }
                pts.replaceSubrange(i...i, with: fillet(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n], radius: radius))
            }
            setPoints(owner, ring, pts)
        }
        return !groups.isEmpty
    }

    /// The selected runs, or whole selected areas, simplified within
    /// `tolerance`. Returns the points before and after, nil when nothing
    /// fit to simplify is selected.
    mutating func simplify(_ selection: Set<Item>, tolerance: Double) -> (Int, Int)? {
        let whole = selection.areas, work = runs(selection)
        guard !whole.isEmpty || !work.isEmpty else { return nil }
        var before = 0, after = 0
        for a in whole {
            areas[a].rings = areas[a].rings.map { ring in
                before += ring.count
                let s = ImmersiveMapEditor.simplify(ring + [ring[0]], tolerance: tolerance).dropLast()
                after += s.count
                return s.count >= 3 ? Array(s) : ring
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

    // MARK: Adding

    /// A new area, its ring wound counter-clockwise. Returns its index.
    mutating func addArea(_ pts: [Vec2], op: String) -> Int {
        let ring = signedArea(pts) < 0 ? Array(pts.reversed()) : pts
        areas.append(Area(id: newID("a"), op: op, rings: [ring]))
        return areas.count - 1
    }

    mutating func addMarking(_ m: Marking) -> Int {
        var m = m
        m.id = newID(Self.letter(of: m.kind))
        markings.append(m)
        return markings.count - 1
    }

    mutating func addShelter(at p: Vec2, heading: Double) -> Int {
        shelters.append(Shelter(id: newID("s"), position: p, heading: heading))
        return shelters.count - 1
    }
}
