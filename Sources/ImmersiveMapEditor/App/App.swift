import SwiftUI
import TileKit

/// Immersive Map Editor: the desktop tool for the ImmersiveMap engine's
/// content. It works on a TilePipeline folder (its workspace): a map to pick
/// tiles on, fetch their OSM and build them, the road documents corrected by
/// hand, and the built tiles shown together in 3D.
///
///   ImmersiveMapEditor [DATA FOLDER]
///   ImmersiveMapEditor pipeline COMMAND ...                   the pipeline's commands, as tilepipeline takes them
///   ImmersiveMapEditor --resave IN OUT                        a document read and written, no window
///   ImmersiveMapEditor --snapshot WORKSPACE OUT.png X/Y       a tile in 3D to a PNG, no window
///   ImmersiveMapEditor --map-snapshot WORKSPACE OUT.png       the map to a PNG, no window
///   ImmersiveMapEditor --landmark-snapshot MODEL.glb OUT.png  a landmark model to a PNG, no window
///
/// With no argument it opens the data folder of Settings (DataFolder).
@main
enum Entry {
    /// Synchronous on purpose: see `Platform.runMain`.
    static func main() {
        let arguments = CommandLine.arguments
        // The pipeline's commands, run by the editor as a process of its own
        // build, so the pipeline is never older than the editor.
        if arguments.count > 1, arguments[1] == "pipeline" {
            PipelineCommand.run(Array(arguments.dropFirst(2)))
        }
        if Headless.asked(arguments) {
            Platform.runMain { exit(await Headless.run(arguments) ?? 1) }
        }
        // The window on the main thread itself, as SwiftUI and AppKit want
        // it: from a task on the main queue it would hold that queue for
        // good, and no other main-actor task (the map's tiles, the build's
        // log) would ever run.
        MainActor.assumeIsolated { Platform.activateBareExecutable() }
        EditorApp.main()
    }
}

struct EditorApp: App {
    @State private var session: Session

    init() {
        // A folder given on the command line, else the data folder of Settings.
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        _session = State(initialValue: Session(root: args.first.map { URL(fileURLWithPath: $0) } ?? DataFolder.current))
    }

    var body: some Scene {
        Window("Immersive Map Editor", id: "main") {
            ContentView()
                .environment(session)
        }
        .defaultSize(width: 1400, height: 900)
        .commands { EditorCommands(session: session) }

        Settings { SettingsView().environment(session) }
    }
}
