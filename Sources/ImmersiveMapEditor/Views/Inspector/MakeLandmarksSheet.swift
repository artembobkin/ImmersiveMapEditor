import SwiftUI

/// The sheet of Make Landmarks…: which of the tile's buildings become
/// landmarks at once (`LandmarkKind`), each with how many are no landmark
/// yet, and how many of them, the largest first. Nothing is modelled: they
/// are to be looked over on the map and in the list first.
struct MakeLandmarksSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LandmarkKind = .known
    @State private var limit = 0

    var body: some View {
        let counts = Dictionary(uniqueKeysWithValues: LandmarkKind.allCases.map { ($0, session.toMake($0).count) })
        let count = counts[kind] ?? 0
        let made = limit == 0 ? count : min(limit, count)
        VStack(alignment: .leading, spacing: 16) {
            Text("Make Landmarks").font(.headline)
            Form {
                Picker("Buildings", selection: $kind) {
                    ForEach(LandmarkKind.allCases) { k in
                        Text("\(k.title): \(counts[k] ?? 0)").tag(k)
                    }
                }
                .pickerStyle(.radioGroup)
                .help("The tile's buildings that are no landmark yet, by what the map shows of them: teal the known ones, amber the monuments, or by their size.")
                Picker("How many", selection: $limit) {
                    Text("All \(count)").tag(0)
                    ForEach([50, 20, 10, 5].filter { $0 < count }, id: \.self) { Text("The \($0) largest").tag($0) }
                }
                .help("The largest by footprint first.")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Make \(made) Landmark" + (made == 1 ? "" : "s")) {
                    session.makeLandmarks(kind, limit: made)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(made == 0)
                .help("Each becomes a landmark of the tile, whole with its parts, named by its name or address, orange on the map and in the list. Nothing is modelled: delete the ones not worth a model first.")
            }
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: kind) { limit = 0 }
    }
}
