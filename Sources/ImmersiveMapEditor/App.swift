import AppKit
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
///
/// With no argument it opens the workspace opened last, else
/// ~/Desktop/TilePipeline.
@main
enum Entry {
    static func main() async {
        if let code = await Headless.run(CommandLine.arguments) { exit(code) }
        // Run without its app bundle (from the command line or Xcode), the
        // executable has no activation policy of its own.
        if Bundle.main.bundleIdentifier == nil { NSApplication.shared.setActivationPolicy(.regular) }
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

        Window("Build", id: "build") {
            BuildLogView().environment(session.build)
        }
        .defaultSize(width: 760, height: 420)
    }
}

/// The menus: workspaces and documents, saving, the views, building.
struct EditorCommands: Commands {
    let session: Session
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Workspace…") { session.importing = .workspace }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Open Road Document…") { session.importing = .roads }.keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { session.model?.save() }
                .keyboardShortcut("s")
                .disabled(session.model == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Select None") {
                if session.workspace.viewMode == .map { session.workspace.selection = [] } else { session.model?.selection = [] }
            }
            .keyboardShortcut("d")
        }
        CommandGroup(before: .toolbar) {
            Button("Map") { session.workspace.viewMode = .map }.keyboardShortcut("1")
            Button("Roads") { session.workspace.viewMode = .roads }.keyboardShortcut("2")
            Button("Tiles 3D") { session.workspace.viewMode = .tiles }.keyboardShortcut("3")
            Divider()
        }
        CommandMenu("Tiles") {
            Button("Fetch and Build") {
                session.buildPickedOrOpen()
                openWindow(id: "build")
            }
            .keyboardShortcut("b")
            .disabled(session.build.running)
            Button("Show Build Log") { openWindow(id: "build") }.keyboardShortcut("l")
        }
    }
}
