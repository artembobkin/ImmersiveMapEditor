import SwiftUI

/// The left panel, the same in every view: the tile shown (open, or picked
/// while choosing), its folder (everything of it, to look at or delete as
/// one) and its files, fetched, seeded and built. A file opens in its app.
struct FilesSidebar: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        let workspace = session.workspace
        // Read again when the tiles' builds change or a build ends.
        let _ = (workspace.tilesRevision, session.build.running)
        List {
            if let tile = session.shownTile {
                let files = TileFiles(tile: tile, workspace: workspace)
                let exists = FileManager.default.fileExists(atPath: files.folder.path)
                Section {
                    Button { openURL(files.folder) } label: {
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
                        ForEach(group.files) { file in
                            FileRow(file: file, folder: group.folder)
                                .contextMenu {
                                    Button("Open") { openURL(file.url) }
                                    Button("Open Its Folder") { openURL(file.url.deletingLastPathComponent()) }
                                }
                                .onTapGesture(count: 2) { openURL(file.url) }
                        }
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

/// A file of a tile: its path within its group's folder, its size and age.
private struct FileRow: View {
    let file: TileFiles.File
    let folder: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(relative).lineLimit(1).truncationMode(.middle)
            Text([ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file),
                  file.modified.map { $0.formatted(.relative(presentation: .named)) }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .help(file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }

    private var relative: String {
        let base = folder.standardizedFileURL.path + "/"
        let path = file.url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : file.name
    }
}
