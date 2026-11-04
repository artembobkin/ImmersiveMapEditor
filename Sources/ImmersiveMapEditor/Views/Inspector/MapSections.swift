import SwiftUI

/// The sections of the map a tile is chosen on: opening the tile picked, and
/// what the workspace has.
struct MapSections: View {
    @Environment(Session.self) private var session
    @State private var destination = ""
    @State private var placeName = ""

    /// The map moved to what is typed; the text stays when it means nothing.
    private func go() {
        if session.goTo(destination) { destination = "" }
    }

    /// Where the map looks kept under the name typed, else the tile's.
    private func keep() {
        let name = placeName.trimmingCharacters(in: .whitespaces)
        session.savePlace(named: name.isEmpty ? (session.candidate?.name ?? "Place \(session.places.all.count + 1)") : name)
        placeName = ""
    }

    var body: some View {
        let workspace = session.workspace
        Section("Open") {
            if session.phase == .preparing {
                Text("Preparing the tile: the console shows how far.").foregroundStyle(.secondary)
            } else {
                PanelButton("Open the Tile", systemImage: "arrow.right.circle") {
                    if let t = session.candidate { session.open(tile: t) }
                }
                .disabled(session.candidate.map { session.jobs.isActive(.tile($0)) } ?? true)
                .help("Fetches its OSM and seeds its roads when they are missing, then its views are there. Double-click a tile, or ↩.")
                // Built from here too, without opening it (the user, 2026-11-04).
                PanelButton("Build the Tile…", systemImage: "cube") { session.buildAsked = true }
                    .disabled(!session.canBuildTarget)
                    .help(session.candidate.map { session.workspace.fetched.contains($0) } ?? false
                          ? "Builds the tile picked with the parts you choose, its light not baked; the console shows how far."
                          : "Fetch the tile's OSM first: Open the Tile, or mark it and Fetch OSM.")
            }
        }
        // Typed destinations and kept places (the user, 2026-11-04).
        Section("Go to") {
            HStack {
                TextField("Tile or lat, lon", text: $destination, prompt: Text("15/19808/10243 or 55.7539, 37.6208"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { go() }
                    .help("A tile's number z/x/y, or a latitude and longitude: ↩ moves the map there and picks the tile.")
                Button("Go", systemImage: "location") { go() }
                    .labelStyle(.iconOnly)
                    .disabled(Places.destination(destination) == nil)
                    .help("Moves the map to what is typed and picks the tile.")
            }
            HStack {
                TextField("Name", text: $placeName, prompt: Text(session.candidate?.name ?? "A name for this place"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { keep() }
                Button("Save", systemImage: "bookmark") { keep() }
                    .labelStyle(.iconOnly)
                    .help("Keeps where the map looks now under this name, in the data folder's config/places.json.")
            }
            ForEach(session.places.all) { place in
                HStack {
                    Button { session.jump(to: place) } label: {
                        HStack {
                            Text(place.name).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.4f, %.4f", place.latitude, place.longitude)).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Moves the map there.")
                    Button { session.places.remove(place) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .help("Forgets this place.")
                }
            }
        }
        // Several tiles marked with shift-clicks, their OSM fetched at once
        // (the user, 2026-11-04: one tile at a time was no way to get data).
        let marked = session.chosen.union(session.candidate.map { [$0] } ?? [])
        if marked.count > 1 {
            let toFetch = session.chosenToFetch.count
            Section("Marked: \(marked.count) tiles") {
                Text(toFetch == 0 ? "All of them have their OSM." : "\(marked.count - toFetch) with their OSM, \(toFetch) without.")
                    .foregroundStyle(.secondary)
                PanelButton("Fetch OSM for \(toFetch) Tile" + (toFetch == 1 ? "" : "s"), systemImage: "square.and.arrow.down") { session.fetchChosen() }
                    .disabled(toFetch == 0 || session.jobs.isActive(.workspace))
                    .help("Fetches the OSM of every marked tile that has none, one after another, the console counting them. Shift-click marks a tile, a plain click starts over.")
                PanelButton("Unmark All", systemImage: "xmark.circle") { session.chosen = [] }
            }
        }
        // The fetch of the marked tiles, as it goes and as it came out: which
        // tile now, how many done, which failed and why (the user,
        // 2026-11-04: the fetching was not to be understood from the log).
        if let job = session.jobs.latest(of: .workspace) as? PipelineJob, job.results.first?.arguments.first == "fetch" || job.current?.first == "fetch" {
            Section(job.state.running ? "Fetching OSM" : "Fetched OSM") {
                if job.state.running {
                    let step = job.console.step
                    ProgressView(value: Double(max(0, step.index - 1)), total: Double(max(1, step.count)))
                    Text(job.current.map { "\(step.index) of \(step.count): tile \($0.dropFirst(1).joined(separator: "/"))" } ?? "Starting…")
                        .font(.callout).foregroundStyle(.secondary)
                    if let detail = job.console.stage?.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                } else {
                    let done = job.results.filter(\.ok).count, failed = job.results.filter { !$0.ok }
                    Text("\(done) of \(job.results.count) fetched" + job.endedStamp + (failed.isEmpty ? "." : ", \(failed.count) failed:"))
                        .font(.callout).foregroundStyle(failed.isEmpty ? Color.secondary : Color.red)
                    ForEach(Array(failed.enumerated()), id: \.offset) { _, r in
                        Text(r.arguments.dropFirst(1).joined(separator: "/") + (r.note.map { ": \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !failed.isEmpty {
                        Text("The tiles that failed stay marked: Fetch OSM again when Overpass is back.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Section("Archive") {
            PanelButton(TileAction.engine.title, systemImage: TileAction.engine.systemImage) { session.perform(.engine) }
                .disabled(!session.can(.engine))
                .help("Every built tile into the model archive the Engine map reads, in the data folder's engine/.")
        }
        // Every run of Claude of this session, whatever tile: going, queued,
        // then ended, the latest first; a row opens its tile and landmark
        // (the user, 2026-11-04: runs started in many tiles, nowhere seen
        // together).
        let runs = session.agent.runs
        if !runs.isEmpty {
            let going = runs.filter(\.state.running).count, queued = runs.filter { $0.state.active && !$0.state.running }.count
            Section("Claude: \(going) running" + (queued > 0 ? ", \(queued) queued" : "") + (runs.count - going - queued > 0 ? ", \(runs.count - going - queued) ended" : "")) {
                ForEach(session.agent.listed, id: \.id) { run in
                    Button {
                        if let tile = run.tile { session.open(tile: tile, landmark: run.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.name).lineLimit(1)
                                Text(verbatim: (run.tile?.name ?? "") + " · " + run.status + runElapsed(run))
                                    .font(.caption).foregroundStyle(run.state.isFailed ? .red : .secondary)
                            }
                            Spacer()
                            if run.state.running { ProgressView().controlSize(.mini) }
                            if run.state.active {
                                Button { session.agent.stop(run.id) } label: { Image(systemName: "stop.circle") }
                                    .buttonStyle(.borderless)
                                    .help("Stops Claude on \(run.name).")
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Opens the tile and the landmark.")
                }
                if session.agent.running {
                    PanelButton("Stop All", systemImage: "stop.circle") { session.agent.stopAll() }
                        .help("Stops every run of Claude, going and queued.")
                }
            }
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched, \(workspace.documents.count) road documents")
                .foregroundStyle(.secondary)
            PanelButton("Export Archive…", systemImage: "shippingbox") { session.exportArchive() }
                .disabled(workspace.built.isEmpty || session.jobs.isActive(.workspace))
                .help("Every built tile into one PMTiles archive of model tiles, the file the engine reads, where you choose.")
        }
    }

    /// How long a run has been going, ", 4 min" after its status; nothing when it is not.
    private func runElapsed(_ run: LandmarkRun) -> String {
        guard run.state.running, let started = run.started else { return "" }
        let s = Int(Date().timeIntervalSince(started))
        return s < 60 ? ", \(s) s" : ", \(s / 60) min"
    }
}
