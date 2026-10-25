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
            main
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
        case .light:
            // The same 3D tile, lit: its light map on the palette, or alone.
            if session.workspace.shown.isEmpty {
                ContentUnavailableView("The tile is not built", systemImage: "sun.max",
                                       description: Text("Build the tile in Tiles 3D, then bake its light here."))
            } else if let tiles = session.tiles {
                MetalHost(view: tiles)
            }
        case .landmarks:
            Group {
                if session.landmarks.selected == nil {
                    ContentUnavailableView("No landmark picked", systemImage: "building.columns",
                                           description: Text("Pick a model in the list on the right."))
                } else if let view = session.landmarkView {
                    MetalHost(view: view)
                }
            }
            .onChange(of: session.landmarks.picked, initial: true) { session.showLandmark() }
        }
    }
}
