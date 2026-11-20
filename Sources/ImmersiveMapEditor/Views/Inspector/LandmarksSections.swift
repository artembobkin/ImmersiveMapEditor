import SwiftUI

/// The Buildings view's landmark sections, by what the user is doing (the
/// user, 2026-10-29: the buttons that matter now at the top):
///
/// - No landmark open: the tile's landmarks as a list to open, each with
///   whether it has a model.
/// - A landmark open (its model in place of the buildings' map): back, the
///   name and state, then what hands it to the agent the user runs in a
///   terminal (the user, 2026-11-20): the detail, Gather References, the
///   folder's command and the prompt copied, and Build from Its Recipe;
///   the rest folded away: what the agent is asked for, the view, the
///   folder, and what deletes.
struct LandmarksSections: View {
    @Environment(Session.self) private var session
    @AppStorage(AgentSettings.emphasisKey) private var emphasis = "photos"
    @AppStorage(AgentSettings.exaggerationKey) private var exaggeration = 3.0
    @State private var forgetting = false
    @State private var deleting: TileLandmark?
    @State private var settingsShown = false
    @State private var moreShown = false
    /// What was last put on the clipboard and when, for the state line.
    @State private var copied: (what: String, when: Date)?

    var body: some View {
        @Bindable var session = session
        if let landmark = session.candidates.first(where: { $0.id == session.pickedLandmark }) {
            open(landmark)
        } else {
            list
        }
    }

    /// The tile's landmarks, to open.
    @ViewBuilder private var list: some View {
        Section("Landmarks: \(session.candidates.count)") {
            if session.candidates.isEmpty {
                Text("None in this tile yet: pick buildings above and make one.").foregroundStyle(.secondary)
            }
            ForEach(session.candidates) { landmark in
                Button { session.pickedLandmark = landmark.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(landmark.name)
                            Text(verbatim: landmark.buildingsCount + " · " + (landmark.model == nil ? "no model yet" : "model"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.isBusy(landmark: landmark.id) { ProgressView().controlSize(.mini) }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copy Prompt", systemImage: "doc.on.clipboard") { session.copyPrompt(id: landmark.id) }
                    Button("Open Its Folder", systemImage: "folder") { Platform.open(landmark.folder) }
                    Button("Delete \(landmark.name)…", systemImage: "trash", role: .destructive) { deleting = landmark }
                        .disabled(session.isBusy(landmark: landmark.id))
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
        let busy = session.isBusy(landmark: landmark.id)
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
                     + (LandmarkAgent.hasBuilt(landmark.folder) ? " · The agent has worked on it" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Model") {
            PanelButton("Gather References", systemImage: "photo.on.rectangle.angled") { session.gatherReferences(id: landmark.id) }
                .disabled(busy)
                .help("The street photos of every facade from Mapillary, the satellite view and Commons' views, kept into the landmark's references/ ahead of the agent, which otherwise gathers them itself at its first look. The photos already kept stay.")
            DetailPicker()
            PanelButton("Copy Folder Command", systemImage: "terminal") {
                session.copyChangeDirectory(id: landmark.id)
                copied = ("Folder command", Date())
            }
            .help("Copies the cd into the landmark's folder, set up with the modelling tools for Claude Code and Codex: paste it in a terminal, then start your agent there.")
            PanelButton("Copy Prompt", systemImage: "doc.on.clipboard") {
                session.copyPrompt(id: landmark.id)
                copied = ("Prompt", Date())
            }
            .help("Copies the brief with its plan, at the detail set above, to paste into the agent started in the landmark's folder. The models it builds show here as they land.")
            if let copied {
                Text("\(copied.what) copied \(copied.when.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PanelButton("Build from Its Recipe", systemImage: "hammer") { session.buildLandmark() }
                .disabled(busy)
                .help("Builds model.glb from recipe.json (a starter recipe from OSM's tags when there is none).")
        }
        .onChange(of: landmark.id) { copied = nil }
        Section {
            DisclosureGroup("Agent settings", isExpanded: $settingsShown) {
                Picker("Distinctive details", selection: $emphasis) {
                    Text("Off").tag("off")
                    Text("From what the agent knows").tag("known")
                    Text("Known, or from the photos").tag("photos")
                }
                .pickerStyle(.menu)
                .help("The one or two things a person points at from afar, modelled in full and drawn larger than life. From what the agent knows: its own knowledge of the place alone. Or from the photos: for a building it does not know, the roof and corners of the whole-building photo. Off for a plain building. Taken into the prompt when it is copied.")
                Slider(value: $exaggeration, in: 1...4, step: 0.25) { Text(String(format: "Exaggeration ×%.2g", exaggeration)) }
                    .disabled(emphasis == "off")
                    .help("How much larger than life a distinctive detail is drawn: 1 is its real size. Taken when the prompt is copied.")
            }
            DisclosureGroup("More", isExpanded: $moreShown) {
                Toggle("Wireframe", isOn: $session.landmarkWireframe)
                    .help("The model's edges over its shading.")
                PanelButton("Open Its Folder", systemImage: "folder") { Platform.open(landmark.folder) }
                if LandmarkAgent.hasWork(landmark.folder) {
                    PanelButton("Forget Agent's Work…", systemImage: "trash", role: .destructive) { forgetting = true }
                        .disabled(busy)
                        .confirmationDialog("Forget everything the agent made for \(landmark.name)?", isPresented: $forgetting) {
                            Button("Forget the Photos, Recipe and Model", role: .destructive) {
                                LandmarkAgent.forget(landmark.folder)
                                session.landmarkWorkChanged()
                            }
                        } message: {
                            Text("Its photos, renders, recipe and model are deleted. The landmark itself stays.")
                        }
                }
                PanelButton("Delete the Landmark…", systemImage: "trash", role: .destructive) { deleting = landmark }
                    .disabled(busy)
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
