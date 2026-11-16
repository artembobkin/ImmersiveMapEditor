import SwiftUI
import TileKit

/// The Preview's sections: what is shown (the tile, all its landmarks'
/// models together, or one landmark alone) and, for a landmark, the
/// camera's lens. The Preview's light has nothing to set: one sun with its
/// shadow, the editor's own (`PreviewLight`).
struct PreviewSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var preview = session.preview
        @Bindable var workspace = session.workspace
        Section("Show") {
            Picker("Subject", selection: $workspace.previewSubject) {
                Text("The tile").tag("tile")
                Text("All the landmarks").tag("landmarks")
                ForEach(session.candidates.filter { $0.model != nil }) { Text($0.name).tag($0.id) }
            }
            .help("The tile as built; all the landmarks' models together where the build places them, with no build; or one landmark alone. Each in its palette's colours under the preview's own sun, which is not in the tiles: the engine lights the models itself.")
            PanelButton("Rebuild Landmarks from Recipes", systemImage: "hammer") { session.rebuildLandmarks() }
                .disabled(session.landmarksWithRecipes == 0 || session.workspace.tile.map { session.jobs.isActive(.tile($0)) } ?? true)
                .help("Every landmark of the tile with a recipe built again from it (\(session.landmarksWithRecipes) of them): after a change of the palette, or of a recipe by hand. The tile itself is not built: see them together as All the landmarks.")
            if workspace.previewSubject != "tile" {
                HStack {
                    Text("Lens")
                    Slider(value: $preview.lens, in: 20...90)
                    Text(String(format: "%.0f°", preview.lens)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .help("The camera's lens, its vertical field of view: the engine's is 45°. Narrow, like a telephoto, flattens the building and keeps its walls parallel; wide makes what is near loom and the far shrink. The model keeps its size in the frame.")
            }
        }
    }
}
