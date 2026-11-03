import Foundation
import TileKit

/// What a tile's folder holds (WorkspacePaths: tiles/<z>/<x>/<y>/), in the
/// groups the pipeline writes it: its OSM (osm/), its roads (roads/: the
/// document and what it was seeded from, seed/) and its build (build/, with
/// bake/). Read from disk each time it is asked: a few folders.
struct TileFiles {
    struct File: Identifiable, Hashable {
        let url: URL
        let size: Int
        let modified: Date?
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// A file, or a folder of files and folders: a group's files as a tree.
    struct Node: Identifiable {
        let url: URL
        let file: File?
        let children: [Node]
        var id: URL { url }
        var name: String { url.lastPathComponent }
        /// How many files it holds, all the way down.
        var count: Int { file != nil ? 1 : children.reduce(0) { $0 + $1.count } }
    }

    struct Group: Identifiable {
        let title: String
        let systemImage: String
        /// The folder the group's files lie in.
        let folder: URL
        let files: [File]
        var id: String { title }

        /// Its files as a tree: the folders of `folder` first, by name.
        var tree: [Node] { TileFiles.tree(files, under: folder.standardizedFileURL) }

        init(title: String, systemImage: String, folder: URL) {
            self.title = title
            self.systemImage = systemImage
            self.folder = folder
            files = TileFiles.files(in: folder)
        }
    }

    /// The groups a tile has: the sidebar shows the ones the view needs.
    enum Kind { case osm, roads, build, landmarks, config, engine }

    /// The tile's folder: everything of it.
    let folder: URL
    private let tile: TileKey
    private let paths: WorkspacePaths

    init(tile: TileKey, workspace: Workspace) {
        self.tile = tile
        paths = workspace.paths
        folder = workspace.folder(tile)
    }

    /// Every group of the tile, as the pipeline writes it.
    var all: [Group] { [group(.osm), group(.roads), group(.build), group(.landmarks)] }

    func group(_ kind: Kind) -> Group {
        let (z, x, y) = (tile.z, tile.x, tile.y)
        switch kind {
        case .osm: return Group(title: "OSM", systemImage: "map", folder: paths.tileData(z: z, x: x, y: y))
        case .roads: return Group(title: "Roads", systemImage: "road.lanes", folder: paths.roadDocument(z: z, x: x, y: y).deletingLastPathComponent())
        case .build: return Group(title: "Build", systemImage: "cube", folder: paths.tileOut(z: z, x: x, y: y))
        case .landmarks: return Group(title: "Landmarks", systemImage: "building.columns", folder: paths.tileLandmarks(z: z, x: x, y: y))
        case .config: return Group(title: "Config", systemImage: "paintpalette", folder: paths.config)
        case .engine: return Group(title: "Engine", systemImage: "globe", folder: paths.root.appendingPathComponent("engine"))
        }
    }

    /// One landmark's folder as a group of its own: its references, rounds,
    /// recipe and model at the top, not folded under Landmarks.
    func landmark(_ landmark: TileLandmark) -> Group {
        Group(title: landmark.name, systemImage: "building.columns", folder: landmark.folder)
    }

    static func tree(_ files: [File], under folder: URL) -> [Node] {
        let base = folder.path + "/"
        var direct: [Node] = []
        var below: [String: [File]] = [:]
        for f in files {
            let path = f.url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let rest = path.dropFirst(base.count)
            if let slash = rest.firstIndex(of: "/") {
                below[String(rest[..<slash]), default: []].append(f)
            } else {
                direct.append(Node(url: f.url, file: f, children: []))
            }
        }
        let folders = below.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name -> Node in
            let sub = folder.appendingPathComponent(name)
            return Node(url: sub, file: nil, children: tree(below[name]!, under: sub))
        }
        return folders + direct
    }

    /// The files of a folder and of its folders, by name.
    static func files(in folder: URL) -> [File] {
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
