import SwiftUI

/// Immersive Map Editor: the desktop tool for the ImmersiveMap engine's
/// content. It works on a TilePipeline folder (its workspace): a map to pick
/// tiles on, fetch their OSM and build them, the road documents corrected by
/// hand, and the built tiles shown together in 3D.
///
///   ImmersiveMapEditor [WORKSPACE | ROAD DOCUMENT]
///   ImmersiveMapEditor --resave IN OUT                        a document read and written, no window
///   ImmersiveMapEditor --snapshot WORKSPACE OUT.png X/Y...    tiles in 3D to a PNG, no window
///   ImmersiveMapEditor --map-snapshot WORKSPACE OUT.png       the map to a PNG, no window
///   ImmersiveMapEditor --landmark-snapshot MODEL.glb OUT.png  a landmark model to a PNG, no window
///
/// With no argument it opens the workspace opened last, else
/// ~/Desktop/TilePipeline.
@main
enum Entry {
    /// Synchronous on purpose: see `Platform.runMain`.
    static func main() {
        let arguments = CommandLine.arguments
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
    private let document: URL?

    init() {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        var root = UserDefaults.standard.string(forKey: "workspace").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/TilePipeline")
        var document: URL?
        if let path = args.first {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "json" {
                document = url
                root = url.deletingLastPathComponent().deletingLastPathComponent()
            } else {
                root = url
            }
        }
        _session = State(initialValue: Session(root: root))
        self.document = document
    }

    var body: some Scene {
        Window("Immersive Map Editor", id: "main") {
            ContentView()
                .environment(session)
                .task { if let document { session.open(roads: document) } }
        }
        .defaultSize(width: 1400, height: 900)
        .commands { EditorCommands(session: session) }
    }
}
