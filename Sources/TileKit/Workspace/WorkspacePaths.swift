import Foundation

/// Where the build reads and writes: a TilePipeline folder (its workspace)
/// and the hand-made models of Modeling. Passed to whatever reads or writes
/// a file, never kept in a global, so two workspaces can be built side by
/// side and every function says what it touches.
///
///   data/<z>_<x>_<y>/        a tile's raw sources (Fetch)
///   data/regions/<range>/    what a range's road document is seeded from (Seed)
///   roads/                   the road documents, hand-edited
///   landmarks/               recipes, the landmark registry, downloaded models
///   config/                  what OSM shows but the place does not have
///   out/tiles/<z>/<x>/<y>/   the built tiles
///   tools/osm2streets_cli/   the Rust osm2streets, only the oracle of the Streets tests
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

    public var data: URL { root.appendingPathComponent("data") }
    public var roads: URL { root.appendingPathComponent("roads") }
    public var landmarks: URL { root.appendingPathComponent("landmarks") }
    public var config: URL { root.appendingPathComponent("config") }
    public var tilesOut: URL { root.appendingPathComponent("out/tiles") }

    /// A tile's raw sources.
    public func tileData(z: Int, x: Int, y: Int) -> URL { data.appendingPathComponent("\(z)_\(x)_\(y)") }

    /// A built tile's folder.
    public func tileOut(z: Int, x: Int, y: Int) -> URL { tilesOut.appendingPathComponent("\(z)/\(x)/\(y)") }

    /// What a range's road document is seeded from.
    public func region(_ name: String) -> URL { data.appendingPathComponent("regions/\(name)") }

    /// A path given relative to the workspace (or absolute).
    public func resolve(_ path: String) -> URL { URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL }
}
