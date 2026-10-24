import AppKit
import SwiftUI

/// Immersive Map Editor: the desktop tool for the ImmersiveMap engine's
/// content. It works on a TilePipeline folder (its workspace): a map to pick
/// tiles on, fetch their OSM and build them, the road documents corrected by
/// hand (TilePipeline's build/roads.py has the format), and the built tiles
/// shown together in 3D.
///
///   swift run -c release ImmersiveMapEditor [TILEPIPELINE | ROAD DOCUMENT]
///
/// With no argument it opens the workspace opened last, else
/// ~/Desktop/TilePipeline.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    var session: Session?
    var build: BuildRunner?
    private var watches: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = menu()
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        var document: URL?
        var root = UserDefaults.standard.string(forKey: "workspace").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/TilePipeline")
        if let path = args.first {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "json" {
                document = url
                root = url.deletingLastPathComponent().deletingLastPathComponent()
            } else {
                root = url
            }
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("pipeline.py").path) else {
            openWorkspace(nil)
            return
        }
        start(root)
        if let document { openRoads(document) }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The window over a TilePipeline folder.
    func start(_ root: URL) {
        let workspace = Workspace(root: root)
        let session = Session(workspace: workspace)
        let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                             backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView(session: session, workspace: workspace))
        window.title = "Immersive Map Editor: \(root.lastPathComponent)"
        window.delegate = self
        window.setFrameAutosaveName("ImmersiveMapEditor")
        if self.window == nil { window.center() }
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.session = session
        UserDefaults.standard.set(root.path, forKey: "workspace")
        watches = [session.$model.sink { [weak self] model in self?.watch(model) }]
    }

    /// The open road document's unsaved state, on the window.
    private func watch(_ model: EditorModel?) {
        guard let model else { return }
        window?.representedURL = model.url
        watches.append(model.$dirty.sink { [weak window] dirty in window?.isDocumentEdited = dirty })
    }

    private var model: EditorModel? { session?.model }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmDiscard() ? .terminateNow : .terminateCancel
    }

    /// True if there is nothing unsaved, or the user saves or drops it.
    func confirmDiscard() -> Bool {
        guard let model, model.dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save the changes to \(model.url.lastPathComponent)?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: model.save(); return !model.dirty
        case .alertThirdButtonReturn: model.dirty = false; return true
        default: return false
        }
    }

    func openRoads(_ url: URL) {
        guard let session, confirmDiscard() else { return }
        do {
            try session.open(url)
            session.workspace.viewMode = .roads
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Cannot open \(url.lastPathComponent): \(error.localizedDescription)"
            alert.runModal()
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model?.undo }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmDiscard() }

    // MARK: Actions

    @objc func openWorkspace(_ sender: Any?) {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "A TilePipeline folder (the one with pipeline.py)"
        if panel.runModal() == .OK, let url = panel.url {
            start(url)
        } else if window == nil {
            NSApp.terminate(nil)
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = session?.workspace.root.appendingPathComponent("roads")
        panel.message = "A road document: roads/<z>_<x0>_<y0>_<x1>_<y1>.json"
        if panel.runModal() == .OK, let url = panel.url { openRoads(url) }
    }

    @objc func saveDocument(_ sender: Any?) { model?.save() }

    @objc func revertDocument(_ sender: Any?) {
        guard let model else { return }
        model.dirty = false
        openRoads(model.url)
    }

    @objc func selectNone(_ sender: Any?) {
        if session?.workspace.viewMode == .map { session?.workspace.selection = [] } else { model?.selection = [] }
    }

    /// Fetches what is missing and builds `tiles` with the pipeline (the road
    /// document open is saved first), then shows them.
    func build(_ tiles: [TileKey]) {
        guard let session, !tiles.isEmpty, let z = tiles.first?.z else { return }
        if let model, model.dirty { model.save() }
        let runner = build ?? BuildRunner()
        build = runner
        let workspace = session.workspace
        workspace.building = true
        runner.run(root: workspace.root, arguments: ["pipeline.py", "\(z)", "--tiles"] + tiles.map { "\($0.x)/\($0.y)" }) {
            workspace.building = false
            workspace.scan()
            let built = tiles.filter { workspace.built.contains($0) }
            if !built.isEmpty { workspace.shown = built } else { workspace.tilesRevision += 1 }
        }
    }

    /// Builds the tiles picked on the map, or else those of the road document open.
    @objc func buildTiles(_ sender: Any?) {
        guard let session else { return }
        var tiles = session.workspace.selection.sorted()
        if session.workspace.viewMode != .map || tiles.isEmpty, let t = model?.doc.tiles {
            tiles = (t.y0...t.y1).flatMap { y in (t.x0...t.x1).map { TileKey(z: t.z, x: $0, y: y) } }
        }
        build(tiles)
    }

    @objc func showMap(_ sender: Any?) { session?.workspace.viewMode = .map }

    @objc func showRoads(_ sender: Any?) { session?.workspace.viewMode = .roads }

    @objc func showTiles(_ sender: Any?) { session?.workspace.viewMode = .tiles }

    @objc func showBuildLog(_ sender: Any?) { build?.window.makeKeyAndOrderFront(nil) }

    // MARK: Menu

    private func menu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        submenu("Immersive Map Editor", [item("Quit Immersive Map Editor", #selector(NSApplication.terminate(_:)), "q")])
        submenu("File", [item("Open Workspace…", #selector(openWorkspace(_:)), "o", [.command, .shift]),
                         item("Open Road Document…", #selector(openDocument(_:)), "o"),
                         item("Save", #selector(saveDocument(_:)), "s"),
                         item("Revert to Saved", #selector(revertDocument(_:))),
                         .separator(),
                         item("Close", #selector(NSWindow.performClose(_:)), "w")])
        submenu("Edit", [item("Undo", Selector(("undo:")), "z"),
                         item("Redo", Selector(("redo:")), "z", [.command, .shift]),
                         .separator(),
                         item("Cut", #selector(NSText.cut(_:)), "x"),
                         item("Copy", #selector(NSText.copy(_:)), "c"),
                         item("Paste", #selector(NSText.paste(_:)), "v"),
                         item("Select None", #selector(selectNone(_:)), "d")])
        submenu("View", [item("Map", #selector(showMap(_:)), "1"),
                         item("Roads", #selector(showRoads(_:)), "2"),
                         item("Tiles 3D", #selector(showTiles(_:)), "3")])
        submenu("Tiles", [item("Fetch and Build", #selector(buildTiles(_:)), "b"),
                          item("Show Build Log", #selector(showBuildLog(_:)), "l")])
        return main
    }
}

// `--resave IN OUT`: reads a document and writes it again, no window. An
// unedited document comes out byte for byte the same.
if let i = CommandLine.arguments.firstIndex(of: "--resave"), CommandLine.arguments.count > i + 2 {
    do {
        let doc = try RoadDocument.read(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        try doc.write(URL(fileURLWithPath: CommandLine.arguments[i + 2]))
        exit(0)
    } catch {
        FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--snapshot TILEPIPELINE OUT.png X/Y...`: built tiles rendered together in
// 3D from above at a slant, no window.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 3 {
    let a = CommandLine.arguments
    let workspace = Workspace(root: URL(fileURLWithPath: a[i + 1]))
    workspace.shown = a[(i + 3)...].compactMap { t in
        let p = t.split(separator: "/").compactMap { Int($0) }
        return p.count == 2 ? TileKey(z: Workspace.zoom, x: p[0], y: p[1]) : nil
    }
    guard let view = TileView(model: workspace) else { exit(1) }
    view.frame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    do {
        try view.snapshot(to: URL(fileURLWithPath: a[i + 2]), width: 1600, height: 1000)
        print(workspace.tileStatus)
        exit(0)
    } catch {
        FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--map-snapshot TILEPIPELINE OUT.png`: the map of tiles as it opens,
// after a few seconds for OpenStreetMap's tiles to come, no window.
if let i = CommandLine.arguments.firstIndex(of: "--map-snapshot"), CommandLine.arguments.count > i + 2 {
    let a = CommandLine.arguments
    let picker = MapPicker(workspace: Workspace(root: URL(fileURLWithPath: a[i + 1])))
    picker.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
    let rep = picker.bitmapImageRepForCachingDisplay(in: picker.bounds)!
    for _ in 0..<4 {
        picker.cacheDisplay(in: picker.bounds, to: rep)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    }
    picker.cacheDisplay(in: picker.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[i + 2]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
