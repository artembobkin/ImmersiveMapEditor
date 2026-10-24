import AppKit
import Observation
import SwiftUI

/// What the window shows: the workspace, the views of its modes, the road
/// document open in the Roads view, the build.
@Observable
@MainActor
final class Session {
    private(set) var workspace: Workspace
    let camera = MapCamera()
    let raster = RasterTiles()
    let build = BuildRunner()
    private(set) var tiles: TileView?
    private(set) var model: EditorModel?
    private(set) var roads: MapView?
    /// What went wrong last, shown as an alert.
    var problem: String?
    /// What the open dialog is asked for, if it is.
    var importing: Importing?

    enum Importing { case workspace, roads }

    init(root: URL) {
        workspace = Workspace(root: root)
        tiles = TileView(model: workspace)
        camera.frame(workspace)
        UserDefaults.standard.set(root.path, forKey: "workspace")
    }

    /// A TilePipeline folder instead of the current one.
    func open(workspace root: URL) {
        model?.saveIfNeeded()
        model = nil
        roads = nil
        workspace = Workspace(root: root)
        tiles = TileView(model: workspace)
        camera.frame(workspace)
        UserDefaults.standard.set(root.path, forKey: "workspace")
    }

    /// Opens a road document in the Roads view.
    func open(roads url: URL) {
        model?.saveIfNeeded()
        do {
            let model = try EditorModel(url: url)
            let view = MapView()
            view.model = model
            self.model = model
            roads = view
            workspace.viewMode = .roads
            Task { @MainActor in view.frameAll() }
        } catch {
            problem = "Cannot open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Fetches what is missing and builds `tiles` (the road document open is
    /// saved first), then shows them.
    func build(_ tiles: [TileKey]) {
        guard let z = tiles.first?.z else { return }
        model?.saveIfNeeded()
        let workspace = self.workspace
        workspace.building = true
        build.run(root: workspace.root, arguments: ["build", "\(z)", "--tiles"] + tiles.map { "\($0.x)/\($0.y)" }) {
            workspace.building = false
            workspace.scan()
            let built = tiles.filter { workspace.built.contains($0) }
            if !built.isEmpty { workspace.shown = built } else { workspace.tilesRevision += 1 }
        }
    }

    /// The tiles picked on the map, or else those of the road document open.
    func buildPickedOrOpen() {
        var tiles = workspace.selection.sorted()
        if workspace.viewMode != .map || tiles.isEmpty, let t = model?.doc.tiles {
            tiles = (t.y0...t.y1).flatMap { y in (t.x0...t.x1).map { TileKey(z: t.z, x: $0, y: y) } }
        }
        build(tiles)
    }
}

/// The window's content: the view of the mode, its panel in the inspector,
/// the mode in the toolbar, hints and state along the bottom.
struct ContentView: View {
    @Environment(Session.self) private var session
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var phase
    @State private var inspector = true

    var body: some View {
        @Bindable var workspace = session.workspace
        let importing = session.importing
        Group {
            switch workspace.viewMode {
            case .map:
                MapPicker()
            case .roads:
                if let roads = session.roads {
                    MetalHost(view: roads)
                } else {
                    ContentUnavailableView("No road document", systemImage: "road.lanes",
                                           description: Text("Pick a tile with roads on the Map, then Edit Roads."))
                }
            case .tiles:
                if let tiles = session.tiles { MetalHost(view: tiles) }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusLine()
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $workspace.viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button("Fetch and Build", systemImage: "hammer") {
                    session.buildPickedOrOpen()
                    openWindow(id: "build")
                }
                .disabled(session.build.running)
            }
            ToolbarItem {
                Button("Panel", systemImage: "sidebar.trailing") { inspector.toggle() }
            }
        }
        .inspector(isPresented: $inspector) {
            Group {
                switch workspace.viewMode {
                case .map: MapInspector()
                case .roads:
                    if let model = session.model, let roads = session.roads { Inspector(model: model, map: roads) }
                case .tiles: TilesInspector()
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 290, max: 400)
        }
        .navigationTitle(session.model.map { "\($0.url.lastPathComponent)\($0.dirty ? " (edited)" : "")" }
                         ?? session.workspace.root.lastPathComponent)
        .onChange(of: undoManager, initial: true) { session.model?.undo = undoManager }
        .onChange(of: session.model.map { ObjectIdentifier($0) }) { session.model?.undo = undoManager }
        .onChange(of: phase) { if phase != .active { session.model?.saveIfNeeded() } }
        .fileImporter(isPresented: Binding(get: { session.importing != nil }, set: { if !$0 { session.importing = nil } }),
                      allowedContentTypes: session.importing == .workspace ? [.folder] : [.json]) { result in
            guard let url = try? result.get() else { return }
            if importing == .workspace { session.open(workspace: url) } else { session.open(roads: url) }
        }
        .fileDialogDefaultDirectory(session.importing == .roads ? session.workspace.root.appendingPathComponent("roads") : nil)
        .alert("Immersive Map Editor", isPresented: Binding(get: { session.problem != nil }, set: { if !$0 { session.problem = nil } })) {
        } message: {
            Text(session.problem ?? "")
        }
    }
}

struct StatusLine: View {
    @Environment(Session.self) private var session

    var body: some View {
        HStack {
            switch session.workspace.viewMode {
            case .map:
                Text("Drag to move, scroll to zoom. Click picks a tile, shift-drag a box of them, double-click shows a built one in 3D.")
                    .lineLimit(1)
                Spacer()
            case .roads:
                if let model = session.model {
                    Text(model.tool.hint).lineLimit(1)
                    Spacer()
                    Text(model.status).lineLimit(1).foregroundStyle(.secondary)
                } else {
                    Spacer()
                }
            case .tiles:
                Text(session.workspace.flying
                    ? "Flight: W A S D, Q down, E up, shift faster, right-drag to look, scroll for speed. Tab to orbit."
                    : "Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom to the cursor. Tab flies, F frames, L light map.")
                    .lineLimit(1)
                Spacer()
                Text(session.workspace.tileStatus).lineLimit(1).foregroundStyle(.secondary)
            }
        }
    }
}

/// A Metal view in SwiftUI: the one kind of AppKit view the app keeps, for
/// what SwiftUI has no API for (its input). It takes the keyboard when shown.
struct MetalHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.needsDisplay = true
        Task { @MainActor in nsView.window?.makeFirstResponder(nsView) }
    }
}

/// The map's panel: what the colours mean, the tiles picked, and what to do
/// with them.
struct MapInspector: View {
    @Environment(Session.self) private var session
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let workspace = session.workspace
        let picked = workspace.selection.sorted()
        let toFetch = picked.filter { !workspace.fetched.contains($0) }
        let built = picked.filter { workspace.built.contains($0) }
        let documents = Set(picked.compactMap { workspace.document(holding: $0) })
        Form {
            Section("Tiles") {
                legend(.green, "built")
                legend(.yellow, "OSM fetched, not built")
                legend(.purple, "has a road document", outline: true)
                legend(.blue, "picked")
                legend(.orange, "shown in 3D", outline: true)
                Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                    .foregroundStyle(.secondary)
            }
            Section("Picked: \(picked.count)") {
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
                    if let url = picked.compactMap({ workspace.document(holding: $0) }).first { session.open(roads: url) }
                }
                .disabled(documents.isEmpty)
                Button("Fetch OSM and Build \(picked.count)") {
                    session.build(picked)
                    openWindow(id: "build")
                }
                .disabled(picked.isEmpty || session.build.running)
                if !toFetch.isEmpty {
                    Text("\(toFetch.count) not fetched yet: Overpass first, about half a minute each, then osm2streets and a road document for the tiles that have none.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Clear") { workspace.selection = [] }
                    .disabled(picked.isEmpty)
                Button("Frame the work  F") { session.camera.frame(workspace) }
            }
        }
        .formStyle(.grouped)
    }

