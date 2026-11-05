import SwiftUI

/// The Engine view's sections: the engine's release, the archive shown
/// (its file, size and age) and the camera back over the tile. Update the
/// Archive is the view's action, in the Build section above.
struct EngineSections: View {
    @AppStorage(EngineView.labelsKey) private var labels = true
    @Environment(Session.self) private var session

    var body: some View {
        Section("Engine") {
            Text("ImmersiveMap \(EngineView.engineVersion)").foregroundStyle(.secondary)
            if let archive = session.engineArchive,
               let values = try? archive.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                Text(verbatim: [archive.lastPathComponent,
                                ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file),
                                values.contentModificationDate.map { $0.formatted(.relative(presentation: .named)) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No archive yet").foregroundStyle(.secondary)
            }
            Text("\(session.workspace.built.count) built tiles").foregroundStyle(.secondary)
            Toggle("Labels", isOn: $labels)
                .help("The engine's labels: place names, points of interest, house numbers and road names. Off, the models stand alone.")
            PanelButton("Centre on the Tile", systemImage: "scope") { session.engineJumps += 1 }
                .disabled(session.engineArchive == nil)
                .help("The camera back over the tile open, from the south, tilted.")
        }
    }
}
