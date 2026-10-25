import Foundation
import Observation

/// The road document open in the Roads view: the document, what is selected,
/// the tool and its settings, what is shown. Every change goes through
/// `change`, so it is one step of the window's undo and is saved by the
/// store. The edits themselves are RoadPlan's (RoadEdits.swift).
@Observable
@MainActor
final class RoadEditor {
    var doc: RoadPlan
    var selection: Set<Item> = []
    var tool: Tool = .select
    var settings = ToolSettings()
    var layers = Layers()
    let store: DocumentStore
    let context: Underlay
    /// Bumped whenever the document's geometry changes, so views rebuild.
    private(set) var revision = 0
    /// The window's undo manager, given by the view (`@Environment(\.undoManager)`).
    @ObservationIgnored weak var undo: UndoManager?
    @ObservationIgnored private var index = RoadwayIndex()

    /// The point tools' parameters.
    struct ToolSettings {
        var cornerRadius = 4.0
        var tolerance = 0.3
    }

    /// What the Roads view draws.
    struct Layers {
        var buildings = true
        var centreLines = true
        var markings = true
        var handles = true
        /// Mapbox's satellite imagery under the document.
        var satellite = false
    }

    init(url: URL) throws {
        store = DocumentStore(url: url)
        let doc = try RoadPlan.read(url)
        self.doc = doc
        context = Underlay.read(store.root.appendingPathComponent("data/regions/\(doc.name)/context.json"), doc.projection)
    }

    var url: URL { store.url }
    var dirty: Bool { store.dirty }
    var status: String { store.status }

    // MARK: Changes, undo and saving

    /// Changes the document as one step of undo.
    func change(_ name: String, select: Set<Item>? = nil, _ body: (inout RoadPlan) -> Void) {
        let before = doc, selected = selection
        body(&doc)
        if let select { selection = select }
        registerUndo(name, before, selected)
        touched()
    }

    /// Marks the start of a change made in many small steps (a drag): undo
    /// goes back to here.
    func beginGesture(_ name: String) {
        registerUndo(name, doc, selection)
    }

    /// The document as a gesture has it now (no undo step: `beginGesture`
    /// made it).
    func apply(_ next: RoadPlan) {
        doc = next
        touched()
    }

    private func registerUndo(_ name: String, _ before: RoadPlan, _ selected: Set<Item>) {
        undo?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                let now = editor.doc, nowSelected = editor.selection
                editor.doc = before
                editor.selection = selected
                editor.registerUndo(name, now, nowSelected)
                editor.touched()
            }
        }
        undo?.setActionName(name)
    }

    private func touched() {
        revision += 1
        store.changed { [weak self] in
            guard let self else { return }
            try doc.write(url)
        }
    }

    func save() { store.save { try doc.write(url) } }

    func saveIfNeeded() { if dirty { save() } }

    // MARK: Edits

    func nudge(_ d: Vec2) {
        guard !selection.isEmpty else { return }
        beginGesture("Move")
        apply(doc.moved(selection, by: d))
    }

    func turn(_ degrees: Double) {
        guard !selection.markings.isEmpty || !selection.shelters.isEmpty else { return }
        change("Rotate") { $0.turn(selection, by: degrees) }
    }

    func insertPoint(_ owner: Owner, _ ring: Int, after index: Int, at p: Vec2) {
        change("Add Point", select: [.vertex(owner, ring: ring, index: index + 1)]) { $0.insert(p, owner, ring, after: index) }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        change("Delete", select: []) { $0.delete(selection) }
    }

    func straighten(keep: Bool = false) {
        guard !doc.runs(selection).isEmpty else {
            store.say("Straighten: select two points of a ring, or a run of them")
            return
        }
        change(keep ? "Align" : "Straighten", select: []) { $0.straighten(selection, keep: keep) }
    }

    func roundCorners() {
        guard !selection.rings.isEmpty else {
            store.say("Round: select corners")
            return
        }
        change("Round Corner", select: []) { $0.roundCorners(selection, radius: settings.cornerRadius) }
    }

    func simplifySelection() {
        var test = doc
        guard let (before, after) = test.simplify(selection, tolerance: settings.tolerance) else {
            store.say("Simplify: select a run of points or an area")
            return
        }
        change("Simplify", select: []) { _ = $0.simplify(selection, tolerance: settings.tolerance) }
        store.say("Simplified \(before) points to \(after)")
    }

    func flipZigzags() {
        let zigzags = selection.markings.filter { doc.markings[$0].kind == "zigzag" }
        guard !zigzags.isEmpty else { return }
        change("Flip Zigzag") { doc in for m in zigzags { doc.markings[m].side *= -1 } }
    }

    func addArea(_ pts: [Vec2], op: String) {
        guard pts.count >= 3 else { return }
        var made = 0
        change(op == "add" ? "Add Roadway" : "Cut Roadway") { made = $0.addArea(pts, op: op) }
        selection = [.area(made)]
    }

    func addMarking(_ m: RoadPlan.Marking) {
        var made = 0
        change("Add \(m.kind.capitalized)") { made = $0.addMarking(m) }
        selection = [.marking(made)]
    }

    func addShelter(at p: Vec2, heading: Double) {
        var made = 0
        change("Add Shelter") { made = $0.addShelter(at: p, heading: heading) }
        selection = [.shelter(made)]
    }

    // MARK: The roadway

    /// Whether a point is on the roadway: inside the added areas and outside
    /// the cut ones.
    func onRoadway(_ p: Vec2) -> Bool {
        if index.revision != revision { index = RoadwayIndex(doc, revision) }
        return index.onRoadway(p)
    }
}
