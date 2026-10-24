import MetalKit
import SwiftUI

/// What the window shows: the workspace, its views, and the road document
/// open in the Roads view, if any.
final class Session: ObservableObject {
    let workspace: Workspace
    let picker: MapPicker
    let tiles: TileView?
    @Published private(set) var model: EditorModel?
    @Published private(set) var roads: MapView?

    init(workspace: Workspace) {
        self.workspace = workspace
        picker = MapPicker(workspace: workspace)
        tiles = TileView(model: workspace)
    }

    /// Opens a road document in the Roads view.
    func open(_ url: URL) throws {
        let model = try EditorModel(url: url)
        let view = MapView()
        view.model = model
        self.model = model
        roads = view
        DispatchQueue.main.async { view.frameAll() }
    }
}

/// The window's content: the view of the mode, beside it its panel, under
/// it a line of hints and state.
struct ContentView: View {
    @ObservedObject var session: Session
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    switch workspace.viewMode {
                    case .map:
                        ViewHost(view: session.picker)
                    case .roads:
                        if let roads = session.roads { ViewHost(view: roads) } else { placeholder }
                    case .tiles:
                        if let tiles = session.tiles { ViewHost(view: tiles) } else { placeholder }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack(spacing: 0) {
                    Picker("", selection: $workspace.viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                    switch workspace.viewMode {
                    case .map:
                        MapInspector(session: session, workspace: workspace)
                    case .roads:
                        if let model = session.model, let roads = session.roads {
                            Inspector(model: model, map: roads)
                        } else {
                            Spacer()
                        }
                    case .tiles:
                        TilesInspector(workspace: workspace, view: session.tiles)
                    }
                }
                .frame(width: 280)
            }
            Divider()
            StatusLine(session: session, workspace: workspace)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
    }

    var placeholder: some View {
        Text("Pick a tile with roads on the Map, then Edit Roads.").foregroundStyle(.secondary)
    }
}

struct StatusLine: View {
    @ObservedObject var session: Session
    @ObservedObject var workspace: Workspace

    var body: some View {
        HStack {
            switch workspace.viewMode {
            case .map:
                Text("Drag to move, scroll to zoom. Click picks a tile, shift-drag a box of them, double-click shows a built one in 3D.")
                    .lineLimit(1)
                Spacer()
            case .roads:
                if let model = session.model { RoadsStatus(model: model) }
            case .tiles:
                Text(workspace.flying
                    ? "Flight: W A S D, Q down, E up, shift faster, right-drag to look, scroll for speed. Tab to orbit."
                    : "Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom to the cursor. Tab flies, F frames, L light map.")
                    .lineLimit(1)
                Spacer()
                Text(workspace.tileStatus).lineLimit(1).foregroundStyle(.secondary)
            }
        }
    }
}

struct RoadsStatus: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        Text(model.tool.hint).lineLimit(1)
        Spacer()
        Text(model.status).lineLimit(1).foregroundStyle(.secondary)
    }
}

struct ViewHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.needsDisplay = true
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

/// The map's panel: what the colours mean, the tiles picked, and what to do
/// with them.
struct MapInspector: View {
    @ObservedObject var session: Session
    @ObservedObject var workspace: Workspace
    @State private var error: String?

