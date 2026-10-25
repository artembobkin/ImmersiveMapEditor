import SwiftUI

/// The menus: workspaces and documents, saving, the views, building.
struct EditorCommands: Commands {
    let session: Session
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
                if session.workspace.viewMode == .map { session.workspace.tile = nil } else { session.model?.selection = [] }
            }
            .keyboardShortcut("d")
        }
        CommandGroup(before: .toolbar) {
            Button("Map") { session.workspace.viewMode = .map }.keyboardShortcut("1")
            Button("Roads") { session.workspace.viewMode = .roads }.keyboardShortcut("2")
            Button("Tiles 3D") { session.workspace.viewMode = .tiles }.keyboardShortcut("3")
            Button("Light") { session.workspace.viewMode = .light }.keyboardShortcut("4")
            Button("Landmarks") { session.workspace.viewMode = .landmarks }.keyboardShortcut("5")
            Divider()
        }
        CommandMenu("Tiles") {
            Button("Fetch and Build the Tile") { session.buildTile() }
            .keyboardShortcut("b")
            .disabled(session.build.running || session.workspace.tile == nil)
            Button(session.build.shown ? "Hide Build Log" : "Show Build Log") { session.build.shown.toggle() }.keyboardShortcut("l")
        }
    }
}
