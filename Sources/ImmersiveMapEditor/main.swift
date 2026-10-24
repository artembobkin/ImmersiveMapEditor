import AppKit
import SwiftUI

/// Immersive Map Editor: the desktop tool for the ImmersiveMap engine's
/// content. Today it corrects the road document of a range of tiles of
/// TilePipeline by hand (its build/roads.py has the format) and shows the
/// built tiles in 3D. Opens the document given as the first argument, else
/// the last one opened, else TilePipeline's first, else asks for one.
///
///   swift run -c release ImmersiveMapEditor ~/Desktop/TilePipeline/roads/15_19808_10242_19809_10243.json
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    var model: EditorModel?
    var map: MapView?
    var build: BuildRunner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = menu()
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let path = args.first {
            open(URL(fileURLWithPath: path))
        } else if let url = lastDocument() ?? pipelineDocument() {
            open(url)
        } else {
            openDocument(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The document opened last, if it is still there.
    private func lastDocument() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: "lastDocument"),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The first road document of TilePipeline, next to this project on the Desktop.
    private func pipelineDocument() -> URL? {
        let roads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/TilePipeline/roads")
        let files = (try? FileManager.default.contentsOfDirectory(at: roads, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.first
    }

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
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func open(_ url: URL) {
        do {
            let model = try EditorModel(url: url)
            let map = MapView()
            map.model = model
            let content = NSHostingView(rootView: ContentView(model: model, map: map, tiles: TileView(model: model)))
            let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                                                 styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                                 backing: .buffered, defer: false)
            window.contentView = content
            window.title = "Immersive Map Editor: \(url.lastPathComponent)"
            window.representedURL = url
            window.delegate = self
            window.setFrameAutosaveName("ImmersiveMapEditor")
            UserDefaults.standard.set(url.path, forKey: "lastDocument")
            if self.window == nil { window.center() }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(map)
            self.window = window
            self.model = model
            self.map = map
            DispatchQueue.main.async { map.frameAll() }
            watchDirty(model, window)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Cannot open \(url.lastPathComponent): \(error.localizedDescription)"
            alert.runModal()
        }
    }

    private var dirtyWatch: Any?
    private func watchDirty(_ model: EditorModel, _ window: NSWindow) {
        dirtyWatch = model.$dirty.sink { [weak window] dirty in window?.isDocumentEdited = dirty }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model?.undo }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmDiscard() }

    // MARK: Actions

    @objc func openDocument(_ sender: Any?) {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "A road document: roads/<z>_<x0>_<y0>_<x1>_<y1>.json"
        if panel.runModal() == .OK, let url = panel.url {
            model?.dirty = false
            open(url)
        } else if window == nil {
            NSApp.terminate(nil)
        }
    }

    @objc func saveDocument(_ sender: Any?) { model?.save() }

    @objc func revertDocument(_ sender: Any?) {
        guard let model else { return }
        model.dirty = false
        open(model.url)
    }

    @objc func deleteSelection(_ sender: Any?) { model?.deleteSelection() }

    @objc func selectNone(_ sender: Any?) { model?.selection = [] }

    /// Saves, then runs the pipeline over the document's tiles.
    @objc func buildTiles(_ sender: Any?) {
        guard let model else { return }
        if model.dirty { model.save() }
        let t = model.doc.tiles
        let runner = build ?? BuildRunner()
        build = runner
        runner.run(root: model.root, arguments: ["pipeline.py", "\(t.z)", "\(t.x0)", "\(t.y0)", "\(t.x1)", "\(t.y1)"]) {
            model.tilesRevision += 1
        }
    }

    @objc func showRoads(_ sender: Any?) { model?.viewMode = .roads }

    @objc func showTiles(_ sender: Any?) { model?.viewMode = .tiles }

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
        submenu("File", [item("Open…", #selector(openDocument(_:)), "o"),
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
        submenu("View", [item("Roads", #selector(showRoads(_:)), "1"),
                         item("Tiles 3D", #selector(showTiles(_:)), "2")])
        submenu("Tiles", [item("Build Tiles", #selector(buildTiles(_:)), "b"),
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

// `--snapshot DOCUMENT OUT.png [X Y]`: the built tiles of a document (or
// one of them) rendered in 3D from above at a slant, no window.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 2 {
    let a = CommandLine.arguments
    do {
        let model = try EditorModel(url: URL(fileURLWithPath: a[i + 1]))
        if a.count > i + 4, let x = Int(a[i + 3]), let y = Int(a[i + 4]) {
            model.tileScope = .one
            model.tileX = x
            model.tileY = y
        }
        guard let view = TileView(model: model) else { exit(1) }
        view.frame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        view.frameTiles()
        try view.snapshot(to: URL(fileURLWithPath: a[i + 2]), width: 1600, height: 1000)
        print(model.tileStatus)
        exit(0)
    } catch {
        FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
