import SwiftUI

/// The Landmarks view's panel: the landmark models ready, those of the tiles
/// picked on the map or all of them, to pick one and look at it.
struct LandmarksPanel: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var catalog = session.landmarks
        let picked = session.workspace.selection
        let listed = catalog.listed(in: picked)
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $catalog.query)
                .textFieldStyle(.roundedBorder)
            Toggle("Only in the tiles picked", isOn: $catalog.onlyPickedTiles)
                .disabled(picked.isEmpty)
            Text(picked.isEmpty || !catalog.onlyPickedTiles
                 ? "\(listed.count) of \(catalog.all.count) models"
                 : "\(listed.count) models in \(picked.count) tiles picked, \(catalog.all.count) in all")
                .font(.callout).foregroundStyle(.secondary)
            List(listed, selection: $catalog.picked) { m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name)
                    Text(verbatim: "\(m.tile.name) · \(m.source.rawValue)\(m.hasRecipe ? " · recipe" : "")")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .tag(m.id)
            }
            .listStyle(.inset)
            if let m = catalog.selected {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([m.glb]) }
            }
            Button("Read the models again") { session.scanLandmarks() }
        }
        .padding(12)
    }
}
