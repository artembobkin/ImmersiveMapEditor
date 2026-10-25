import Foundation

/// Where the build reads and writes: the app's data folder (its workspace,
/// "Immersive Map Editor Data" by default) and the hand-made models of
/// Modeling. Passed to whatever reads or writes a file, never kept in a
/// global, so two workspaces can be built side by side and every function
/// says what it touches.
///
/// Everything of a tile lies in its one folder, so a tile is looked at,
/// moved or deleted as one:
///
///   tiles/<z>/<x>/<y>/osm/          its raw sources (Fetch): osm.json, tile.json
///   tiles/<z>/<x>/<y>/roads/        its road document, roads.json, hand-edited,
///                                   and seed/, what it was seeded from (Seed)
///   tiles/<z>/<x>/<y>/build/        its built model (Build, Bake)
///   tiles/<z>/<x>/<y>/landmarks/    its buildings marked to become landmarks, a
///                                   folder each (the editor's Buildings view)
///   tiles/index.json                the last build of every tile
///   landmarks/                      recipes, the landmark registry, downloaded models
///   config/                         what OSM shows but the place does not have
public struct WorkspacePaths: Sendable {
    public let root: URL
    /// Hand-made models of ~/Desktop/Modeling, read only.
    public let modeling: URL

    public static let defaultModeling = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/Modeling")

    public init(root: URL, modeling: URL = WorkspacePaths.defaultModeling) {
        self.root = root.standardizedFileURL
        self.modeling = modeling
    }

    public var landmarks: URL { root.appendingPathComponent("landmarks") }
    public var config: URL { root.appendingPathComponent("config") }
    public var tiles: URL { root.appendingPathComponent("tiles") }

    /// A tile's folder: everything of it.
    public func tile(z: Int, x: Int, y: Int) -> URL { tiles.appendingPathComponent("\(z)/\(x)/\(y)") }

    /// A tile's raw sources.
    public func tileData(z: Int, x: Int, y: Int) -> URL { tile(z: z, x: x, y: y).appendingPathComponent("osm") }

    /// A tile's road document, hand-edited.
    public func roadDocument(z: Int, x: Int, y: Int) -> URL {
        tile(z: z, x: x, y: y).appendingPathComponent("roads/roads.json")
    }

    /// What a tile's road document is seeded from, and the editor's underlay.
    public func seed(z: Int, x: Int, y: Int) -> URL { tile(z: z, x: x, y: y).appendingPathComponent("roads/seed") }

    /// A tile's landmark candidates, a folder each.
    public func tileLandmarks(z: Int, x: Int, y: Int) -> URL { tile(z: z, x: x, y: y).appendingPathComponent("landmarks") }

    /// A built tile's folder.
    public func tileOut(z: Int, x: Int, y: Int) -> URL { tile(z: z, x: x, y: y).appendingPathComponent("build") }

    /// A path given relative to the workspace (or absolute).
    public func resolve(_ path: String) -> URL { URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL }
}
