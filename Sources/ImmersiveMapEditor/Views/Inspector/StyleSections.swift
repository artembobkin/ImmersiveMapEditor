import SwiftUI
import TileKit

/// The Style view's sections: what is set over the defaults, where it is
/// kept, and what takes it up.
struct StyleSections: View {
    @Environment(Session.self) private var session
    @State private var resetting = false

    var body: some View {
        let _ = session.palette.revision
        Section("Palette") {
            let n = session.palette.colours.count
            Text(n == 0 ? "The defaults, nothing set over them." : "\(n) colour\(n == 1 ? "" : "s") set over the defaults.")
                .foregroundStyle(.secondary)
            Button("Reset All to the Defaults…", systemImage: "arrow.counterclockwise", role: .destructive) { resetting = true }
                .disabled(n == 0)
                .confirmationDialog("Back to the default palette?", isPresented: $resetting) {
                    Button("Reset All", role: .destructive) { session.palette.resetAll() }
                }
            if let file = session.palette.file {
                Button("Show the Palette File", systemImage: "doc") { Platform.reveal(file) }
                    .disabled(!FileManager.default.fileExists(atPath: file.path))
                    .help(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            }
        }
        Section("Takes effect") {
            Text("A change is saved at once. A tile paints with it when built again (Build the Tile), a landmark model at its next build (Build from Its Recipe, or Claude's).")
                .foregroundStyle(.secondary)
        }
        Section("Sun") {
            Text(verbatim: String(format: "From %.0f°, the south-west. Every wall's lit, side and shade tones follow it, and the engine's sun must come from there too.", Palette.sunFrom))
                .foregroundStyle(.secondary)
        }
    }
}
