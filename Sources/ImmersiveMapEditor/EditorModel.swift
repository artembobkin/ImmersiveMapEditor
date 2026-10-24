import Foundation
import Observation

/// A thing that can be selected.
enum Item: Hashable {
    /// A point of an area's ring or of a line or zigzag marking.
    case vertex(Owner, ring: Int, index: Int)
    case marking(Int)
    case shelter(Int)
    case area(Int)
}

enum Owner: Hashable {
    case area(Int)
    case marking(Int)
}

enum Tool: String, CaseIterable, Identifiable {
    case select = "Select"
    case addArea = "Add roadway"
    case cutArea = "Cut roadway"
    case line = "Line"
    case zebra = "Zebra"
    case zigzag = "Zigzag"
    case letter = "Letter A"
    case shelter = "Shelter"
    var id: String { rawValue }
    var key: String {
        switch self {
        case .select: "V"
        case .addArea: "A"
        case .cutArea: "C"
        case .line: "L"
        case .zebra: "Z"
        case .zigzag: "G"
        case .letter: "T"
        case .shelter: "B"
        }
    }
    var hint: String {
        switch self {
        case .select: "Click, shift-click or drag a box to select. Drag to move, option-drag to rotate markings. Double-click an edge to add a point."
        case .addArea, .cutArea: "Click the corners, Return or a click on the first point closes. Backspace drops the last point."
        case .line: "Click the points, Return finishes."
        case .zebra: "Drag across the road from kerb to kerb."
        case .zigzag: "Drag along the kerb, the roadway on the left of the drag."
        case .letter: "Click where the letter goes, then rotate it with [ and ]."
        case .shelter: "Click where the shelter stands, the road on its left; rotate with [ and ]."
        }
    }
}

/// The road document open in the Roads view, its selection and its tools.
/// Every change is one step of the window's undo, and the document saves
/// itself a moment after the last change.
@Observable
final class EditorModel {
    var doc: RoadDocument
    var selection: Set<Item> = []
    var tool: Tool = .select
    var dirty = false
    var cornerRadius = 4.0
    var tolerance = 0.3
    var showBuildings = true
    var showCentreLines = true
    var showMarkings = true
    var showHandles = true
    var status = ""
    /// Bumped whenever the document's geometry changes, so the view rebuilds.
    private(set) var revision = 0

    let url: URL
    let context: Underlay
    /// The window's undo manager, given by the view (`@Environment(\.undoManager)`).
    @ObservationIgnored weak var undo: UndoManager?
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(url: URL) throws {
        self.url = url
        let doc = try RoadDocument.read(url)
        self.doc = doc
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        let ctx = root.appendingPathComponent("data/regions/\(doc.name)/context.json")
        context = Underlay.read(ctx, doc.projection)
    }

    /// The project's folder: roads/<name>.json sits in it.
    var root: URL { url.deletingLastPathComponent().deletingLastPathComponent() }

    // MARK: Changes and undo

    /// Changes the document as one step of undo.
    func change(_ name: String, keepSelection: Bool = true, _ body: (inout RoadDocument) -> Void) {
        let before = doc, selected = selection
        body(&doc)
        if !keepSelection { selection = [] }
        registerUndo(name, before, selected)
        touched()
    }

    /// Marks the start of a change made in many small steps (a drag): undo
    /// goes back to here.
    func beginGesture(_ name: String) {
        registerUndo(name, doc, selection)
    }

    private func registerUndo(_ name: String, _ before: RoadDocument, _ selected: Set<Item>) {
        undo?.registerUndo(withTarget: self) { model in
            let now = model.doc, nowSelected = model.selection
            model.doc = before
            model.selection = selected
            model.registerUndo(name, now, nowSelected)
            model.touched()
        }
        undo?.setActionName(name)
    }

