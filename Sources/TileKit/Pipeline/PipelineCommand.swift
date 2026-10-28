import Foundation

/// The pipeline's commands, as the editor takes them (`ImmersiveMapEditor
/// pipeline COMMAND ...`, from the terminal or run by the editor itself):
/// map tiles into 3D models for the ImmersiveMap engine. They work on the
/// app's data folder (tiles/<z>/<x>/<y>/ with osm/, roads/ and build/, then
/// landmarks/ and config/; WorkspacePaths): the current folder, or --root.
///
///   pipeline build 15 19808 10243                 one tile
///   pipeline build 15 19808 10242 19809 10243     a range of tiles
///   pipeline build 15 --tiles 19810/10243 ...     any set of tiles
///       [--refetch] [--samples 256] [--no-light]   (the light baked later: bake)
///   pipeline lab data/15_19808_10243 out/style_lab [--region CX CY HALF | --whole] [--export]
///       [--samples 128] [--roads roads/....json]
///   pipeline fetch 15 19808 10243 [--force]
///   pipeline seed 15 19808 10243 [--force]           a tile's road document
///   pipeline migrate ~/Desktop/TilePipeline       an older workspace, copied in
///   pipeline bake 15 --tiles 19808/10243 ...      the light of built tiles again
///       [--size 1024] [--samples 256] [--bounces 3] [--gamma 1.6] [--lit R G B] [--shade R G B]
///       [--mode sky|ao] [--ao-radius 8] [--sky 1] [--sun AZIMUTH ELEVATION STRENGTH | --no-sun]
///   pipeline validate tiles/15/19808/10243/build
///   pipeline fit detsky-mir
///
/// One app, one binary: the editor runs these in a process of itself, so the
/// pipeline is never another build than the editor.
public enum PipelineCommand {
    /// Runs one command and ends the process with its status.
    public static func run(_ arguments: [String]) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        var args = Arguments(arguments)
        let paths = WorkspacePaths(root: URL(fileURLWithPath: args.value("--root")?[0] ?? FileManager.default.currentDirectoryPath))
        Palette.load(paths)
        func path(_ p: String) -> URL { paths.resolve(p) }
        do {
            guard let command = args.next() else { usage() }
            switch command {
            case "build":
                var options = Pipeline.Options()
                options.refetch = args.flag("--refetch")
                options.bakeLight = !args.flag("--no-light")
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
                let bounces = number("--bounces").map(Int.init), gamma = number("--gamma"), depth = number("--depth")
                let faceRadius = number("--face-radius"), faceStep = number("--face-step")
                let lit = colour("--lit"), shade = colour("--shade")
                let mode = args.value("--mode")?[0], aoRadius = number("--ao-radius"), sky = number("--sky")
                let noSun = args.flag("--no-sun")
                let sun = args.value("--sun", count: 3).map { $0.compactMap(Double.init) }.flatMap { $0.count == 3 ? $0 : nil }
                let tiles = args.tiles()
                guard let z = args.list.first.flatMap({ Int($0) }), args.list.count == 1, !tiles.isEmpty else { usage() }
                exit(Bake.run(paths, z: z, tiles: tiles) { s in
                    if let v = size { s.size = v }
                    if let v = samples { s.samples = v }
                    if let v = bounces { s.bounces = v }
                    if let v = gamma { s.gamma = v }
                    if let v = depth { s.depth = v }
                    if let v = faceRadius { s.faceRadius = v }
                    if let v = faceStep { s.faceStep = v }
                    if let v = lit { s.lit = v }
                    if let v = shade { s.shade = v }
                    if let v = mode { s.mode = v }
                    if let v = aoRadius { s.aoRadius = v }
                    if let v = sky { s.skyStrength = v }
                    if noSun { s.sun = false }
                    if let v = sun { (s.sun, s.sunAzimuth, s.sunElevation, s.sunStrength) = (true, v[0], v[1], v[2]) }
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
            case "landmark":
                // A landmark's model from its recipe (a starter recipe from
                // OSM first when it has none, or when asked).
                guard let f = args.list.first else { usage() }
                let folder = path(f)
                let recipe = folder.appendingPathComponent("recipe.json")
                if args.flag("--starter") || !FileManager.default.fileExists(atPath: recipe.path) {
                    try LandmarkSource(folder.appendingPathComponent("landmark.json")).starterRecipe().write(recipe)
                    print("[landmark] a starter recipe from OSM: \(recipe.lastPathComponent)")
                }
                let (problems, summary) = try LandmarkGenerator.run(folder: folder)
                for p in problems { print("problem: \(p)") }
                guard problems.isEmpty else { exit(1) }
                print("[landmark] model.glb: \(summary)")
            default:
                usage()
            }
        } catch {
            FileHandle.standardError.write("pipeline: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        exit(0)
    }

    static func usage() -> Never {
        FileHandle.standardError.write("""
        usage: ImmersiveMapEditor pipeline [--root FOLDER] build Z X Y | Z X0 Y0 X1 Y1 | Z --tiles X/Y... [--refetch] [--samples N] [--no-light]
               ImmersiveMapEditor pipeline lab DATA OUT [--region CX CY HALF | --whole] [--export] [--samples N] [--roads FILE]
               ImmersiveMapEditor pipeline fetch Z X Y [--force]
               ImmersiveMapEditor pipeline seed Z X Y [--force]
               ImmersiveMapEditor pipeline migrate OLD_WORKSPACE
               ImmersiveMapEditor pipeline bake Z --tiles X/Y... [--size N] [--samples N] [--bounces N] [--gamma G] [--lit R G B] [--shade R G B]
                   [--mode sky|ao] [--ao-radius M] [--sky S] [--sun AZ EL S | --no-sun]
               ImmersiveMapEditor pipeline validate FOLDER
               ImmersiveMapEditor pipeline landmark LANDMARK_FOLDER [--starter]
               ImmersiveMapEditor pipeline fit ID

        """.data(using: .utf8)!)
        exit(2)
    }
}

/// The command's arguments, taken off as they are read: flags, options with
/// their values, then what is left in order.
private struct Arguments {
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
