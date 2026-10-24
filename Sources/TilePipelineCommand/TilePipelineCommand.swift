import Foundation
import TileKit

/// tilepipeline: map tiles into 3D models for the ImmersiveMap engine, from
/// the command line. Works on a TilePipeline folder (data/, roads/,
/// landmarks/, out/): the current folder, or --root.
///
///   tilepipeline build 15 19808 10243                 one tile
///   tilepipeline build 15 19808 10242 19809 10243     a range of tiles
///   tilepipeline build 15 --tiles 19810/10243 ...     any set of tiles
///       [--refetch] [--samples 256]
///   tilepipeline lab data/15_19808_10243 out/style_lab [--region CX CY HALF | --whole] [--export]
///       [--samples 128] [--roads roads/....json]
///   tilepipeline fetch 15 19808 10243 [--force]
///   tilepipeline seed 15 19808 10242 19809 10243 [--force]
///   tilepipeline validate out/tiles/15/19808/10243
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
                var tiles: [(Int, Int)] = []
                if let i = args.list.firstIndex(of: "--tiles") {
                    tiles = args.list[(i + 1)...].compactMap { t in
                        let p = t.split(separator: "/").suffix(2).compactMap { Int($0) }
                        return p.count == 2 ? (p[0], p[1]) : nil
                    }
                    args.list.removeSubrange(i...)
                }
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
            case "lab":
                let whole = args.flag("--whole"), export = args.flag("--export")
                let samples = args.value("--samples").flatMap { Int($0[0]) } ?? 128
                let region = args.value("--region", count: 3).map { v in (Double(v[0])!, Double(v[1])!, Double(v[2])!) }
                let roads = args.value("--roads").map { path($0[0]) }
                guard args.list.count == 2 else { usage() }
                try Build.run(paths, tile: Tile(folder: path(args.list[0])), out: path(args.list[1]), region: region, whole: whole, export: export,
                              samples: samples, roads: roads)
            case "fetch":
                let force = args.flag("--force")
                let n = args.list.compactMap { Int($0) }
                guard n.count == 3 else { usage() }
                try Fetch.tile(paths, z: n[0], x: n[1], y: n[2], force: force)
            case "seed":
                let force = args.flag("--force")
                let n = args.list.compactMap { Int($0) }
                guard n.count == 5 else { usage() }
                _ = try Seed.run(paths, z: n[0], x0: n[1], y0: n[2], x1: n[3], y1: n[4], force: force)
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
               tilepipeline seed Z X0 Y0 X1 Y1 [--force]
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
