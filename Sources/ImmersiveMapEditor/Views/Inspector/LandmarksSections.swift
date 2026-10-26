import SwiftUI

/// The Landmarks view's sections: the tile's landmarks (made in the
/// Buildings view, each a folder of the tile's landmarks/), to pick one and
/// see its model, its buildings and its folder.
struct LandmarksSections: View {
    @Environment(Session.self) private var session
    @State private var request = ""
    /// The model the agent runs on: Claude Code's default, or one by name.
    @AppStorage(ClaudeSettings.modelKey) private var model = ""
    @State private var forgetting = false

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
                Picker("Detail", selection: Binding(
                    get: { landmark.detail },
                    set: { LandmarkCandidates.setDetail(landmark.folder, $0); session.readCandidates() })) {
                    Text("Simple").tag("simple")
                    Text("Normal").tag("normal")
                    Text("Detailed").tag("detailed")
                }
                .pickerStyle(.menu)
                .disabled(session.agent.running)
                .help("How far Claude goes: the masses and roofs alone, the facades with their windows, doors and relief, or every element that reads from across the street.")
                Picker("Model", selection: $model) {
                    Text("Default").tag("")
                    Text("Fable").tag("fable")
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                .pickerStyle(.menu)
                .disabled(session.agent.running)
                .help("Which Claude models the landmark: Claude Code's default, or one by name (the same setting as Settings > Claude > Model).")
                if session.agent.running {
                    Button("Stop Claude", systemImage: "stop.circle") { session.agent.stop() }
                } else {
                    Button("Model with Claude", systemImage: "sparkles") { session.modelLandmark() }
                        .disabled(runner.running)
                        .help("A new attempt from OSM: Claude Code looks for freely licensed photos (the ones kept are used again), writes the recipe, renders and corrects it. Through the proxy of Settings > Claude.")
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
            if LandmarkAgent.hasWork(landmark.folder) {
                Section {
                    Button("Forget Claude's Work…", systemImage: "trash", role: .destructive) { forgetting = true }
                        .disabled(runner.running)
                        .confirmationDialog("Forget everything Claude made for \(landmark.name)?", isPresented: $forgetting) {
                            Button("Forget the Photos, Recipe and Model", role: .destructive) {
                                LandmarkAgent.forget(landmark.folder)
                                session.landmarkWorkChanged()
                            }
                        } message: {
                            Text("Its photos, renders, recipe, model and conversation are deleted. The landmark itself stays.")
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
