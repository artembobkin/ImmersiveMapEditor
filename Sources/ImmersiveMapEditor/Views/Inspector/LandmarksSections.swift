import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Buildings view's landmark sections, by what the user is doing (the
/// user, 2026-10-29: the buttons that matter now at the top):
///
/// - No landmark open: the tile's landmarks as a list to open, each with
///   whether it has a model.
/// - A landmark open (its model in place of the buildings' map): back, the
///   name and state, then the two buttons that matter, Model with Claude
///   (or Stop) and Build from Its Recipe, the request field when a
///   conversation is on, and the rest folded away: Claude's settings, the
///   view, the folder, and what deletes.
struct LandmarksSections: View {
    @Environment(Session.self) private var session
    @AppStorage(ClaudeSettings.modelKey) private var model = ""
    @AppStorage(ClaudeSettings.effortKey) private var effort = ""
    @AppStorage(ClaudeSettings.emphasisKey) private var emphasis = "photos"
    @AppStorage(ClaudeSettings.exaggerationKey) private var exaggeration = 2.0
    @AppStorage(ClaudeSettings.turnsPerFacadeKey) private var turnsPerFacade = 3
    @AppStorage(ClaudeSettings.atOnceKey) private var atOnce = 3
    @State private var forgetting = false
    @State private var deleting: TileLandmark?
    @State private var settingsShown = false
    @State private var moreShown = false
    /// The open landmark's facades, for the turn limit's words.
    @State private var facades = 4

    var body: some View {
        @Bindable var session = session
        if let landmark = session.candidates.first(where: { $0.id == session.pickedLandmark }) {
            open(landmark)
        } else {
            list
        }
    }

    /// The tile's landmarks in the order the list shows them: the ones Claude
    /// is modelling first, then the queued, then the runs ended this
    /// session, the latest first, to look at what came of them, then the
    /// rest as their folders sort (the user, 2026-11-02: the work in
    /// progress and just done at the top).
    private var listed: [TileLandmark] {
        func key(_ landmark: TileLandmark, _ offset: Int) -> (Int, Double, Int) {
            guard let run = session.agent.run(of: landmark.id) else { return (3, 0, offset) }
            if run.state.running { return (0, 0, offset) }
            if run.state.active { return (1, 0, offset) }
            return (2, -(run.ended?.timeIntervalSinceReferenceDate ?? 0), offset)
        }
        return session.candidates.enumerated().sorted { key($0.element, $0.offset) < key($1.element, $1.offset) }.map(\.element)
    }

