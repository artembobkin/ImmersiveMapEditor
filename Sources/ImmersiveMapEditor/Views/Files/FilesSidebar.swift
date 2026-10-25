import SwiftUI

/// The left panel, the same in every view: the files the workspace holds of
/// the tile shown (open, or picked while choosing), what was fetched, seeded
/// and built and where it lies. A file opens in its app, a folder in Finder.
struct FilesSidebar: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        let workspace = session.workspace
        // Read again when the tiles' builds change or a build ends.
        let _ = (workspace.tilesRevision, session.build.running)
        List {
            Section {
                Button { openURL(workspace.root) } label: {
                    Label(workspace.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("The workspace: everything fetched, seeded and built. Click to open it in Finder.")
            } header: {
                Text("Workspace")
            }
            if let tile = session.shownTile {
                ForEach(TileFiles(tile: tile, workspace: workspace).groups) { group in
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
                        HStack {
                            Label(group.title, systemImage: group.systemImage)
                            Spacer()
                            Button("Open Folder", systemImage: "arrow.up.forward.square") { openURL(group.folder) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help(group.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        }
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