    var body: some View {
        let picked = workspace.selection.sorted()
        let toFetch = picked.filter { !workspace.fetched.contains($0) }
        let built = picked.filter { workspace.built.contains($0) }
        let documents = Set(picked.compactMap { workspace.document(holding: $0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tiles").font(.headline)
                    legend(.systemGreen, "built")
                    legend(.systemYellow, "OSM fetched, not built")
                    legend(.systemPurple, "has a road document", outline: true)
                    legend(.systemBlue, "picked")
                    legend(.systemOrange, "shown in 3D", outline: true)
                    Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Picked: \(picked.count)").font(.headline)
                    if !picked.isEmpty {
                        Text(picked.map { "\($0.x)/\($0.y)" }.joined(separator: "  "))
                            .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(6)
                    }
                    Button("Show in 3D (\(built.count) built)") {
                        workspace.shown = built
                        workspace.viewMode = .tiles
                    }
                    .disabled(built.isEmpty)
                    Button(documents.count > 1 ? "Edit Roads (first of \(documents.count) documents)" : "Edit Roads") {
                        if let url = picked.compactMap({ workspace.document(holding: $0) }).first {
                            openRoads(url)
                        }
                    }
                    .disabled(documents.isEmpty)
                    Button("Fetch OSM and Build \(picked.count)") {
                        (NSApp.delegate as? AppDelegate)?.build(picked)
                    }
                    .disabled(picked.isEmpty || workspace.building)
                    if !toFetch.isEmpty {
                        Text("\(toFetch.count) not fetched yet: Overpass first, about half a minute each, then osm2streets and a road document for the tiles that have none.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Clear") { workspace.selection = [] }
                        .disabled(picked.isEmpty)
                    Button("Frame the work  F") { session.picker.frameWork() }
                }
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
            }
            .padding(12)
        }
    }

    func openRoads(_ url: URL) {
        guard (NSApp.delegate as? AppDelegate)?.confirmDiscard() ?? true else { return }
        do {
            try session.open(url)
            workspace.viewMode = .roads
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func legend(_ colour: NSColor, _ text: String, outline: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(outline ? Color.clear : Color(colour).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(colour), lineWidth: outline ? 2 : 0))
                .frame(width: 14, height: 14)
            Text(text).font(.callout)
        }
    }
}

/// The 3D view's panel: the tiles shown, the camera, the light map.
struct TilesInspector: View {
    @ObservedObject var workspace: Workspace
    let view: TileView?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shown: \(workspace.shown.count)").font(.headline)
                    ForEach(workspace.shown, id: \.self) { t in
                        HStack {
                            Text(verbatim: t.name).font(.callout.monospaced())
                            Spacer()
                            Button("Only") { workspace.shown = [t] }.controlSize(.small)
                            Button("Hide") { workspace.shown.removeAll { $0 == t } }.controlSize(.small)
                        }
                    }
                    Text("Pick tiles on the Map and Show in 3D to change them.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Frame  F") { view?.frameTiles() }
                    Button("Reload the built tiles") { workspace.tilesRevision += 1 }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("View").font(.headline)
                    Toggle("Fly  Tab", isOn: $workspace.flying)
                    Toggle("Light map  L", isOn: $workspace.showLightMap)
                }
                Text(workspace.tileStatus).font(.callout).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

struct Inspector: View {
    @ObservedObject var model: EditorModel
    let map: MapView

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Tool") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(Tool.allCases) { tool in
                            Button { model.tool = tool } label: {
                                HStack {
                                    Text(tool.rawValue)
                                    Spacer()
                                    Text(tool.key).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(model.tool == tool ? .accentColor : nil)
                        }
                    }
                }
                section("Points") {
                    HStack {
                        Button("Straighten  S") { model.straighten() }
                        Button("Align  ⇧S") { model.straighten(keep: true) }
                    }
                    HStack {
                        Button("Round  R") { model.roundCorners() }
                        Slider(value: $model.cornerRadius, in: 0.5...20)
                        Text("\(model.cornerRadius, specifier: "%.1f") m").monospacedDigit().frame(width: 48)
                    }
                    HStack {
                        Button("Simplify  D") { model.simplifySelection() }
                        Slider(value: $model.tolerance, in: 0.05...2)
                        Text("\(model.tolerance, specifier: "%.2f") m").monospacedDigit().frame(width: 48)
                    }
                    Button("Delete  ⌫") { model.deleteSelection() }
                }
                section("Selection") { SelectionView(model: model) }
                section("Layers") {
                    Toggle("Buildings", isOn: $model.showBuildings)
                    Toggle("OSM centre lines, crossings, stops", isOn: $model.showCentreLines)
                    Toggle("Markings", isOn: $model.showMarkings)
                    Toggle("Point handles  H", isOn: $model.showHandles)
                    Button("Frame the tiles  F") { map.frameAll() }
                }
                section("Document") {
                    Text(model.url.lastPathComponent).font(.callout.monospaced())
                    Text("\(model.doc.areas.count) areas, \(model.doc.areas.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }) points, \(model.doc.markings.count) markings, \(model.doc.shelters.count) shelters")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Seeded \(model.doc.seededDate)").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// The parameters of the one selected marking or shelter, editable.
struct SelectionView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let items = model.selection
        if items.isEmpty {
            Text("Nothing selected").foregroundStyle(.secondary)
        } else if items.count == 1, case .marking(let i) = items.first!, i < model.doc.markings.count {
            marking(i)
        } else if items.count == 1, case .shelter(let i) = items.first!, i < model.doc.shelters.count {
            Text("Shelter \(model.doc.shelters[i].id)")
            number("Heading °", { model.doc.shelters[i].heading }) { d, v in d.shelters[i].heading = v }
        } else if items.count == 1, case .area(let i) = items.first!, i < model.doc.areas.count {
            let a = model.doc.areas[i]
            Text("Area \(a.id): \(a.rings.count - 1) holes, \(a.rings.reduce(0) { $0 + $1.count }) points")
            Picker("Op", selection: Binding(get: { a.op }, set: { v in model.change("Edit") { $0.areas[i].op = v } })) {
                Text("Add roadway").tag("add")
                Text("Cut roadway").tag("cut")
            }
        } else {
            let points = items.filter { if case .vertex = $0 { true } else { false } }.count
            Text("\(items.count) selected" + (points > 0 ? ", \(points) points" : ""))
        }
    }

    @ViewBuilder
    func marking(_ i: Int) -> some View {
        let m = model.doc.markings[i]
        Text("\(m.kind.capitalized) \(m.id)")
        switch m.kind {
        case "line":
            Picker("Style", selection: Binding(get: { m.style }, set: { v in model.change("Edit") { $0.markings[i].style = v } })) {
                Text("Solid").tag("solid")
                Text("Dashed").tag("dashed")
                Text("Double").tag("double")
            }
            Picker("Colour", selection: Binding(get: { m.colour }, set: { v in model.change("Edit") { $0.markings[i].colour = v } })) {
                Text("White").tag("white")
                Text("Yellow").tag("yellow")
            }
        case "zebra":
            number("Heading °", { model.doc.markings[i].heading }) { d, v in d.markings[i].heading = v }
            number("Span m", { model.doc.markings[i].span }) { d, v in d.markings[i].span = max(1, v) }
            number("Bar m", { model.doc.markings[i].bar }) { d, v in d.markings[i].bar = max(0.1, v) }
            number("Length m", { model.doc.markings[i].length }) { d, v in d.markings[i].length = max(0.5, v) }
        case "zigzag":
            number("Step m", { model.doc.markings[i].step }) { d, v in d.markings[i].step = max(0.5, v) }
            number("Depth m", { model.doc.markings[i].depth }) { d, v in d.markings[i].depth = v }
            Button("Flip side  X") { model.change("Flip Zigzag") { $0.markings[i].side *= -1 } }
        default:
            number("Heading °", { model.doc.markings[i].heading }) { d, v in d.markings[i].heading = v }
        }
    }

    func number(_ label: String, _ get: @escaping () -> Double, _ set: @escaping (inout RoadDocument, Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: Binding(get: get, set: { v in model.change("Edit") { set(&$0, v) } }),
                      format: .number.precision(.fractionLength(0...3)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }
}
