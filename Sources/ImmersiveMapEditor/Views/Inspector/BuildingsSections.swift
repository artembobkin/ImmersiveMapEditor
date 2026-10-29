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
                Text("Click a building, shift-click for more, double-click a whole building with its parts. \(catalog.status)")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else if heldCount == picked.count, let (holder, _) = holders.first, holders.count == 1 {
            Section("Picked: \(picked.count)") {
                Text("All of them are the landmark \"\(holder.name)\"" + (holder.tile == session.workspace.tile?.name ? "." : " of tile \(holder.tile)."))
                    .font(.callout).foregroundStyle(.secondary)
                if holder.tile == session.workspace.tile?.name {
                    Button("Open \(holder.name)", systemImage: "building.columns") { session.pickedLandmark = holder.id }
                }
            }
        } else {
            Section("Make a landmark of \(picked.count - heldCount)") {
                TextField("Name", text: $name, prompt: Text(picked.compactMap(\.name).first ?? "Its name"))
                Button("Make a Landmark of \(picked.count - heldCount) Buildings", systemImage: "building.columns") {
                    session.makeLandmark(named: name.isEmpty ? (picked.compactMap(\.name).first ?? "Landmark") : name, leavingHeld: true)
                    name = ""
                }
                .disabled(picked.count == heldCount)
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
                                Text(verbatim: [b.id, b.isPart ? "part" : nil,
                                                b.height.map { String(format: "%.0f m high", $0) }].compactMap { $0 }.joined(separator: " · "))
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
