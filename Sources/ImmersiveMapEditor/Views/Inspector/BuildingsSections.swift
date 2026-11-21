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
    @State private var makingLandmarks = false
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
                // The tile's best made landmarks first, to look over on the
                // map and in the list, then modelled, the ones without a
                // model or all anew (the user, 2026-11-04).
                let makeable = LandmarkKind.allCases.contains { !session.toMake($0).isEmpty }
                PanelButton("Make Landmarks…", systemImage: "building.columns") { makingLandmarks = true }
                    .disabled(!makeable)
                    .help(makeable ? "Many of the tile's buildings made landmarks at once: the notable, all the teal ones, the monuments, the tall or the large, all of them or the largest. Nothing is modelled: look them over first."
                          : "Every building of the tile the choices take is a landmark already.")
                    .sheet(isPresented: $makingLandmarks) { MakeLandmarksSheet() }
            }
        } else if heldCount == picked.count, let (holder, _) = holders.first, holders.count == 1 {
            Section("Picked: \(picked.count)") {
                Text("All of them are the landmark \"\(holder.name)\"" + (holder.tile == session.workspace.tile?.name ? "." : " of tile \(holder.tile)."))
                    .font(.callout).foregroundStyle(.secondary)
                if holder.tile == session.workspace.tile?.name {
                    PanelButton("Open \(holder.name)", systemImage: "building.columns") { session.pickedLandmark = holder.id }
                    // Handed to the agent from here, the view staying on the
                    // tile's buildings.
                    DetailPicker()
                    PanelButton("Copy Prompt", systemImage: "doc.on.clipboard") { session.copyPrompt(id: holder.id) }
                        .help("Sets up the landmark's folder for the agent and copies its brief, to paste into the agent started in that folder (Copy Folder Command in its panel).")
                    PanelButton("Delete the Landmark…", systemImage: "trash", role: .destructive) { deleting = session.candidates.first { $0.id == holder.id } }
                        .disabled(session.isBusy(landmark: holder.id))
                        .help("Its folder goes with its photos, recipe, model and rounds.")
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
                // Named by its building, else by its address, else by the nearest
                // street, else "Landmark N" (the user, 2026-11-04: five named "Landmark").
                let fallback = picked.first { $0.name != nil } ?? picked.first { $0.address != nil } ?? picked.first
                let fallbackName = fallback.map(session.nameFor) ?? LandmarkCandidates.nextName(among: session.candidates)
                TextField("Name", text: $name, prompt: Text(fallbackName))
                let title = name.isEmpty ? fallbackName : name
                PanelButton("Make a Landmark of \(picked.count - heldCount) Buildings", systemImage: "building.columns") {
                    session.makeLandmark(named: title, leavingHeld: true)
                    name = ""
                }
                .disabled(picked.count == heldCount)
                .help("Its folder with landmark.json and footprint.geojson, in the list below; nothing is modelled yet, and the view stays here.")
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
