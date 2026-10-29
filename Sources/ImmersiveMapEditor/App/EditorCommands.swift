import SwiftUI

/// The menus: workspaces and documents, saving, the views, building.
struct EditorCommands: Commands {
    let session: Session
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {
            Button("Save") { session.model?.save() }
                .keyboardShortcut("s")
                .disabled(session.model == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Select None") { session.model?.selection = [] }
                .keyboardShortcut("d")
                .disabled(session.model == nil)
        }
        CommandGroup(before: .toolbar) {
            // The views over the open tile, there once one is open.
            ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { i, mode in
                Button(mode.rawValue) { session.workspace.viewMode = mode }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                    .disabled(session.phase != .working)
            }
            Divider()
            // Which panels show: the app's setting, kept between runs.
            Toggle("Files", isOn: Binding(get: { session.panels.files }, set: { session.panels.files = $0 }))
                .keyboardShortcut("1", modifiers: [.command, .option])
            Toggle("Console", isOn: Binding(get: { session.panels.console }, set: { session.panels.console = $0 }))
                .keyboardShortcut("l")
            Toggle("Inspector", isOn: Binding(get: { session.panels.inspector }, set: { session.panels.inspector = $0 }))
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
        }
        CommandMenu("Tile") {
            if session.phase == .choosing {
                Button("Open the Tile Picked") { if let t = session.candidate { session.open(tile: t) } }
                    .keyboardShortcut(.return)
                    .disabled(session.candidate == nil || session.build.running)
            } else {
                Button("Choose Another Tile") { session.chooseAnotherTile() }
                    .keyboardShortcut("0")
                    .disabled(session.phase != .working)
            }
            Divider()
            if session.phase == .working {
                // The view's actions: the first on ⌘B.
                ForEach(Array(session.workspace.viewMode.actions.enumerated()), id: \.offset) { i, action in
                    let button = Button(action.title) { session.perform(action) }.disabled(!session.can(action))
                    if i == 0 { button.keyboardShortcut("b") } else { button }
                }
            }
        }
    }
}
