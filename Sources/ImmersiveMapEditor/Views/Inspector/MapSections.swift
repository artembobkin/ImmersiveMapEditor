import SwiftUI

/// The sections of the map a tile is chosen on: opening the tile picked, and
/// what the workspace has.
struct MapSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        Section("Open") {
            if session.phase == .preparing {
                Text("Preparing the tile: the console shows how far.").foregroundStyle(.secondary)
            } else {
                PanelButton("Open the Tile", systemImage: "arrow.right.circle") {
                    if let t = session.candidate { session.open(tile: t) }
                }
                .disabled(session.candidate.map { session.jobs.isActive(.tile($0)) } ?? true)
                .help("Fetches its OSM and seeds its roads when they are missing, then its views are there. Double-click a tile, or ↩.")
            }
        }
        Section("Show") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Map", selection: Binding(get: { session.mapEngine }, set: { session.showMapEngine($0) })) {
                    Text("Tiles").tag(false)
                    Text("Engine").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .help("Tiles: OpenStreetMap under the grid of tiles, each coloured by what the data folder has of it, to pick one. Engine: the engine's own map with the whole model archive over it, every built tile as the engine will show it. The camera is handed over both ways.")
            }
            PanelButton(TileAction.engine.title, systemImage: TileAction.engine.systemImage) { session.perform(.engine) }
                .disabled(!session.can(.engine))
                .help("Every built tile into the model archive the Engine map reads, in the data folder's engine/.")
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
            PanelButton("Export Archive…", systemImage: "shippingbox") { session.exportArchive() }
                .disabled(workspace.built.isEmpty || session.jobs.isActive(.workspace))
                .help("Every built tile into one PMTiles archive of model tiles, the file the engine reads, where you choose.")
        }
    }
}
