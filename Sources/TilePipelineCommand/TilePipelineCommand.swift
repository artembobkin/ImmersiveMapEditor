import Foundation
import TileKit

/// tilepipeline: map tiles into 3D models for the ImmersiveMap engine, from
/// the command line. Works on the app's data folder (tiles/<z>/<x>/<y>/ with
/// osm/, roads/ and build/, then landmarks/ and config/; WorkspacePaths):
/// the current folder, or --root.
///
///   tilepipeline build 15 19808 10243                 one tile
///   tilepipeline build 15 19808 10242 19809 10243     a range of tiles
///   tilepipeline build 15 --tiles 19810/10243 ...     any set of tiles
///       [--refetch] [--samples 256]
///   tilepipeline lab data/15_19808_10243 out/style_lab [--region CX CY HALF | --whole] [--export]
///       [--samples 128] [--roads roads/....json]
///   tilepipeline fetch 15 19808 10243 [--force]
///   tilepipeline seed 15 19808 10243 [--force]           a tile's road document
///   tilepipeline migrate ~/Desktop/TilePipeline       an older workspace, copied in
///   tilepipeline bake 15 --tiles 19808/10243 ...      the light of built tiles again
///       [--size 1024] [--samples 256] [--bounces 3] [--gamma 1.6] [--lit R G B] [--shade R G B]
///   tilepipeline validate tiles/15/19808/10243/build
///   tilepipeline fit detsky-mir
@main
enum TilePipelineCommand {
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        var args = Arguments(Array(CommandLine.arguments.dropFirst()))
        let paths = WorkspacePaths(root: URL(fileURLWithPath: args.value("--root")?[0] ?? FileManager.default.currentDirectoryPath))
        func path(_ p: String) -> URL { paths.resolve(p) }
        do {
            guard let command = args.next() else { usage() }
            switch command {
            case "build":
                var options = Pipeline.Options()
                options.refetch = args.flag("--refetch")
                if let s = args.value("--samples"), let n = Int(s[0]) { options.samples = n }
                var tiles = args.tiles()
                let n = args.list.compactMap { Int($0) }
                guard let z = n.first else { usage() }
                if tiles.isEmpty {
                    if n.count == 3 {
                        tiles = [(n[1], n[2])]
                    } else if n.count == 5 {
                        tiles = (min(n[2], n[4])...max(n[2], n[4])).flatMap { y in (min(n[1], n[3])...max(n[1], n[3])).map { ($0, y) } }
                    } else {
                        usage()
                    }
                }
                exit(try Pipeline.run(paths, z: z, tiles: tiles, options: options) ? 0 : 1)
            case "bake":
                func number(_ name: String) -> Double? { args.value(name).flatMap { Double($0[0]) } }
                func colour(_ name: String) -> [Double]? {
                    args.value(name, count: 3).map { $0.compactMap(Double.init) }.flatMap { $0.count == 3 ? $0 : nil }
                }
                let size = number("--size").map(Int.init), samples = number("--samples").map(Int.init)
                let bounces = number("--bounces").map(Int.init), gamma = number("--gamma")
                let lit = colour("--lit"), shade = colour("--shade")
                let tiles = args.tiles()
                guard let z = args.list.first.flatMap({ Int($0) }), args.list.count == 1, !tiles.isEmpty else { usage() }
                exit(Bake.run(paths, z: z, tiles: tiles) { s in
                    if let v = size { s.size = v }
                    if let v = samples { s.samples = v }
                    if let v = bounces { s.bounces = v }
                    if let v = gamma { s.gamma = v }
                    if let v = lit { s.lit = v }
                    if let v = shade { s.shade = v }
                } ? 0 : 1)
            case "lab":
                let whole = args.flag("--whole"), export = args.flag("--export")
                var light = Lighting.Settings()
                light.samples = args.value("--samples").flatMap { Int($0[0]) } ?? 128
                let region = args.value("--region", count: 3).map { v in (Double(v[0])!, Double(v[1])!, Double(v[2])!) }
                let roads = args.value("--roads").map { path($0[0]) }
                guard args.list.count == 2 else { usage() }
                try Build.run(paths, tile: Tile(folder: path(args.list[0])), out: path(args.list[1]), region: region, whole: whole, export: export,
                              light: light, roads: roads)
            case "fetch":
                let force = args.flag("--force")
                let n = args.list.compactMap { Int($0) }
                guard n.count == 3 else { usage() }
                try Fetch.tile(paths, z: n[0], x: n[1], y: n[2], force: force)
            case "seed":
                let force = args.flag("--force")
                let n = args.list.compactMap { Int($0) }
                guard n.count == 3 else { usage() }
                _ = try Seed.run(paths, z: n[0], x: n[1], y: n[2], force: force)
            case "interface":
                // The editor's check that this pipeline is its own.
                print(PipelineInterface.version)
            case "migrate":
                guard let from = args.list.first else { usage() }
                try Migration.run(from: URL(fileURLWithPath: (from as NSString).expandingTildeInPath), to: paths)
            case "validate":
                guard let f = args.list.first else { usage() }
                let r = try Validate.tile(path(f))
                for c in r.checks { print((c.ok ? "ok    " : "FAIL  ") + c.name + (c.detail.isEmpty ? "" : "  (\(c.detail))")) }
                print(String(format: "%@: %d triangles, %.1f MB, %@", r.model, r.triangles, Double(r.bytes) / 1e6, r.ok ? "valid" : "INVALID"))
                exit(r.ok ? 0 : 1)
            case "fit":
                guard let id = args.list.first else { usage() }
                try Fit.run(id, paths)
            default:
                usage()
            }
        } catch {
            FileHandle.standardError.write("tilepipeline: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func usage() -> Never {
        FileHandle.standardError.write("""
        usage: tilepipeline [--root FOLDER] build Z X Y | Z X0 Y0 X1 Y1 | Z --tiles X/Y... [--refetch] [--samples N]
               tilepipeline lab DATA OUT [--region CX CY HALF | --whole] [--export] [--samples N] [--roads FILE]
               tilepipeline fetch Z X Y [--force]
               tilepipeline seed Z X Y [--force]
               tilepipeline migrate OLD_WORKSPACE
               tilepipeline bake Z --tiles X/Y... [--size N] [--samples N] [--bounces N] [--gamma G] [--lit R G B] [--shade R G B]
               tilepipeline validate FOLDER
               tilepipeline fit ID

        """.data(using: .utf8)!)
        exit(2)
    }
}

/// The command's arguments, taken off as they are read: flags, options with
/// their values, then what is left in order.
struct Arguments {
    var list: [String]

    init(_ list: [String]) { self.list = list }

    mutating func next() -> String? { list.isEmpty ? nil : list.removeFirst() }

    /// The tiles after --tiles, as X/Y (or Z/X/Y), to the end (and takes them off).
    mutating func tiles() -> [(Int, Int)] {
        guard let i = list.firstIndex(of: "--tiles") else { return [] }
        let tiles: [(Int, Int)] = list[(i + 1)...].compactMap { t in
            let p = t.split(separator: "/").suffix(2).compactMap { Int($0) }
            return p.count == 2 ? (p[0], p[1]) : nil
        }
        list.removeSubrange(i...)
        return tiles
    }

    /// Whether a flag is given (and takes it off).
    mutating func flag(_ name: String) -> Bool {
        guard let i = list.firstIndex(of: name) else { return false }
        list.remove(at: i)
        return true
    }

    /// The values after an option (and takes them off), nil without it.
    mutating func value(_ name: String, count: Int = 1) -> [String]? {
        guard let i = list.firstIndex(of: name), list.count > i + count else { return nil }
        let v = Array(list[(i + 1)...(i + count)])
        list.removeSubrange(i...(i + count))
        return v
    }
}
