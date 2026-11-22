import Foundation
import TileKit

/// The work of the area's tools (`AreaMCP`) on the data folder: the plan's
/// tiles and their state, a tile prepared (its OSM, its landmarks), and the
/// tiles built and archived for the engine, each step the editor's own:
/// the pipeline's commands run as the editor runs them (`fetch`, `build
/// --changed`, `archive`), the landmarks made by the rules of Make
/// Landmarks… (`LandmarkMaker`). One step on the data folder at a time.
final class Area: @unchecked Sendable {
    let folder: URL
    let paths: WorkspacePaths
    private let lock = NSLock()
    private let buildLock = NSLock()

    init(folder: URL) {
        self.folder = folder
        paths = WorkspacePaths(root: folder.deletingLastPathComponent())
    }

    private var plan: AreaPlan? { try? AreaPlan.read(folder) }

    /// One of the plan's tiles, by "z/x/y".
    func tile(_ name: String) -> TileKey? {
        guard let plan, plan.tiles.contains(name) else { return nil }
        return AreaPlan.key(name)
    }

    /// The plan's tiles in order, a line each.
    func listTiles() -> String {
        guard let plan else { return "No plan: copy the area's prompt from the editor again." }
        let lines = plan.tiles.compactMap { name -> String? in
            guard let t = AreaPlan.key(name) else { return nil }
            let fetched = Osm.isFetched(paths.tileData(z: t.z, x: t.x, y: t.y))
            let landmarks = LandmarkCandidates.list(paths, tile: t)
            let without = landmarks.filter { $0.model == nil && $0.skipped == nil }.count
            return "\(name): " + (fetched ? "OSM" : "no OSM yet") + (plan.prepared.contains(name) ? ", prepared" : ", not prepared")
                + ", \(landmarks.count) landmarks, \(without) without a model"
        }
        let limit = plan.limit == 0 ? "all" : "the \(plan.limit) largest"
        return "\(plan.tiles.count) tiles; each tile's landmarks: \(limit) of \(plan.landmarkKind.title.lowercased()).\n" + lines.joined(separator: "\n")
    }

    /// A tile readied: its OSM cut when it has none, then its landmarks
    /// made as the plan says, once.
    func prepare(_ tile: TileKey) throws -> String {
        try lock.withLock {
            guard var plan else { throw MCPChannel.Failure("no plan: copy the area's prompt from the editor again") }
            var said: [String] = []
            let data = paths.tileData(z: tile.z, x: tile.x, y: tile.y)
            if !Osm.isFetched(data) {
                let (status, output) = pipeline(["fetch", "\(tile.z)", "\(tile.x)", "\(tile.y)"])
                guard status == 0 else { throw MCPChannel.Failure("the OSM of \(tile.name) did not come: " + lastWord(output)) }
                said.append("Its OSM cut from the extracts.")
            }
            if plan.prepared.contains(tile.name) {
                said.append("Prepared before: its landmarks are as they were.")
            } else {
                guard let (projection, buildings) = TileBuildings.read(folder: data) else {
                    throw MCPChannel.Failure("the buildings of \(tile.name) do not read")
                }
                let registry = try Registry(paths)
                _ = registry.sync(paths)
                let streets = TileBuildings.streets(folder: data)
                let maker = LandmarkMaker(paths: paths, tile: tile, projection: projection, buildings: buildings,
                                          held: { registry.landmark(holding: $0) != nil },
                                          nearestStreet: { TileBuildings.nearestStreet(to: $0, in: streets) })
                let made = maker.make(plan.landmarkKind, limit: plan.limit == 0 ? .max : plan.limit)
                _ = registry.sync(paths)
                plan.prepared.append(tile.name)
                try plan.write(folder)
                said.append(made.isEmpty ? "No new landmark: none of its buildings is \(plan.landmarkKind.title.lowercased()) that is not one already."
                                         : "\(made.count) landmarks made: " + made.joined(separator: ", ") + ".")
            }
            return said.joined(separator: " ") + "\n\n" + LandmarkRouter.listLandmarks(in: paths.tileLandmarks(z: tile.z, x: tile.x, y: tile.y))
        }
    }

    /// A tile built with the plan's parts, once its landmarks' models are made
    /// (the user, 2026-11-22). Builds one at a time, beside the preparing:
    /// a tile prepared meanwhile changes nothing of the one built.
    func build(_ tile: TileKey) throws -> String {
        try buildLock.withLock {
            guard let plan else { throw MCPChannel.Failure("no plan: copy the area's prompt from the editor again") }
            guard Osm.isFetched(paths.tileData(z: tile.z, x: tile.x, y: tile.y)) else { throw MCPChannel.Failure("\(tile.name) has no OSM: prepare_tile first") }
            return "\(tile.name): " + (try TileBuild.run(root: paths.root, z: tile.z, tiles: [tile], parts: plan.parts))
        }
    }

    /// Every plan tile with its OSM built where its inputs changed, then
    /// the engine's archive written anew into engine/, the older ones gone
    /// once it is, as the editor's Update the Archive does.
    func updateArchive() throws -> String {
        try lock.withLock {
            guard let plan else { throw MCPChannel.Failure("no plan: copy the area's prompt from the editor again") }
            let tiles = plan.tiles.compactMap(AreaPlan.key).filter { Osm.isFetched(paths.tileData(z: $0.z, x: $0.x, y: $0.y)) }
            var said: [String] = []
            for z in Set(tiles.map(\.z)).sorted() {
                do { said.append(try TileBuild.run(root: paths.root, z: z, tiles: tiles.filter { $0.z == z }, parts: plan.parts)) } catch { said.append("\(error)") }
            }
            let engine = paths.root.appendingPathComponent("engine")
            try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime])
                .replacingOccurrences(of: ":", with: "")
            let out = engine.appendingPathComponent("models-\(stamp).pmtiles")
            let (status, output) = pipeline(["archive", out.path])
            guard status == 0 else { throw MCPChannel.Failure((said + ["the archive was not made: " + lastWord(output)]).joined(separator: "\n")) }
            for old in ((try? FileManager.default.contentsOfDirectory(at: engine, includingPropertiesForKeys: nil)) ?? [])
                where old.pathExtension == "pmtiles" && old.lastPathComponent != out.lastPathComponent {
                try? FileManager.default.removeItem(at: old)
            }
            let archived = output.split(separator: "\n").filter { $0.contains("unchanged since") || $0.hasPrefix("archived") || $0.contains("tiles,") }.suffix(2)
            return (said + ["The engine's archive made anew (\(out.lastPathComponent)): the Engine view shows it."] + archived.map(String.init))
                .joined(separator: "\n")
        }
    }

    private func pipeline(_ arguments: [String]) -> (Int32, String) { TileBuild.pipeline(paths.root, arguments) }
    private func lastWord(_ output: String) -> String { TileBuild.lastWord(output) }
}
