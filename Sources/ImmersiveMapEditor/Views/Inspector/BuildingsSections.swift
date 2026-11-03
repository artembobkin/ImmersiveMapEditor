import SwiftUI
import TileKit

/// The Buildings view's sections, by what the user is doing (the user,
/// 2026-10-29: the buttons that matter now at the top, no long scroll):
///
/// - Nothing picked: the tile's landmarks to open, and a hint.
/// - Buildings picked that belong to no landmark: a name and the button
///   that makes one of them.
/// - Buildings picked that a landmark already holds: one line naming it,
///   with a button that opens it (not a warning a building).
/// - The picked buildings themselves, with their OSM tags, folded away.
struct BuildingsSections: View {
    @Environment(Session.self) private var session
    @State private var name = ""
    @State private var deleting: TileLandmark?
    @State private var listing = false

    /// The landmarks holding any of the picked buildings, each with how many.
    private func holders(of picked: [OsmBuilding]) -> [(Registry.LandmarkRecord, Int)] {
        var holders: [(Registry.LandmarkRecord, Int)] = []
        for b in picked {
            if let h = session.landmark(holding: b.id) {
                if let i = holders.firstIndex(where: { $0.0.tile == h.tile && $0.0.id == h.id }) { holders[i].1 += 1 } else { holders.append((h, 1)) }
            }
        }
        return holders
    }

    var body: some View {
        let catalog = session.buildings
        let picked = catalog.selected
        let holders = holders(of: picked)
        let heldCount = holders.reduce(0) { $0 + $1.1 }
        if picked.isEmpty {
            Section("Make a landmark") {
                Text("None picked. \(catalog.status)").foregroundStyle(.secondary)
                    .help("Click a building, shift-click for more, double-click a whole building with its parts; a double-click on a landmark's building opens the landmark.")
                Toggle("Names", isOn: Binding(get: { catalog.showNames }, set: { catalog.showNames = $0 }))
                    .help("The known buildings named on the map: the notable ones always (an article in Wikipedia or Wikidata, a heritage or historic tag, a church, theatre, station, palace or museum, drawn deeper teal), the merely named when large enough on screen (light teal).")
            }
        } else if heldCount == picked.count, let (holder, _) = holders.first, holders.count == 1 {
            Section("Picked: \(picked.count)") {
                Text("All of them are the landmark \"\(holder.name)\"" + (holder.tile == session.workspace.tile?.name ? "." : " of tile \(holder.tile)."))
                    .font(.callout).foregroundStyle(.secondary)
                if holder.tile == session.workspace.tile?.name {
                    PanelButton("Open \(holder.name)", systemImage: "building.columns") { session.pickedLandmark = holder.id }
                    // Claude on it again from here, model or no model (the user,
                    // 2026-11-03), the view staying on the tile's buildings.
                    if session.agent.isActive(holder.id) {
                        // A run started by mistake stopped from here, where it
                        // was started (the user, 2026-11-03).
                        PanelButton("Stop Claude", systemImage: "stop.circle") { session.agent.stop(holder.id) }
                            .help("Stops Claude on this landmark alone, killed when it does not go in 3 s" + (session.agent.active.count > 1 ? "; the other landmarks go on." : "."))
                    } else {
                        let busy = session.isBusy(landmark: holder.id)
                        PanelButton(busy ? "Building It" : "Model It with Claude Again", systemImage: "sparkles") { session.modelLandmark(id: holder.id) }
                            .disabled(busy)
                            .help("A new attempt from OSM: the photos kept are used again, the recipe, model and conversation of the last one go. The run is queued, the view stays here.")
                    }
                    PanelButton("Delete the Landmark…", systemImage: "trash", role: .destructive) { deleting = session.candidates.first { $0.id == holder.id } }
                        .disabled(session.agent.isActive(holder.id))
                        .help("Its folder goes with its photos, recipe, model and rounds; stop Claude first while it is on it.")
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
        } else {
            Section("Make a landmark of \(picked.count - heldCount)") {
                TextField("Name", text: $name, prompt: Text(picked.compactMap(\.name).first ?? "Its name"))
                let title = name.isEmpty ? (picked.compactMap(\.name).first ?? "Landmark") : name
                PanelButton("Make a Landmark of \(picked.count - heldCount) Buildings", systemImage: "building.columns") {
                    session.makeLandmark(named: title, leavingHeld: true)
                    name = ""
                }
                .disabled(picked.count == heldCount)
                .help("Its folder with landmark.json and footprint.geojson, opened; nothing is modelled yet.")
                PanelButton("Make It and Model with Claude", systemImage: "sparkles") {
                    session.makeLandmarkAndModel(named: title)
                    name = ""
                }
                .disabled(picked.count == heldCount)
                .help("The landmark made and Claude set on it at once, in the queue with the others; the view stays here, its state in the list of landmarks below.")
                ForEach(holders, id: \.0.folder) { holder, count in
                    HStack {
                        Text("\(count) of the picked are the landmark \"\(holder.name)\"" + (holder.tile == session.workspace.tile?.name ? "" : " of tile \(holder.tile)") + ": left out.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        if holder.tile == session.workspace.tile?.name {
                            Button("Open") { session.pickedLandmark = holder.id }.controlSize(.small)
                        }
                    }
                }
            }
        }
        if !picked.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $listing) {
                    ForEach(picked.prefix(60)) { b in
                        DisclosureGroup {
                            ForEach(b.tags.sorted { $0.key < $1.key }, id: \.key) { tag in
                                Text(verbatim: "\(tag.key) = \(tag.value)")
                                    .font(.callout.monospaced()).textSelection(.enabled)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name ?? b.tags["building"].map { "building = \($0)" } ?? "building part")
                                Text(verbatim: [b.id, b.isPart ? "part" : nil, b.height.map { String(format: "%.0f m high", $0) },
                                                BuildingNote.reason(b.tags).map { "notable: \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if picked.count > 60 { Text("and \(picked.count - 60) more").font(.caption).foregroundStyle(.secondary) }
                } label: {
                    Text("Picked buildings: \(picked.count)" + (picked.compactMap(\.name).first.map { ", \($0)" } ?? ""))
                }
            }
        }
    }
}
