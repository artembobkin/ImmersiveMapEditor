import AppKit
import SwiftUI

/// The left panel, the same in every view: the tile shown (open, or picked
/// while choosing), its folder (everything of it, to look at or delete as
/// one) and its files, fetched, seeded and built. A file opens in its app.
struct FilesSidebar: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        // Read again when the tiles' builds change or a build ends.
        let _ = (workspace.tilesRevision, session.build.running)
        List {
            if let tile = session.shownTile {
                let files = TileFiles(tile: tile, workspace: workspace)
                let exists = FileManager.default.fileExists(atPath: files.folder.path)
                Section {
                    Button { Platform.open(files.folder) } label: {
                        Label("Open Tile Folder", systemImage: "folder")
                    }
                    .disabled(!exists)
                    .help(exists ? files.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                                 : "The tile has no folder yet: opening it fetches its OSM")
                } header: {
                    Text(verbatim: tile.name)
                }
                ForEach(files.groups) { group in
                    Section {
                        if group.files.isEmpty {
                            Text("Nothing yet").foregroundStyle(.secondary)
                        }
                        ForEach(group.tree) { NodeRow(node: $0) }
                    } header: {
                        Label(group.title, systemImage: group.systemImage)
                    }
                }
            } else {
                Text("Pick a tile on the map: its files show here.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}

/// A file, or a folder folded until opened (a landmark, its references,
/// its views), so a group stays short.
private struct NodeRow: View {
    let node: TileFiles.Node

    var body: some View {
        if let file = node.file {
            FileRow(file: file)
                .contextMenu {
                    Button("Open") { Platform.open(file.url) }
                    Button("Show in Finder") { Platform.reveal(file.url) }
                }
                .onTapGesture(count: 2) { Platform.open(file.url) }
        } else {
            DisclosureGroup {
                ForEach(node.children) { NodeRow(node: $0) }
            } label: {
                HStack {
                    Label(node.name, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(node.count)").font(.caption).foregroundStyle(.secondary)
                }
                .contextMenu { Button("Open in Finder") { Platform.open(node.url) } }
            }
        }
    }
}

/// A file of a tile: its name, its size and age. A picture shows itself
/// large over the main area while the pointer rests on it (a popover would
/// take the pointer and close itself).
private struct FileRow: View {
    let file: TileFiles.File
    @Environment(Session.self) private var session
    @State private var hovering = false

    static let pictures: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
    var isPicture: Bool { Self.pictures.contains(file.url.pathExtension.lowercased()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(file.name).lineLimit(1).truncationMode(.middle)
            Text([ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file),
                  file.modified.map { $0.formatted(.relative(presentation: .named)) }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .help(file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .onHover { over in
            guard isPicture else { return }
            hovering = over
            if over {
                // A moment's rest before the picture comes, so a pass over the
                // list does not flash every one.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    if hovering { session.hoveredPicture = file.url }
                }
            } else if session.hoveredPicture == file.url {
                session.hoveredPicture = nil
            }
        }
    }
}

/// The picture the pointer rests on in the files sidebar, large over the
/// main area, under the pointer's notice.
struct PicturePreview: View {
    @Environment(Session.self) private var session

    var body: some View {
        if let url = session.hoveredPicture, let image = NSImage(contentsOf: url) {
            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 12)
            .padding(16)
            .frame(maxWidth: 900, maxHeight: 700, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}