    /// The tile's landmarks, to open.
    @ViewBuilder private var list: some View {
        Section("Landmarks: \(session.candidates.count)") {
            if session.candidates.isEmpty {
                Text("None in this tile yet: pick buildings above and make one.").foregroundStyle(.secondary)
            }
            ForEach(listed) { landmark in
                Button { session.pickedLandmark = landmark.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(landmark.name)
                            Text(verbatim: landmark.buildingsCount + " · " + (landmark.model == nil ? "no model yet" : "model"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let run = session.agent.run(of: landmark.id) {
                            if run.state.running { ProgressView().controlSize(.mini) }
                            Text(run.status).font(.caption).foregroundStyle(run.state.isFailed ? .red : .secondary)
                            // A run stopped from the list, where its state
                            // shows (the user, 2026-11-03: one started by
                            // mistake with no way to cut it short).
                            if run.state.active {
                                Button { session.agent.stop(landmark.id) } label: {
                                    Image(systemName: "stop.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Stops Claude on \(landmark.name), killed when it does not go in 3 s.")
                            }
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if session.agent.isActive(landmark.id) {
                        Button("Stop Claude", systemImage: "stop.circle") { session.agent.stop(landmark.id) }
                    }
                    Button("Open Its Folder", systemImage: "folder") { Platform.open(landmark.folder) }
                    Button("Delete \(landmark.name)…", systemImage: "trash", role: .destructive) { deleting = landmark }
                        .disabled(session.agent.isActive(landmark.id))
                }
            }
        }
        .confirmationDialog("Delete the landmark \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete the Landmark and Everything in Its Folder", role: .destructive) {
                if let landmark = deleting { session.deleteLandmark(landmark) }
                deleting = nil
            }
        } message: {
            Text("Its folder goes with its photos, recipe, model and rounds. Its buildings are built as ordinary ones at the next build.")
        }
    }

    /// One landmark open.
    @ViewBuilder private func open(_ landmark: TileLandmark) -> some View {
        @Bindable var session = session
        Section {
            HStack {
                Button("Back", systemImage: "chevron.left") { session.pickedLandmark = nil }
                    .help("The tile's buildings from above again.")
                Spacer()
                Picker("", selection: Binding(get: { landmark.id }, set: { session.pickedLandmark = $0 })) {
                    ForEach(session.candidates) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(maxWidth: 180)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(landmark.name).font(.headline)
                Text(verbatim: landmark.buildingsCount + " · " + (landmark.model == nil ? "no model yet: its OSM boxes" : landmark.model!.lastPathComponent)
                     + (LandmarkAgent.hasConversation(landmark.folder) ? " · Claude has worked on it" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Model") {
            if session.agent.isActive(landmark.id) {
                PanelButton("Stop Claude", systemImage: "stop.circle") { session.agent.stop(landmark.id) }
                    .help("Stops Claude on this landmark alone, killed when it does not go in 3 s" + (session.agent.active.count > 1 ? "; the other landmarks go on." : "."))
            } else {
                PanelButton("Model with Claude", systemImage: "sparkles") { session.modelLandmark() }
                    .help("A new attempt from OSM: Claude Code gathers freely licensed photos (the ones kept are used again), writes the recipe, renders and corrects it. Through the proxy of Settings > Claude.")
            }
            if LandmarkAgent.hasConversation(landmark.folder) {
                RequestField(landmark: landmark)
            }
            PanelButton("Build from Its Recipe", systemImage: "hammer") { session.buildLandmark() }
                .disabled(session.isBusy(landmark: landmark.id))
                .help("Builds model.glb from recipe.json (a starter recipe from OSM's tags when there is none).")
        }
        Section {
            DisclosureGroup("Claude's settings", isExpanded: $settingsShown) {
                Picker("Model", selection: $model) {
                    Text("Default").tag("")
                    Text("Fable").tag("fable")
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                .pickerStyle(.menu).disabled(session.agent.running)
                .help("Which Claude models the landmark: Claude Code's default, or one by name.")
                Picker("Effort", selection: $effort) {
                    Text("Default").tag("")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Extra high").tag("xhigh")
                    Text("Max").tag("max")
                }
                .pickerStyle(.menu).disabled(session.agent.running)
                .help("How hard Claude thinks before each step: more is slower and dearer, and steadier on the geometry.")
                Picker("Distinctive details", selection: $emphasis) {
                    Text("Off").tag("off")
                    Text("From what Claude knows").tag("known")
                    Text("Known, or from the photos").tag("photos")
                }
                .pickerStyle(.menu).disabled(session.agent.running)
                .help("The one or two things a person points at from afar, modelled in full and drawn larger than life. From what Claude knows: its own knowledge of the place alone. Or from the photos: for a building it does not know, the roof and corners of the whole-building photo. Off for a plain building.")
                Slider(value: $exaggeration, in: 1...4, step: 0.25) { Text(String(format: "Exaggeration ×%.2g", exaggeration)) }
                    .disabled(session.agent.running || emphasis == "off")
                    .help("How much larger than life a distinctive detail is drawn: 1 is its real size.")
                Stepper("Turn limit a facade: \(turnsPerFacade)", value: $turnsPerFacade, in: 0...20)
                    .disabled(session.agent.running)
                    // The count once a landmark, off the main thread: in the
                    // body it ran at every redraw (the user, 2026-11-03).
                    .task(id: landmark.id) {
                        let folder = landmark.folder
                        facades = await Task.detached { LandmarkMCP.Server.facadeCount(folder) }.value
                    }
                    .help("The most replies Claude may make for one landmark, a safety stop: this many a facade and 8 besides, "
                          + (turnsPerFacade > 0 ? "\(ClaudeSettings.maxTurns(facades: facades)) for this one with its \(facades) facades." : "none now: no limit."))
                Stepper("At once: \(atOnce)", value: $atOnce, in: 1...6)
                    .onChange(of: atOnce) { session.agent.pump() }
                    .help("How many landmarks Claude models at the same time, each a session of its own; the rest wait their turn, and the references are gathered for one at a time.")
            }
            DisclosureGroup("More", isExpanded: $moreShown) {
                Toggle("Wireframe", isOn: $session.landmarkWireframe)
                    .help("The model's edges over its shading.")
                PanelButton("Open Its Folder", systemImage: "folder") { Platform.open(landmark.folder) }
                if LandmarkAgent.hasWork(landmark.folder) {
                    PanelButton("Forget Claude's Work…", systemImage: "trash", role: .destructive) { forgetting = true }
                        .disabled(session.isBusy(landmark: landmark.id))
                        .confirmationDialog("Forget everything Claude made for \(landmark.name)?", isPresented: $forgetting) {
                            Button("Forget the Photos, Recipe and Model", role: .destructive) {
                                LandmarkAgent.forget(landmark.folder)
                                session.landmarkWorkChanged()
                            }
                        } message: {
                            Text("Its photos, renders, recipe, model and conversation are deleted. The landmark itself stays.")
                        }
                }
                PanelButton("Delete the Landmark…", systemImage: "trash", role: .destructive) { deleting = landmark }
                    .disabled(session.agent.isActive(landmark.id))
                    .confirmationDialog("Delete the landmark \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                        Button("Delete the Landmark and Everything in Its Folder", role: .destructive) {
                            if let landmark = deleting { session.deleteLandmark(landmark) }
                            deleting = nil
                        }
                    } message: {
                        Text("Its folder goes with its photos, recipe, model and rounds. Its buildings are built as ordinary ones at the next build.")
                    }
            }
        }
    }
}

/// A request to Claude about the landmark, with screenshots: typed, with
/// pictures attached by a button, dropped on it, or pasted (⌘V after a
/// screenshot to the clipboard). Enter sends.
private struct RequestField: View {
    let landmark: TileLandmark
    @Environment(Session.self) private var session
    @State private var text = ""
    @State private var pictures: [URL] = []
    @State private var dropping = false

    private var busy: Bool { session.agent.isActive(landmark.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Ask Claude to change it…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", systemImage: "paperplane", action: send)
                    .labelStyle(.iconOnly)
                    .disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pictures.isEmpty))
            }
            HStack(spacing: 8) {
                Button("Attach Screenshot…", systemImage: "photo.badge.plus") { pick() }
                    .controlSize(.small)
                ForEach(pictures, id: \.self) { url in
                    HStack(spacing: 2) {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 28)
                        }
                        Button("", systemImage: "xmark.circle.fill") { pictures.removeAll { $0 == url } }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
            }
            if busy {
                Text("Claude is still working on it: wait, or Stop Claude.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !pictures.isEmpty {
                Text("\(pictures.count) picture\(pictures.count == 1 ? "" : "s") go with the request.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Drop or paste a screenshot here to show Claude a detail.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(dropping ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers in
            for p in providers {
                if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { Task { @MainActor in self.add(url) } }
                    }
                } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    p.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                        if let data { Task { @MainActor in self.add(data: data) } }
                    }
                }
            }
            return true
        }
        .onPasteCommand(of: [.image, .png, .fileURL]) { providers in
            for p in providers {
                p.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                    if let data { Task { @MainActor in self.add(data: data) } }
                }
            }
        }
    }

    /// The requests' pictures live in the landmark's folder, requests/.
    private var folder: URL { landmark.folder.appendingPathComponent("requests") }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Pictures to show Claude: screenshots of what to change."
        if panel.runModal() == .OK { for url in panel.urls { add(url) } }
    }

    private func add(_ url: URL) {
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        add(data: png)
    }

    private func add(data: Data) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("\(stamp)-\(pictures.count + 1).png")
        guard (try? data.write(to: url)) != nil else { return }
        pictures.append(url)
    }

    private func send() {
        guard !busy else { return }
        var request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty || !pictures.isEmpty else { return }
        if !pictures.isEmpty {
            request += (request.isEmpty ? "" : "\n") + "The user attached \(pictures.count) picture\(pictures.count == 1 ? "" : "s") (screenshots of the model or of the building) to show what to change: look at each first with show_user_picture: "
                + pictures.map(\.lastPathComponent).joined(separator: ", ") + "."
        }
        text = ""
        pictures = []
        session.modelLandmark(request: request)
    }
}
