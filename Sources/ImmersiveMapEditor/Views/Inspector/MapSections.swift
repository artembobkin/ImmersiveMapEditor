import SwiftUI

/// The Map view's sections: what to do with the tile picked, and what the
/// workspace has.
struct MapSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        let tile = workspace.tile
        Section("Actions") {
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
