import Metal
import simd

/// The built tiles the 3D view shows (`Workspace.shown`), on the GPU, each
/// placed in the projection of the range they span. Read again when the
/// workspace's `tilesRevision` moves.
struct TileLibrary {
    private(set) var tiles: [TileModel] = []
    private var loaded = -1

    func isStale(_ workspace: Workspace) -> Bool { loaded != workspace.tilesRevision }

    /// Reads the tiles shown again and writes the workspace's status line.
    /// Returns whether the set of tiles changed, so the camera frames it.
    mutating func reload(_ workspace: Workspace, device: MTLDevice) -> Bool {
        loaded = workspace.tilesRevision
        let before = Set(tiles.map { "\($0.x)/\($0.y)" })
        guard let region = workspace.shownProjection else {
            tiles = []
            workspace.tileStatus = "No tiles shown: pick them on the Map"
            return !before.isEmpty
        }
        var made: [TileModel] = [], missing: [String] = []
        for t in workspace.shown {
            do {
                made.append(try TileModel.load(device: device, root: workspace.root, z: t.z, x: t.x, y: t.y, region: region))
            } catch {
                missing.append(t.name)
            }
        }
        tiles = made
        let triangles = made.reduce(0) { $0 + $1.triangles }
        workspace.tileStatus = "\(made.count) tiles, \(triangles / 1000)k triangles" +
            (missing.isEmpty ? "" : ". Not built: " + missing.joined(separator: ", "))
        return before != Set(made.map { "\($0.x)/\($0.y)" })
    }

    /// The middle of the tiles in plan (east, north), and the farthest any
    /// tile's centre lies from it.
    var extent: (centre: SIMD2<Double>, reach: Double)? {
        guard !tiles.isEmpty else { return nil }
        let c = tiles.reduce(Vec2.zero) { $0 + $1.centre } / Double(tiles.count)
        return (c, tiles.map { ($0.centre - c).length }.max() ?? 0)
    }
}
