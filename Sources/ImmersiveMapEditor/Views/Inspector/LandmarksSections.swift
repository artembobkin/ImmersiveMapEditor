import SwiftUI

/// The Landmarks view's sections: the landmark models ready that stand in the
/// tile open, to pick one and look at it.
struct LandmarksSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var catalog = session.landmarks
        let picked: Set<TileKey> = session.workspace.tile.map { [$0] } ?? []
        let listed = catalog.listed(in: picked)
        Section("Find") {
            TextField("Search", text: $catalog.query)
            Text("\(listed.count) models stand in the tile").foregroundStyle(.secondary)
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
                Button("Open its folder") { Platform.open(m.folder) }
            }
            Button("Read the models again") { session.scanLandmarks() }
        }
    }
}
