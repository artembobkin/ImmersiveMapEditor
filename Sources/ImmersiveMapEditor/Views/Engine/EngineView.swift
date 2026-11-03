import ImmersiveMap
import SwiftUI

/// The Engine view: the engine's own map (ImmersiveMap at the release pinned
/// in Package.swift, never changed from here) with the data folder's model
/// archive over it, so a tile is seen as it will really look, the basemap,
/// the labels and the engine's light and all (the user, 2026-11-02). The
/// camera starts over the tile open, from the south and tilted, and stays
/// where it was left while another view is shown; over a tile open it is
/// held to the tile's neighbourhood.
struct EngineView: View {
    /// The engine's release this editor links: keep it with Package.swift.
    static let engineVersion = "0.11.1"

    @Environment(Session.self) private var session
    @State private var controller = ImmersiveMapCameraController()
    /// Where the camera started, kept for the view's life: the position the
    /// map is given must not follow the live camera, or every frame of a
    /// gesture is answered with a jump back (the user, 2026-11-02: the tilt
    /// stuttered).
    @State private var start: ImmersiveMapCameraPosition?

    var body: some View {
        if let archive = session.engineArchive {
            ImmersiveMapView(cameraPosition: start ?? session.engineCamera ?? session.engineStart, cameraController: controller)
                .modelArchive(archive)
                .cameraBounds(session.engineBounds)
                // The engine's ground relief is off: this view is for looking
                // at the models, which the pipeline builds on a flat ground,
                // and the relief (collapsed at zoom 13.7 anyway) only gets in
                // the way zoomed out (the user, 2026-11-03).
                .groundRelief(isEnabled: false)
                // A new archive is a new file: the view is made again over it.
                .id(archive)
                .onAppear {
                    if start == nil { start = session.engineCamera ?? session.engineStart }
                    controller.onCameraPositionChanged = { [weak session] position in
                        Task { @MainActor in session?.engineCamera = position }
                    }
                }
                .onChange(of: session.engineJumps) {
                    if let home = session.engineStart { controller.jump(to: home) }
                }
        } else {
            ContentUnavailableView("No model archive yet", systemImage: "globe",
                                   description: Text(session.workspace.built.isEmpty
                                       ? "Build a tile first: Preview > Build the Tile."
                                       : "Update the Archive puts every built tile into one the engine reads."))
        }
    }
}
