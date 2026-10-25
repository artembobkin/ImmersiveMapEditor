import SwiftUI

/// The Map view's sections: what to do with the tile picked, and what the
/// workspace has.
struct MapSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        let tile = workspace.tile
        Section("Actions") {
            Button(tile.map { workspace.fetched.contains($0) ? "Build the Tile" : "Fetch OSM and Build the Tile" } ?? "Fetch OSM and Build") {
                session.buildTile()
            }
            .disabled(tile == nil || session.build.running)
            if let t = tile, !workspace.fetched.contains(t) {
                Text("Overpass first, about half a minute, then osm2streets and a road document if none holds the tile.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Show in 3D") { workspace.viewMode = .tiles }
                .disabled(tile.map { !workspace.built.contains($0) } ?? true)
            Button("Edit Roads") { workspace.viewMode = .roads }
                .disabled(tile.flatMap { workspace.document(holding: $0) } == nil)
            Button("Frame the work  F") { session.camera.frame(workspace) }
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
        }
    }
}