    func touched() {
        dirty = true
        revision += 1
        // Saved a moment after the last change, as a Mac document is: a drag
        // saves once, when it stops.
        saving?.cancel()
        saving = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, self.dirty else { return }
            self.save()
        }
    }

    /// Saves now if anything is unsaved: before another document opens, the
    /// workspace changes or the app goes to the background.
    func saveIfNeeded() {
        saving?.cancel()
        if dirty { save() }
    }

    func save() {
        do {
            try doc.write(url)
            dirty = false
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Not saved: \(error.localizedDescription)"
        }
    }

    // MARK: Points

    func point(_ owner: Owner, _ ring: Int, _ index: Int) -> Vec2 {
        switch owner {
        case .area(let a): doc.areas[a].rings[ring][index]
        case .marking(let m): doc.markings[m].points[index]
        }
    }

    func ringPoints(_ owner: Owner, _ ring: Int) -> [Vec2] {
        switch owner {
        case .area(let a): doc.areas[a].rings[ring]
        case .marking(let m): doc.markings[m].points
        }
    }

    func isClosed(_ owner: Owner) -> Bool {
        if case .area = owner { return true }
        return false
    }

    static func setRing(_ doc: inout RoadDocument, _ owner: Owner, _ ring: Int, _ pts: [Vec2]) {
        switch owner {
        case .area(let a): doc.areas[a].rings[ring] = pts
        case .marking(let m): doc.markings[m].points = pts
        }
    }

    /// The selected points, grouped by the ring they belong to.
    var selectedRings: [(Owner, Int, [Int])] {
        var groups: [String: (Owner, Int, [Int])] = [:]
        for case let .vertex(owner, ring, index) in selection {
            let key = "\(owner)-\(ring)"
            groups[key, default: (owner, ring, [])].2.append(index)
        }
        return groups.values.map { ($0.0, $0.1, $0.2.sorted()) }
    }

    // MARK: Moving and rotating

    /// Moves everything selected by `d` (no undo step: the caller makes it).
    func moveSelection(by d: Vec2, from start: RoadDocument) {
        var next = start
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index):
                switch owner {
                case .area(let a): next.areas[a].rings[ring][index] = start.areas[a].rings[ring][index] + d
                case .marking(let m): next.markings[m].points[index] = start.markings[m].points[index] + d
                }
            case .marking(let m):
                next.markings[m].centre = start.markings[m].centre + d
                next.markings[m].points = start.markings[m].points.map { $0 + d }
            case .shelter(let s):
                next.shelters[s].position = start.shelters[s].position + d
            case .area(let a):
                next.areas[a].rings = start.areas[a].rings.map { $0.map { $0 + d } }
            }
        }
        doc = next
        touched()
    }

    /// The centre of what is selected.
    var selectionCentre: Vec2? {
        var pts: [Vec2] = []
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index): pts.append(point(owner, ring, index))
            case .marking(let m): pts.append(doc.markings[m].anchor)
            case .shelter(let s): pts.append(doc.shelters[s].position)
            case .area(let a): pts.append(contentsOf: doc.areas[a].rings[0])
            }
        }
        return pts.isEmpty ? nil : pts.reduce(.zero, +) / Double(pts.count)
    }

    /// Turns the selection by `degrees` around `pivot`, markings and
    /// shelters with their headings (no undo step).
    func rotateSelection(by degrees: Double, around pivot: Vec2, from start: RoadDocument) {
        var next = start
        for item in selection {
            switch item {
            case let .vertex(owner, ring, index):
                switch owner {
                case .area(let a): next.areas[a].rings[ring][index] = start.areas[a].rings[ring][index].rotated(degrees, around: pivot)
                case .marking(let m): next.markings[m].points[index] = start.markings[m].points[index].rotated(degrees, around: pivot)
                }
            case .marking(let m):
                next.markings[m].centre = start.markings[m].centre.rotated(degrees, around: pivot)
                next.markings[m].points = start.markings[m].points.map { $0.rotated(degrees, around: pivot) }
                next.markings[m].heading = start.markings[m].heading + degrees
            case .shelter(let s):
                next.shelters[s].position = start.shelters[s].position.rotated(degrees, around: pivot)
                next.shelters[s].heading = start.shelters[s].heading + degrees
            case .area(let a):
                next.areas[a].rings = start.areas[a].rings.map { $0.map { $0.rotated(degrees, around: pivot) } }
            }
        }
        doc = next
        touched()
    }

    func nudge(_ d: Vec2) {
        guard !selection.isEmpty else { return }
        beginGesture("Move")
        moveSelection(by: d, from: doc)
    }

    /// Rotates each selected marking and shelter about itself.
    func turn(_ degrees: Double) {
        let ms = selection.compactMap { if case .marking(let m) = $0 { m } else { nil } }
        let ss = selection.compactMap { if case .shelter(let s) = $0 { s } else { nil } }
        guard !ms.isEmpty || !ss.isEmpty else { return }
        change("Rotate") { doc in
            for m in ms {
                let c = doc.markings[m].anchor
                doc.markings[m].heading += degrees
                doc.markings[m].points = doc.markings[m].points.map { $0.rotated(degrees, around: c) }
            }
            for s in ss { doc.shelters[s].heading += degrees }
        }
    }

    // MARK: Editing points

    /// A new point on edge `index`→`index + 1` of a ring or line.
    func insertPoint(_ owner: Owner, _ ring: Int, after index: Int, at p: Vec2) {
        change("Add Point", keepSelection: false) { doc in
            var pts = Self.ringPointsOf(doc, owner, ring)
            pts.insert(p, at: index + 1)
            Self.setRing(&doc, owner, ring, pts)
        }
        selection = [.vertex(owner, ring: ring, index: index + 1)]
    }

    static func ringPointsOf(_ doc: RoadDocument, _ owner: Owner, _ ring: Int) -> [Vec2] {
        switch owner {
        case .area(let a): doc.areas[a].rings[ring]
        case .marking(let m): doc.markings[m].points
        }
    }

    /// Deletes what is selected: points (a ring keeps three, a line two;
    /// fewer and the hole, area or marking goes), markings, shelters, areas.
    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let rings = selectedRings
        var deadAreas = Set(selection.compactMap { if case .area(let a) = $0 { a } else { nil } })
        var deadMarkings = Set(selection.compactMap { if case .marking(let m) = $0 { m } else { nil } })
        let deadShelters = Set(selection.compactMap { if case .shelter(let s) = $0 { s } else { nil } })
        change("Delete", keepSelection: false) { doc in
            var deadHoles: [Int: Set<Int>] = [:]
            for (owner, ring, indices) in rings {
                var pts = Self.ringPointsOf(doc, owner, ring)
                for i in indices.reversed() { pts.remove(at: i) }
                switch owner {
                case .area(let a):
                    if pts.count >= 3 {
                        doc.areas[a].rings[ring] = pts
                    } else if ring == 0 {
                        deadAreas.insert(a)
                    } else {
                        deadHoles[a, default: []].insert(ring)
                    }
                case .marking(let m):
                    // A line keeps two points, a zigzag both of its own.
                    if pts.count >= 2 && doc.markings[m].kind == "line" {
                        doc.markings[m].points = pts
                    } else {
                        deadMarkings.insert(m)
                    }
                }
            }
            for (a, holes) in deadHoles {
                doc.areas[a].rings = doc.areas[a].rings.enumerated().filter { !holes.contains($0.offset) }.map(\.element)
            }
            doc.areas = doc.areas.enumerated().filter { !deadAreas.contains($0.offset) }.map(\.element)
            doc.markings = doc.markings.enumerated().filter { !deadMarkings.contains($0.offset) }.map(\.element)
            doc.shelters = doc.shelters.enumerated().filter { !deadShelters.contains($0.offset) }.map(\.element)
        }
    }

    /// The run of a ring a straighten, round or simplify works on: from the
    /// first to the last selected point, the shorter way round a closed ring
    /// when two points are selected, else the way that holds them all.
    private func run(_ owner: Owner, _ ring: Int, _ indices: [Int]) -> [Int]? {
        let n = ringPoints(owner, ring).count
        guard indices.count >= 2 else { return nil }
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
        let length = (end - start + n) % n
        return (0...length).map { (start + $0) % n }
    }

    /// The points between the ends of each selected run dropped: a straight
    /// edge. With `keep`, they stay, moved onto it.
    func straighten(keep: Bool = false) {
        let work = selectedRings.compactMap { g in run(g.0, g.1, g.2).map { (g.0, g.1, $0) } }
        guard !work.isEmpty else { status = "Straighten: select two points of a ring, or a run of them"; return }
        change(keep ? "Align" : "Straighten", keepSelection: false) { doc in
            for (owner, ring, run) in work {
                var pts = Self.ringPointsOf(doc, owner, ring)
                let a = pts[run.first!], b = pts[run.last!]
                let inner = Array(run.dropFirst().dropLast())
                if keep {
                    for i in inner { pts[i] = nearestOnSegment(pts[i], a, b).0 }
                } else {
                    for i in inner.sorted(by: >) { pts.remove(at: i) }
                }
                Self.setRing(&doc, owner, ring, pts)
            }
        }
    }

    /// Each selected corner rounded with `cornerRadius`.
    func roundCorners() {
        let groups = selectedRings
        guard !groups.isEmpty else { status = "Round: select corners"; return }
        change("Round Corner", keepSelection: false) { doc in
            for (owner, ring, indices) in groups {
                var pts = Self.ringPointsOf(doc, owner, ring)
                let closed = isClosed(owner)
                for i in indices.sorted(by: >) {
                    let n = pts.count
                    if !closed && (i == 0 || i == n - 1) { continue }
                    let arc = fillet(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n], radius: cornerRadius)
                    pts.replaceSubrange(i...i, with: arc)
                }
                Self.setRing(&doc, owner, ring, pts)
            }
        }
    }

    /// The selected runs, or whole selected areas, simplified within
    /// `tolerance`.
    func simplifySelection() {
        let areas = selection.compactMap { if case .area(let a) = $0 { a } else { nil } }
        let work = selectedRings.compactMap { g in run(g.0, g.1, g.2).map { (g.0, g.1, $0) } }
        guard !areas.isEmpty || !work.isEmpty else { status = "Simplify: select a run of points or an area"; return }
        var before = 0, after = 0
        change("Simplify", keepSelection: false) { doc in
            for a in areas {
                doc.areas[a].rings = doc.areas[a].rings.map { ring in
                    before += ring.count
                    let s = simplify(ring + [ring[0]], tolerance: tolerance).dropLast()
                    after += s.count
                    return s.count >= 3 ? Array(s) : ring
                }
            }
            for (owner, ring, run) in work {
                var pts = Self.ringPointsOf(doc, owner, ring)
                let kept = simplify(run.map { pts[$0] }, tolerance: tolerance)
                before += run.count
                after += kept.count
                let dropped = Set(run).subtracting(Set(run.filter { kept.contains(pts[$0]) }))
                pts = pts.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
                Self.setRing(&doc, owner, ring, pts)
            }
        }
        status = "Simplified \(before) points to \(after)"
    }

    // MARK: Adding

    func addArea(_ pts: [Vec2], op: String) {
        guard pts.count >= 3 else { return }
        let ring = signedArea(pts) < 0 ? Array(pts.reversed()) : pts
        change(op == "add" ? "Add Roadway" : "Cut Roadway", keepSelection: false) { doc in
            doc.areas.append(.init(id: doc.newID("a"), op: op, rings: [ring]))
        }
        selection = [.area(doc.areas.count - 1)]
    }

    func addMarking(_ m: RoadDocument.Marking) {
        var m = m
        change("Add \(m.kind.capitalized)", keepSelection: false) { doc in
            m.id = doc.newID(RoadDocument.letter(of: m.kind))
            doc.markings.append(m)
        }
        selection = [.marking(doc.markings.count - 1)]
    }

    func addShelter(at p: Vec2, heading: Double) {
        change("Add Shelter", keepSelection: false) { doc in
            doc.shelters.append(.init(id: doc.newID("s"), position: p, heading: heading))
        }
        selection = [.shelter(doc.shelters.count - 1)]
    }

    // MARK: The roadway

    /// Whether a point is on the roadway: inside the added areas and
    /// outside the cut ones (non-zero winding, holes wound the other way).
    func onRoadway(_ p: Vec2) -> Bool {
        if index.revision != revision { index = RoadwayIndex(doc, revision) }
        return index.onRoadway(p)
    }

    private var index = RoadwayIndex()
}

