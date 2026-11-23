import SwiftUI
import TileKit

/// The Style view's sections: the palettes kept and the one in use, what
/// is set over the defaults in it, the landmark colours it adds, where it
/// is kept, and what takes it up.
struct StyleSections: View {
    @Environment(Session.self) private var session
    @State private var resetting = false
    @State private var deleting = false
    @State private var newName = ""
    @State private var extraName = ""
    @State private var extraHex = ""
    @State private var city = ""
    @State private var copied: String?

    var body: some View {
        let _ = session.palette.revision
        let palette = session.palette
        // The palette edited is the one the Tile section's picker shows, above:
        // one picker for one thing (the user, 2026-11-05).
        Section("Palettes") {
            HStack {
                TextField("New palette", text: $newName, prompt: Text("A name: a city, a style"))
                    .textFieldStyle(.roundedBorder)
                    // The label is the prompt: in a grouped form a labelled field sat under
                    // its label, right-aligned, its button off its line (the user, 2026-11-05).
                    .labelsHidden().multilineTextAlignment(.leading)
                    .onSubmit { palette.create(named: newName); newName = "" }
                Button("Add", systemImage: "plus") { palette.create(named: newName); newName = "" }
                    .labelStyle(.iconOnly)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || palette.names.contains(newName.trimmingCharacters(in: .whitespaces)))
                    .help("A new palette, a copy of the one in use under this name, put in use.")
            }
            PanelButton("Delete \(palette.active)…", systemImage: "trash", role: .destructive) { deleting = true }
                .disabled(palette.names.count < 2)
                .confirmationDialog("Delete the palette \(palette.active)?", isPresented: $deleting) {
                    Button("Delete", role: .destructive) { palette.delete(palette.active) }
                } message: {
                    Text("Its file goes; the tiles built with it keep their colours.")
                }
        }
        // A palette made to fit a city with an agent the user starts in a
        // terminal (PaletteMCP; the user, 2026-11-22), its changes shown here
        // as they land (Session.watchFolder).
        Section("Agent") {
            TextField("City", text: $city, prompt: Text("A city: \(palette.active) if empty"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden().multilineTextAlignment(.leading)
                .help("The city the palette is made for. A palette of its name is made from the one shown when there is none; empty, the palette shown is made to fit the city it is named for.")
            PanelButton("Copy Folder Command", systemImage: "terminal") {
                session.copyPaletteFolderCommand()
                copied = "The cd copied: start claude or codex there."
            }
            .help("Sets up the data folder's agent/palette/ with the palette tools for Claude Code and Codex, and copies the cd into it.")
            PanelButton("Copy Prompt", systemImage: "doc.on.clipboard") {
                session.copyPalettePrompt(city: city)
                copied = "The prompt copied: paste it into the session."
            }
            .disabled(city.trimmingCharacters(in: .whitespaces).isEmpty && palette.active == "Common")
            .help("Copies the brief: the agent looks at the city's street photos and sets the palette's colours, each change shown here at once.")
            if let copied { Text(copied).font(.caption).foregroundStyle(.secondary) }
        }
        Section("Landmark colours added") {
            if palette.extras.isEmpty {
                Text("None beyond the defaults.").foregroundStyle(.secondary)
            }
            ForEach(palette.extras, id: \.0) { extra in
                HStack {
                    Text(extra.0).font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(extra.1).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Button { palette.removeExtra(extra.0) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .help("Takes this colour out of the palette.")
                }
            }
            HStack {
                TextField("Name", text: $extraName, prompt: Text("terracotta"))
                    .textFieldStyle(.roundedBorder)
                    // The label is the prompt: in a grouped form a labelled field sat under
                    // its label, right-aligned, its button off its line (the user, 2026-11-05).
                    .labelsHidden().multilineTextAlignment(.leading)
                TextField("Hex", text: $extraHex, prompt: Text("#B5653F"))
                    .textFieldStyle(.roundedBorder)
                    // The label is the prompt: in a grouped form a labelled field sat under
                    // its label, right-aligned, its button off its line (the user, 2026-11-05).
                    .labelsHidden().multilineTextAlignment(.leading)
                    .frame(width: 90)
                    .onSubmit { addExtra() }
                Button("Add", systemImage: "plus") { addExtra() }
                    .labelStyle(.iconOnly)
                    .disabled(!validExtra)
                    .help("A landmark colour this palette has and the defaults do not: the agent is told its name with the others.")
            }
        }
        Section("Set over the defaults") {
            let n = palette.colours.count
            Text(n == 0 ? "Nothing: the defaults." : "\(n) colour\(n == 1 ? "" : "s") set in \(palette.active).")
                .foregroundStyle(.secondary)
            PanelButton("Reset All to the Defaults…", systemImage: "arrow.counterclockwise", role: .destructive) { resetting = true }
                .disabled(n == 0)
                .confirmationDialog("Back to the defaults in \(palette.active)?", isPresented: $resetting) {
                    Button("Reset All", role: .destructive) { palette.resetAll() }
                }
            if let file = palette.file {
                PanelButton("Show the Palette Files", systemImage: "doc") { Platform.reveal(file) }
                    .disabled(!FileManager.default.fileExists(atPath: file.path))
                    .help(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + ", and the palettes kept beside it in palettes/")
            }
        }
        Section("Takes effect") {
            Text("A change is saved at once. A tile paints with it when built again (Build the Tile), a landmark model at its next build (Build from Its Recipe, or the agent’s).")
                .foregroundStyle(.secondary)
        }
        Section("Sun") {
            Text(verbatim: String(format: "From %.0f°, the south-west. Every wall's lit, side and shade tones follow it, and the engine's sun must come from there too.", Palette.sunFrom))
                .foregroundStyle(.secondary)
        }
    }

    private var validExtra: Bool {
        let h = extraHex.trimmingCharacters(in: .whitespaces).uppercased()
        let hex = h.hasPrefix("#") ? h : "#" + h
        return !extraName.trimmingCharacters(in: .whitespaces).isEmpty && hex.count == 7 && Int(hex.dropFirst(), radix: 16) != nil
    }

    private func addExtra() {
        guard validExtra else { return }
        let h = extraHex.trimmingCharacters(in: .whitespaces).uppercased()
        session.palette.addExtra(extraName, h.hasPrefix("#") ? h : "#" + h)
        extraName = ""
        extraHex = ""
    }
}
