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
                Button("Open the Tile", systemImage: "arrow.right.circle") {
                    if let t = session.candidate { session.open(tile: t) }
                }
                .disabled(session.candidate == nil || session.build.running)
                Text("Fetches its OSM and seeds its roads when they are missing, then its views are there. Double-click a tile, or ↩.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
            Button("Export Archive…", systemImage: "shippingbox") { session.exportArchive() }
                .disabled(workspace.built.isEmpty || workspace.building)
            Text("Every built tile into one PMTiles archive of model tiles, the file the engine reads, where you choose.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
