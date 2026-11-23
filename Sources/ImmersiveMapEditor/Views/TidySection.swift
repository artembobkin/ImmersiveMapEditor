import SwiftUI

/// The Settings section that frees the disk: every finished landmark of the
/// data folder tidied (`LandmarkTidy`: its candidates and old rounds gone,
/// its model, recipe and references kept), what it would free measured
/// first, off the main thread, and said (the user, 2026-11-22: the data
/// folder filled the disk).
struct TidySection: View {
    let tiles: URL
    @State private var measure: (landmarks: Int, bytes: Int)?
    @State private var asking = false
    @State private var working = false
    @State private var done: String?

    var body: some View {
        Section("Disk") {
            HStack {
                if let measure {
                    Text(measure.landmarks == 0 ? "Nothing to tidy." : "\(measure.landmarks) finished landmarks: \(LandmarkTidy.text(measure.bytes)) of working files.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").foregroundStyle(.secondary)
                }
                Spacer()
                Button(working ? "Tidying…" : "Tidy…") { asking = true }
                    .disabled(working || (measure?.bytes ?? 0) == 0)
                    .help("Removes the finished landmarks' working files, which the agent makes again when it works on one: the candidates it was shown and the models and pictures of its old rounds. Their models, recipes, references and every round's recipe stay.")
                    .confirmationDialog("Tidy \(measure?.landmarks ?? 0) finished landmarks?", isPresented: $asking) {
                        Button("Free \(LandmarkTidy.text(measure?.bytes ?? 0))", role: .destructive) { tidy() }
                    } message: {
                        Text("Their models, recipes and references stay.")
                    }
            }
            if let done { Text(done).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: tiles) { await remeasure() }
    }

    private func remeasure() async {
        measure = nil
        let tiles = self.tiles
        measure = await Task.detached {
            var landmarks = 0, bytes = 0
            for folder in LandmarkTidy.tileLandmarkFolders(tiles).flatMap(LandmarkTidy.landmarkFolders) {
                let b = LandmarkTidy.reclaimable(folder)
                if b > 0 { landmarks += 1; bytes += b }
            }
            return (landmarks, bytes)
        }.value
    }

    private func tidy() {
        working = true
        let tiles = self.tiles
        Task {
            let (count, freed) = await Task.detached {
                LandmarkTidy.tileLandmarkFolders(tiles).map(LandmarkTidy.tidyTile).reduce((0, 0)) { ($0.0 + $1.landmarks, $0.1 + $1.freed) }
            }.value
            done = "\(count) landmarks tidied, \(LandmarkTidy.text(freed)) freed."
            working = false
            await remeasure()
        }
    }
}
