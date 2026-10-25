import SwiftUI

/// The Landmarks view's sections: the tile's landmarks (made in the
/// Buildings view, each a folder of the tile's landmarks/), to pick one and
/// see its model, its buildings and its folder.
struct LandmarksSections: View {
    @Environment(Session.self) private var session
    @State private var request = ""

    private var runner: BuildRunner { session.build }

    var body: some View {
        @Bindable var session = session
        Section("The tile's landmarks: \(session.candidates.count)") {
            if session.candidates.isEmpty {
                Text("None yet: pick buildings in Buildings and make a landmark of them.").foregroundStyle(.secondary)
            }
            ForEach(session.candidates) { landmark in
                Button { session.pickedLandmark = landmark.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(landmark.name)
                        Text(verbatim: "\(landmark.buildings.count) buildings · " + (landmark.model == nil ? "no model yet: its OSM boxes" : landmark.model!.lastPathComponent))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(session.pickedLandmark == landmark.id ? Color.accentColor.opacity(0.25) : nil)
            }
        }
        if let landmark = session.candidates.first(where: { $0.id == session.pickedLandmark }) {
            Section("Model with Claude") {
                if session.agent.running {
                    Button("Stop Claude", systemImage: "stop.circle") { session.agent.stop() }
                } else {
                    Button("Model with Claude", systemImage: "sparkles") { session.modelLandmark() }
                        .disabled(runner.running)
                        .help("Claude Code looks for freely licensed photos, writes the recipe, renders and corrects it. Through the proxy of Settings > Claude.")
                }
                if LandmarkAgent.hasConversation(landmark.folder) {
                    HStack {
                        TextField("Ask Claude to change it…", text: $request, axis: .vertical)
                            .lineLimit(1...4)
                            .onSubmit(send)
                        Button("Send", systemImage: "paperplane", action: send)
                            .labelStyle(.iconOnly)
                            .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || runner.running)
                    }
                }
            }
            Section {
                Button("Build from Its Recipe", systemImage: "hammer") { session.buildLandmark() }
                    .disabled(runner.running)
                    .help("Builds model.glb from recipe.json (a starter recipe from OSM's tags when there is none).")
                Button("Open Its Folder", systemImage: "folder") { Platform.open(landmark.folder) }
            }
        }
    }

    private func send() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !runner.running else { return }
        request = ""
        session.modelLandmark(request: text)
    }
}
