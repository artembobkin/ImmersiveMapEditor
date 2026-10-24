import SwiftUI

/// The 3D view's panel: the tiles shown, the camera, the light map.
struct TilesPanel: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var workspace = session.workspace
        Form {
            Section("Shown: \(workspace.shown.count)") {
                ForEach(workspace.shown, id: \.self) { t in
                    HStack {
                        Text(verbatim: t.name).font(.callout.monospaced())
                        Spacer()
                        Button("Only") { workspace.shown = [t] }.controlSize(.small)
                        Button("Hide") { workspace.shown.removeAll { $0 == t } }.controlSize(.small)
                    }
                }
                Text("Pick tiles on the Map and Show in 3D to change them.").foregroundStyle(.secondary)
                Button("Frame  F") { session.tiles?.frameTiles() }
                Button("Reload the built tiles") { workspace.tilesRevision += 1 }
            }
            Section("View") {
                Toggle("Fly  Tab", isOn: $workspace.flying)
                Toggle("Light map  L", isOn: $workspace.showLightMap)
            }
            Section {
                Text(workspace.tileStatus).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
