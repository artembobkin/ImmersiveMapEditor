import SwiftUI

/// The Map view's sections: the view, and what the workspace has. The tile
/// picked is worked on in the other views, chosen at the top.
struct MapSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        Section("View") {
            Button("Frame the work  F") { session.camera.frame(workspace) }
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
        }
    }
}
