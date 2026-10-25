import SwiftUI

/// The map's panel: the tiles picked, and what to do with them.
struct MapPanel: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        let picked = workspace.selection.sorted()
        let toFetch = picked.filter { !workspace.fetched.contains($0) }
        let built = picked.filter { workspace.built.contains($0) }
        let documents = Set(picked.compactMap { workspace.document(holding: $0) })
        Form {
            Section {
                Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                    .foregroundStyle(.secondary)
            }
            Section("Picked: \(picked.count)") {
                if !picked.isEmpty {
                    Text(picked.map(\.name).joined(separator: "  "))
                        .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(6)
                }
                Button("Show in 3D (\(built.count) built)") { workspace.viewMode = .tiles }
                .disabled(built.isEmpty)
                Button(documents.count > 1 ? "Edit Roads (first of \(documents.count) documents)" : "Edit Roads") {
                    if let url = picked.compactMap({ workspace.document(holding: $0) }).first { session.open(roads: url) }
                }
                .disabled(documents.isEmpty)
                Button("Fetch OSM and Build \(picked.count)") { session.build(picked) }
                .disabled(picked.isEmpty || session.build.running)
                if !toFetch.isEmpty {
                    Text("\(toFetch.count) not fetched yet: Overpass first, about half a minute each, then osm2streets and a road document for the tiles that have none.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Clear") { workspace.selection = [] }
                    .disabled(picked.isEmpty)
                Button("Frame the work  F") { session.camera.frame(workspace) }
            }
        }
        .formStyle(.grouped)
    }
}
