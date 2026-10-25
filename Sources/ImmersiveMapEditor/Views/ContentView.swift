import SwiftUI

/// The window's content: the view of the mode, its panel in the inspector,
/// the mode in the toolbar, the build's log below it while open, hints and
/// state along the bottom.
struct ContentView: View {
    @Environment(Session.self) private var session
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var phase
    @State private var inspector = true

    var body: some View {
        @Bindable var workspace = session.workspace
        let importing = session.importing
        VSplitView {
            mode
                .frame(minWidth: 600, minHeight: 300)
            if session.build.shown {
                BottomPanel()
                    .environment(session.build)
                    .frame(minHeight: 120, idealHeight: 220)
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
                Button("Fetch and Build", systemImage: "hammer") { session.buildPickedOrOpen() }
                .disabled(session.build.running)
            }
            ToolbarItem {
                Button("Build Log", systemImage: "terminal") { session.build.shown.toggle() }
            }
            ToolbarItem {
                Button("Panel", systemImage: "sidebar.trailing") { inspector.toggle() }
            }
        }
        .inspector(isPresented: $inspector) {
            Inspector()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .navigationTitle(session.model.map { "\($0.url.lastPathComponent)\($0.dirty ? " (edited)" : "")" }
                         ?? session.workspace.root.lastPathComponent)
        .onChange(of: workspace.viewMode) { session.follow(workspace.viewMode) }
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

    /// The view of the mode.
    @ViewBuilder private var mode: some View {
        switch session.workspace.viewMode {
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
            if session.workspace.shown.isEmpty {
                ContentUnavailableView("No built tile picked", systemImage: "cube",
                                       description: Text("Pick built tiles on the Map: they show here in 3D."))
            } else if let tiles = session.tiles {
                MetalHost(view: tiles)
            }
        case .light:
            LightView()
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
