import SwiftUI

/// The Landmarks view's sections: the landmark models ready, those standing
/// in the working tile or all of them, to pick one and look at it.
struct LandmarksSections: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var catalog = session.landmarks
        let picked: Set<TileKey> = session.workspace.tile.map { [$0] } ?? []
        let listed = catalog.listed(in: picked)
        Section("Find") {
            TextField("Search", text: $catalog.query)
            Toggle("Only in the tile", isOn: $catalog.onlyPickedTiles)
                .disabled(picked.isEmpty)
            Text(picked.isEmpty || !catalog.onlyPickedTiles
                 ? "\(listed.count) of \(catalog.all.count) models"
                 : "\(listed.count) models in the tile, \(catalog.all.count) in all")
                .foregroundStyle(.secondary)
        }
        Section("Models") {
            ForEach(listed) { m in
                Button { catalog.picked = m.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name)
                        Text(verbatim: "\(m.tile.name) · \(m.source.rawValue)\(m.hasRecipe ? " · recipe" : "")")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(catalog.picked == m.id ? Color.accentColor.opacity(0.25) : nil)
            }
        }
        Section {
            if let m = catalog.selected {
                Button("Open its folder") { openURL(m.folder) }
            }
            Button("Read the models again") { session.scanLandmarks() }
        }
    }
}