/// The areas' edges sorted into horizontal strips, so a point's winding
/// looks only at the edges its strip crosses.
struct RoadwayIndex {
    static let strip = 5.0
    var revision = -1
    private var strips: [Int: [(a: Vec2, b: Vec2, area: Int)]] = [:]
    private var ops: [String] = []

    init() {}

    init(_ doc: RoadDocument, _ revision: Int) {
        self.revision = revision
        ops = doc.areas.map(\.op)
        for (i, area) in doc.areas.enumerated() {
            for ring in area.rings {
                for k in ring.indices {
                    let a = ring[k], b = ring[(k + 1) % ring.count]
                    let lo = Int((min(a.y, b.y) / Self.strip).rounded(.down))
                    let hi = Int((max(a.y, b.y) / Self.strip).rounded(.down))
                    for s in lo...hi { strips[s, default: []].append((a, b, i)) }
                }
            }
        }
    }

    func onRoadway(_ p: Vec2) -> Bool {
        var w: [Int: Int] = [:]
        for (a, b, i) in strips[Int((p.y / Self.strip).rounded(.down))] ?? [] {
            if a.y <= p.y {
                if b.y > p.y && cross(b - a, p - a) > 0 { w[i, default: 0] += 1 }
            } else if b.y <= p.y && cross(b - a, p - a) < 0 {
                w[i, default: 0] -= 1
            }
        }
        let inside = w.filter { $0.value != 0 }.keys
        return inside.contains { ops[$0] == "add" } && !inside.contains { ops[$0] == "cut" }
    }
}
