import SwiftUI

/// The Buildings view's sections: making the buildings picked a landmark
/// candidate (a folder of what a detailed model can be made from), the
/// buildings picked with all their OSM tags, and the tile's candidates.
struct BuildingsSections: View {
    @Environment(Session.self) private var session
    @State private var name = ""

    var body: some View {
        let catalog = session.buildings
        let picked = catalog.selected
        let held = picked.compactMap { b in session.landmark(holding: b.id).map { (b.id, $0) } }
        Section("Make a landmark") {
            TextField("Name", text: $name, prompt: Text(picked.compactMap(\.name).first ?? "Its name"))
            Button("Make a Landmark of \(picked.count) Buildings", systemImage: "building.columns") {
                session.makeLandmark(named: name.isEmpty ? (picked.compactMap(\.name).first ?? "Landmark") : name)
                name = ""
            }
            .disabled(picked.isEmpty || !held.isEmpty)
            ForEach(held, id: \.0) { osm, holder in
                Text("\(osm) is already part of the landmark \"\(holder.name)\" of tile \(holder.tile): a building belongs to one landmark, in one tile.")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("Writes a folder in the tile's landmarks/ with the buildings' outlines, parts, heights and tags (landmark.json, footprint.geojson) to make a detailed model from. The tile is built as before until a model is placed.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Picked: \(picked.count)") {
            if picked.isEmpty {
                Text("Click a building, shift-click for more. \(catalog.status)").foregroundStyle(.secondary)
            }
            ForEach(picked) { b in
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
        }
        Section("Landmark candidates") {
            let list = session.candidates
            if list.isEmpty { Text("None in this tile yet.").foregroundStyle(.secondary) }
            ForEach(list, id: \.id) { c in
                HStack {
                    Text(c.name)
                    Spacer()
                    Button("Open Folder", systemImage: "folder") { Platform.open(c.folder) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(c.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                }
            }
        }
    }
}
