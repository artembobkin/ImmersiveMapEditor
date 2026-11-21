import SwiftUI
import TileKit

/// The Settings section of the OSM extracts the tiles' OSM is cut from: the
/// data folder's `sources/osm/`, where the user puts the `.osm.pbf` files
/// they downloaded (the user, 2026-11-21: no public API asked). Each with
/// the box it covers and the date of its data; the folder opened in Finder
/// to add or remove one.
struct OsmExtractsSection: View {
    let paths: WorkspacePaths
    @State private var extracts: [OsmExtract] = []
    @State private var unreadable: [String] = []

    var body: some View {
        Section("OpenStreetMap extracts") {
            if extracts.isEmpty && unreadable.isEmpty {
                Text("None: no tile's OSM can be fetched.").foregroundStyle(.secondary)
            }
            ForEach(extracts, id: \.url) { extract in
                LabeledContent(extract.name) {
                    Text(Self.describe(extract)).font(.caption).foregroundStyle(.secondary)
                }
                .help(String(format: "Covers %.3f° to %.3f° north, %.3f° to %.3f° east (its box: the region inside it may be smaller).",
                             extract.south, extract.north, extract.west, extract.east))
            }
            ForEach(unreadable, id: \.self) { name in
                LabeledContent(name) { Text("not an OSM PBF file").font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Button("Show in Finder") {
                    let folder = OsmExtract.folder(paths)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    Platform.open(folder)
                }
                .help("The folder the extracts are kept in: put a region's .osm.pbf there, then Reload.")
                Button("Reload") { load() }
                Spacer()
                Link("download.geofabrik.de", destination: URL(string: "https://download.geofabrik.de/")!)
                    .font(.callout)
                    .help("Geofabrik's extracts of every country and region, updated daily. A tile near a region's border takes the extract beside it too.")
            }
        }
        .task(id: paths.root) { load() }
    }

    private func load() {
        (extracts, unreadable) = OsmExtract.all(paths)
    }

    /// Its size and the date of its data: "499 MB, data of 20 Nov 2026".
    static func describe(_ extract: OsmExtract) -> String {
        let size = (try? extract.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        var text = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        if let date = extract.timestamp { text += ", data of " + date.formatted(date: .abbreviated, time: .omitted) }
        return text
    }
}
