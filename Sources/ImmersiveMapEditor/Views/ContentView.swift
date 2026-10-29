import SwiftUI

/// The window, one layout whatever is shown: the tile's files on the left
/// (FilesSidebar), the main region with the console and the status line
/// under it (WindowLayout), the inspector on the right. Its content follows
/// the session's phase: the map while a tile is chosen and prepared, the
/// view picked at the top (shown only then) while it is worked on.
struct ContentView: View {
    @Environment(Session.self) private var session
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let workspace = session.workspace
        NavigationSplitView(columnVisibility: Binding(get: { session.panels.files ? .all : .detailOnly },
                                                       set: { session.panels.files = $0 != .detailOnly })) {
            FilesSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
                // Shown or hidden in the View menu, no button of its own.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .onChange(of: workspace.viewMode) { session.follow(workspace.viewMode) }
        .onChange(of: undoManager, initial: true) { session.model?.undo = undoManager }
        .onChange(of: session.model.map { ObjectIdentifier($0) }) { session.model?.undo = undoManager }
        .onChange(of: phase) { if phase != .active { session.model?.saveIfNeeded() } }
        .confirmationDialog("Seed the roads again?", isPresented: Binding(get: { session.reseedAsked },
                                                                          set: { session.reseedAsked = $0 })) {
            Button("Seed Again, Losing the Hand Edits", role: .destructive) { session.seedRoads(force: true) }
        } message: {
            Text("The road document holding the tile is seeded again from osm2streets and OSM, over every hand edit in it.")
        }
        .alert("Immersive Map Editor", isPresented: Binding(get: { session.problem != nil }, set: { if !$0 { session.problem = nil } })) {
        } message: {
            Text(session.problem ?? "")
        }
    }

    /// The main region with the console and the status line, the inspector
    /// on its right, the toolbar over it.
    private var detail: some View {
        @Bindable var workspace = session.workspace
        let working = session.phase == .working
        return WindowLayout(consoleShown: session.panels.console) {
            main.overlay(alignment: .topLeading) { PicturePreview() }
        } console: {
            BottomPanel().environment(session.build)
        } status: {
            StatusLine()
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The views exist once a tile is open.
                if working {
                    Picker("View", selection: $workspace.viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            ToolbarItem(placement: .navigation) {
                if working, let tile = workspace.tile {
                    Button(tile.name, systemImage: "square.grid.3x3") { session.chooseAnotherTile() }
                        .labelStyle(.titleAndIcon)
                        .help("Choose another tile (⌘0)")
                }
            }
        }
        .inspector(isPresented: Binding(get: { session.panels.inspector }, set: { session.panels.inspector = $0 })) {
            Inspector()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        // No title: the tile is named in the toolbar and the inspector.
        .navigationTitle("")
    }

    /// The main region: the map while a tile is chosen and prepared, else
    /// the view picked at the top.
    @ViewBuilder private var main: some View {
        if session.phase == .working {
            mode
        } else {
            MapPicker()
        }
    }

    /// The view picked, over the tile open.
    @ViewBuilder private var mode: some View {
        switch session.workspace.viewMode {
        case .roads:
            if let roads = session.roads {
                MetalHost(view: roads)
            } else {
                ContentUnavailableView("No road document", systemImage: "road.lanes",
                                       description: Text("No road document holds the tile: Seed the Roads makes one."))
            }
        case .tiles:
            if session.workspace.shown.isEmpty {
                ContentUnavailableView("The tile is not built", systemImage: "cube",
                                       description: Text("Build the Tile makes its model."))
            } else if let tiles = session.tiles {
                MetalHost(view: tiles)
            }
        case .buildings:
            BuildingsView()
        case .style:
            StyleView()
        case .preview:
            // What the engine will show: the tile built and lit by its light
            // map (or the light alone), or one landmark alone, its light
            // baked here with the same settings and the engine's sun.
            let workspace = session.workspace
            if workspace.previewSubject != "tile" {
                // Something fills the region before the view exists: on an
                // empty view the task never runs, and the console takes the
                // place of the region.
                ZStack {
                    if let view = session.previewView {
                        MetalHost(view: view)
                            .overlay { AxisLabels(labels: session.previewLabels) }
                            .overlay(alignment: .topLeading) { CameraBadge(line: session.previewCamera) }
                    } else {
                        ContentUnavailableView("Baking the light", systemImage: "sun.max",
                                               description: Text("The landmark alone, lit as the engine will light it, comes in a moment."))
                    }
                }
                .task(id: "\(workspace.previewSubject) \(session.lightSettings.previewKey) \(workspace.tilesRevision) \(session.candidates.map { $0.modelStamp })") {
                    // A moment after the last change, so a slider's drag bakes once.
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    session.showPreview()
                }
                .onChange(of: session.lightSettings.previewShadow, initial: true) { session.previewView?.shadowStrength = session.lightSettings.previewShadow }
                .onChange(of: session.lightSettings.lens, initial: true) { session.previewView?.lens = session.lightSettings.lens }
            } else if workspace.shown.isEmpty {
                ContentUnavailableView("The tile is not built", systemImage: "sun.max",
                                       description: Text("Build the tile in Tiles 3D, then bake its light here. A landmark alone needs no build: pick it on the right."))
            } else if let tiles = session.tiles {
                MetalHost(view: tiles)
            }
        case .landmarks:
            // The tile's landmark picked: its model when one is there.
            Group {
                // Its model, or its OSM buildings as boxes while it has none.
                if session.candidates.contains(where: { $0.id == session.pickedLandmark }), let view = session.landmarkView {
                    MetalHost(view: view).overlay(alignment: .topLeading) { CameraBadge(line: session.landmarkCamera) }
                } else {
                    ContentUnavailableView("No landmark picked", systemImage: "building.columns",
                                           description: Text("The tile's landmarks are made in Buildings: pick one on the right."))
                }
            }
            .onChange(of: session.pickedLandmark, initial: true) { session.showLandmark() }
        }
    }
}

/// The view's camera in the top left corner, as the headless render takes
/// it (--landmark-look FOLDER OUT.png X Y Z HEADING PITCH HFOV W H), with a
/// button that copies it: a view seen in the editor can be rendered again
/// exactly, for a check (the user, 2026-10-29).
struct CameraBadge: View {
    let line: String

    var body: some View {
        if !line.isEmpty {
            HStack(spacing: 6) {
                Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(line, forType: .string) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy the camera: the eye in metres (east, north, up), the heading, the pitch, the lens's horizontal angle and the view's size in pixels, as --landmark-look takes them.")
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(8)
        }
    }
}

/// The axes' labels over the 3D view, each at its point: X E, Y N, Z at
/// the arrows' tips, W and S the other way (the user, 2026-10-29).
struct AxisLabels: View {
    let labels: [ViewLabel]

    var body: some View {
        // Only the labels inside the view, and nothing drawn past its edge.
        GeometryReader { geo in
            let inside = CGRect(origin: .zero, size: geo.size).insetBy(dx: 16, dy: 10)
            ForEach(labels.filter { inside.contains($0.point) }) { l in
                Text(l.text).font(.system(.callout, design: .rounded).bold()).foregroundStyle(.primary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(l.point)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
