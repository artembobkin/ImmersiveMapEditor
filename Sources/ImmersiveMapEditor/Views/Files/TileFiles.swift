import Foundation

/// What the workspace holds of one tile, as files on disk, in the groups the
/// pipeline writes them: its OSM (data/<z>_<x>_<y>/), its roads (the road
/// document holding it, and what that was seeded from, data/regions/<range>/)
/// and its build (out/tiles/<z>/<x>/<y>/, with bake/). Read from disk each
/// time it is asked: a few folders.
struct TileFiles {
    struct File: Identifiable, Hashable {
        let url: URL
        let size: Int
        let modified: Date?
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    struct Group: Identifiable {
        let title: String
        let systemImage: String
        /// The folder the group's files lie in.
        let folder: URL
        let files: [File]
        var id: String { title }
    }

    let groups: [Group]

    init(tile: TileKey, workspace: Workspace) {
        let root = workspace.root
        var groups = [Group]()
        let data = root.appendingPathComponent("data/\(tile.z)_\(tile.x)_\(tile.y)")
        groups.append(Group(title: "OSM", systemImage: "map", folder: data, files: Self.files(in: data)))
        if let document = workspace.document(holding: tile) {
            let region = root.appendingPathComponent("data/regions/\(document.deletingPathExtension().lastPathComponent)")
            groups.append(Group(title: "Roads", systemImage: "road.lanes", folder: document.deletingLastPathComponent(),
                                files: Self.file(document).map { [$0] } ?? []))
            groups.append(Group(title: "Roads seeded from", systemImage: "point.3.connected.trianglepath.dotted",
                                folder: region, files: Self.files(in: region)))
        } else {
            groups.append(Group(title: "Roads", systemImage: "road.lanes", folder: root.appendingPathComponent("roads"), files: []))
        }
        let out = root.appendingPathComponent("out/tiles/\(tile.z)/\(tile.x)/\(tile.y)")
        groups.append(Group(title: "Build", systemImage: "cube", folder: out, files: Self.files(in: out)))
        self.groups = groups
    }

    /// The files of a folder and of its folders, by name.
    private static func files(in folder: URL) -> [File] {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey,
                                                                                 .contentModificationDateKey],
                                       options: [.skipsHiddenFiles]) else { return [] }
        var out = [File]()
        for case let url as URL in walk {
            if let f = file(url) { out.append(f) }
        }
        return out.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private static func file(_ url: URL) -> File? {
        guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              v.isRegularFile == true else { return nil }
        return File(url: url, size: v.fileSize ?? 0, modified: v.contentModificationDate)
    }
}
