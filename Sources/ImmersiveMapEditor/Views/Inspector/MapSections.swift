import SwiftUI

/// The sections of the map a tile is chosen on: opening the tile picked, the
/// view, and what the workspace has.
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
        Section("View") {
            Button("Frame the work  F") { session.camera.frame(workspace) }
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
        }
    }
}
