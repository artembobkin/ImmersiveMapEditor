import SwiftUI

/// The Map view's sections: what to do with the tiles picked, and what the
/// workspace has.
struct MapSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        let picked = workspace.selection.sorted()
        let toFetch = picked.filter { !workspace.fetched.contains($0) }
        let built = picked.filter { workspace.built.contains($0) }
        let documents = Set(picked.compactMap { workspace.document(holding: $0) })
        Section("Actions") {
            Button("Fetch OSM and Build \(picked.count)") { session.build(picked) }
                .disabled(picked.isEmpty || session.build.running)
            if !toFetch.isEmpty {
                Text("\(toFetch.count) not fetched yet: Overpass first, about half a minute each, then osm2streets and a road document for the tiles that have none.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Show in 3D (\(built.count) built)") { workspace.viewMode = .tiles }
                .disabled(built.isEmpty)
            Button(documents.count > 1 ? "Edit Roads (first of \(documents.count) documents)" : "Edit Roads") {
                workspace.viewMode = .roads
            }
            .disabled(documents.isEmpty)
            Button("Clear the pick") { workspace.selection = [] }
                .disabled(picked.isEmpty)
            Button("Frame the work  F") { session.camera.frame(workspace) }
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
        }
    }
}
