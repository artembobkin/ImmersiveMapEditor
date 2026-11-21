import SwiftUI

/// The sections of the map a tile is chosen on: opening the tile picked, and
/// what the workspace has.
struct MapSections: View {
    @Environment(Session.self) private var session
    @State private var destination = ""
    @State private var placeName = ""
    @State private var automating = false

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
                .help("Fetches its OSM" + (Features.roads ? " and seeds its roads" : "") + " when they are missing, then its views are there. Double-click a tile, or ↩.")
                // Built from here too, without opening it (the user, 2026-11-04).
                PanelButton("Build the Tile…", systemImage: "cube") { session.buildAsked = true }
                    .disabled(!session.canBuildTarget)
                    .help(session.candidate.map { session.workspace.fetched.contains($0) } ?? false
                          ? "Builds the tile picked with the parts you choose; the console shows how far."
                          : "Fetch the tile's OSM first: Open the Tile, or mark it and Fetch OSM.")
            }
        }
        // Typed destinations and kept places (the user, 2026-11-04).
        Section("Go to") {
            HStack {
                TextField("Tile or lat, lon", text: $destination, prompt: Text("15/19808/10243 or 55.7539, 37.6208"))
                    .textFieldStyle(.roundedBorder)
                    // The label is the prompt: in a grouped form a labelled field sat under
                    // its label, right-aligned, its button off its line (the user, 2026-11-05).
                    .labelsHidden().multilineTextAlignment(.leading)
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
                    // The label is the prompt: in a grouped form a labelled field sat under
                    // its label, right-aligned, its button off its line (the user, 2026-11-05).
                    .labelsHidden().multilineTextAlignment(.leading)
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
                    .help("Cuts the OSM of every marked tile that has none from the extracts in the data folder's sources/osm (.osm.pbf, from download.geofabrik.de), each extract read once for all of them. Shift-click marks a tile, a plain click starts over.")
                PanelButton("Automate \(marked.count) Tiles…", systemImage: "wand.and.stars") { automating = true }
                    .help("One agent session goes through the marked tiles: each one's OSM and landmarks, its landmarks modelled by subagents, the engine's archive at the end.")
                    .sheet(isPresented: $automating) { AutomateAreaSheet() }
                PanelButton("Unmark All", systemImage: "xmark.circle") { session.chosen = [] }
            }
        }
        // The fetch of the marked tiles, as it goes and as it came out: how
        // far the extracts are read, how many tiles taken, which were not
        // and why (the user, 2026-11-04: the fetching was not to be
        // understood from the log). One command a zoom, all its tiles cut
        // together, so a tile is counted as taken when it has its OSM now.
        if let job = session.jobs.latest(of: .workspace) as? PipelineJob, job.results.first?.arguments.first == "fetch" || job.current?.first == "fetch" {
            Section(job.state.running ? "Fetching OSM" : "Fetched OSM") {
                if job.state.running {
                    let stage = job.console.stage
                    ProgressView(value: stage?.fraction ?? 0)
                    Text("\(Self.fetchedTiles(job.current ?? []).count) tiles: " + (stage?.name ?? "starting…"))
                        .font(.callout).foregroundStyle(.secondary)
                    if let detail = stage?.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                } else {
                    let asked = job.results.flatMap { Self.fetchedTiles($0.arguments) }
                    let missing = asked.filter { !workspace.fetched.contains($0) }
                    Text("\(asked.count - missing.count) of \(asked.count) fetched" + job.endedStamp + (missing.isEmpty ? "." : ", \(missing.count) not:"))
                        .font(.callout).foregroundStyle(missing.isEmpty ? Color.secondary : Color.red)
                    if !missing.isEmpty {
                        Text(missing.prefix(8).map(\.name).joined(separator: ", ") + (missing.count > 8 ? "…" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(job.results.compactMap(\.note).enumerated()), id: \.offset) { _, note in
                        Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
        Section("Archive") {
            PanelButton("Build Changed Tiles and Export…", systemImage: "square.stack.3d.up", key: "⇧⌘B") { session.buildAllAndExport() }
                .disabled(!session.canBuildAll)
                .help("Of the \(workspace.fetched.count) tiles with their OSM, those whose OSM, landmarks (theirs or a neighbour's) or palette changed since their last build are built again with the parts chosen in Build the Tile, then archived, only the changed tiles baked anew: the Engine map's archive made anew and a copy saved where you choose, the place remembered. A tile that fails is named at the end, the others are archived.")
            PanelButton(TileAction.engine.title, systemImage: TileAction.engine.systemImage) { session.perform(.engine) }
                .disabled(!session.can(.engine))
                .help("Every built tile into the model archive the Engine map reads, in the data folder's engine/.")
        }
        Section("Workspace") {
            Text("\(workspace.built.count) built, \(workspace.fetched.count) fetched" + (Features.roads ? ", \(workspace.documents.count) road documents" : ""))
                .foregroundStyle(.secondary)
            PanelButton("Export Archive…", systemImage: "shippingbox") { session.exportArchive() }
                .disabled(workspace.built.isEmpty || session.jobs.isActive(.workspace))
                .help("Every built tile into one PMTiles archive of model tiles, the file the engine reads, where you choose.")
        }
    }

    /// The tiles a fetch command asks for: `fetch Z X Y` or `fetch Z --tiles X/Y ...`.
    static func fetchedTiles(_ arguments: [String]) -> [TileKey] {
        guard arguments.first == "fetch", arguments.count > 1, let z = Int(arguments[1]) else { return [] }
        if let i = arguments.firstIndex(of: "--tiles") {
            return arguments[(i + 1)...].compactMap { t in
                let p = t.split(separator: "/").compactMap { Int($0) }
                return p.count == 2 ? TileKey(z: z, x: p[0], y: p[1]) : nil
            }
        }
        let n = arguments.dropFirst(2).compactMap { Int($0) }
        return n.count >= 2 ? [TileKey(z: z, x: n[0], y: n[1])] : []
    }
}