    func legend(_ colour: Color, _ text: String, outline: Bool = false) -> some View {
        Label {
            Text(text)
        } icon: {
            RoundedRectangle(cornerRadius: 2)
                .fill(outline ? Color.clear : colour.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(colour, lineWidth: outline ? 2 : 0))
                .frame(width: 14, height: 14)
        }
    }
}

/// The 3D view's panel: the tiles shown, the camera, the light map.
struct TilesInspector: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var workspace = session.workspace
        Form {
            Section("Shown: \(workspace.shown.count)") {
                ForEach(workspace.shown, id: \.self) { t in
                    HStack {
                        Text(verbatim: t.name).font(.callout.monospaced())
                        Spacer()
                        Button("Only") { workspace.shown = [t] }.controlSize(.small)
                        Button("Hide") { workspace.shown.removeAll { $0 == t } }.controlSize(.small)
                    }
                }
                Text("Pick tiles on the Map and Show in 3D to change them.").foregroundStyle(.secondary)
                Button("Frame  F") { session.tiles?.frameTiles() }
                Button("Reload the built tiles") { workspace.tilesRevision += 1 }
            }
            Section("View") {
                Toggle("Fly  Tab", isOn: $workspace.flying)
                Toggle("Light map  L", isOn: $workspace.showLightMap)
            }
            Section {
                Text(workspace.tileStatus).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The Roads view's panel: tools, point operations, the selection, layers.
struct Inspector: View {
    @Bindable var model: EditorModel
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
    @Bindable var model: EditorModel

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
