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

    var body: some View {
        let _ = session.palette.revision
        let palette = session.palette
        Section("Palettes") {
            Picker("In use", selection: Binding(get: { palette.active }, set: { palette.select($0) })) {
                ForEach(palette.names, id: \.self) { Text($0).tag($0) }
            }
            .help("The palette every build, every run of Claude and every preview paints with, from now on. Also in the toolbar.")
            HStack {
                TextField("New palette", text: $newName, prompt: Text("A name: a city, a style"))
                    .textFieldStyle(.roundedBorder)
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
                TextField("Hex", text: $extraHex, prompt: Text("#B5653F"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit { addExtra() }
                Button("Add", systemImage: "plus") { addExtra() }
                    .labelStyle(.iconOnly)
                    .disabled(!validExtra)
                    .help("A landmark colour this palette has and the defaults do not: Claude is told its name with the others.")
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
            Text("A change is saved at once. A tile paints with it when built again (Build the Tile), a landmark model at its next build (Build from Its Recipe, or Claude's).")
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
