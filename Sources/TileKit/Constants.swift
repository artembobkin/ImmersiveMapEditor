import Foundation

/// The levels and sizes several parts of the build share.
public enum Level {
    /// The roads lie flat this far above the ground plane, so they never
    /// fight the vector tile's ground.
    public static let road = 0.03
    /// What stands on the ground: buildings, shelters, construction sites.
    public static let ground = 0.0
}

/// The kerb band around the roadway.
public let kerbWidth = 0.35

/// A bus shelter: along the kerb, across, high.
public let shelterSize = (4.6, 1.6, 2.5)

/// Its centre behind the kerb's line.
public let shelterBack = kerbWidth + 0.7 + shelterSize.1 / 2

/// The ordinary building's grid, which a landmark's walls fall back to.
public enum Facade {
    public static let floor = 3.4
    public static let bay = 3.2
    /// Wall kept plain at each end of a facade.
    public static let corner = 0.6
    public static let windowWidth = 1.3
    public static let windowHeight = 1.85
}

/// The TilePipeline folder the build reads and writes: data/, roads/,
/// landmarks/, out/. Set by the caller (the editor or the CLI).
nonisolated(unsafe) public var pipelineRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Desktop/TilePipeline")

/// Hand-made models of ~/Desktop/Modeling, read only.
public let modelingRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Modeling")
