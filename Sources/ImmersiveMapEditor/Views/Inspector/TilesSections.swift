import SwiftUI

/// The 3D view's sections: the camera and the light map. The tiles are those
/// picked on the map that are built.
struct TilesSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var workspace = session.workspace
        Section("View") {
            Toggle("Fly  Tab", isOn: $workspace.flying)
            Toggle("Light map  L", isOn: $workspace.showLightMap)
            Button("Frame  F") { session.tiles?.frameTiles() }
            Button("Reload the built tiles") { workspace.tilesRevision += 1 }
        }
        Section("Shown") {
            Text(workspace.tileStatus).foregroundStyle(.secondary)
        }
    }
}
