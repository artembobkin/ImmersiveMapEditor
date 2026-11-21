import SwiftUI

/// The sheet of Automate N Tiles… on the map: which buildings of each marked
/// tile become landmarks and how many, then the folder's command and the
/// prompt of the one session that goes through the tiles (`AreaMCP`): each
/// prepared, its landmarks modelled by subagents, the archive made anew at
/// the end (the user, 2026-11-21: tile after tile, without doing each by hand).
struct AutomateAreaSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LandmarkKind = .known
    @State private var limit = 0
    @State private var copied: String?

    var body: some View {
        let tiles = session.markedTiles
        VStack(alignment: .leading, spacing: 16) {
            Text("Automate \(tiles.count) Tiles").font(.headline)
            Form {
                Picker("Landmarks of", selection: $kind) {
                    ForEach(LandmarkKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .help("Which buildings of each tile become landmarks when the session prepares it. A tile prepared before keeps its landmarks.")
                Picker("A tile at most", selection: $limit) {
                    Text("All").tag(0)
                    ForEach([30, 20, 10, 5], id: \.self) { Text("The \($0) largest").tag($0) }
                }
                .help("The largest by footprint first.")
                LabeledContent("Detail", value: AgentSettings.fine ? "Fine" : "Normal")
                    .help("The modelling's detail, set in a landmark's panel: every subagent models at it.")
            }
            if let copied { Text(copied).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Copy Folder Command") {
                    session.copyAreaFolderCommand(kind: kind, limit: limit)
                    copied = "The cd into the data folder's agent/ copied: start claude or codex there."
                }
                .help("Writes the area's plan and sets up the data folder's agent/ for one Claude Code or Codex session, and copies the cd into it.")
                Button("Copy Prompt") {
                    session.copyAreaPrompt(kind: kind, limit: limit)
                    copied = "The prompt copied: paste it into the session."
                }
                .help("The prompt of the session: it goes through the tiles in rows from the north, prepares each (its OSM from the extracts, its landmarks), models every landmark without a model with a subagent, \(LandmarkAgent.tileAtOnce) at once, and makes the engine's archive anew at the end.")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
