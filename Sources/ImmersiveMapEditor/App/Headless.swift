import Foundation
import ImageIO
import SwiftUI
import TileKit

/// What the editor does without a window, for checks from the command line:
/// a road document read and written again, the tiles in 3D or the map
/// rendered to a PNG. nil when the arguments ask for none of these.
@MainActor
enum Headless {
    /// Whether the arguments ask for a run without a window.
    nonisolated static func asked(_ arguments: [String]) -> Bool {
        arguments.contains { ["--resave", "--snapshot", "--map-snapshot", "--landmark-snapshot", "--landmark-views", "--landmark-look", "--street-photos", "--gather-references"].contains($0) }
    }

    static func run(_ arguments: [String]) async -> Int32? {
        func fail(_ message: String) -> Int32 {
            FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
            return 1
        }
        if let i = arguments.firstIndex(of: "--resave"), arguments.count > i + 2 {
            // An unedited document comes out byte for byte the same.
            do {
                let doc = try RoadPlan.read(URL(fileURLWithPath: arguments[i + 1]))
                try doc.write(URL(fileURLWithPath: arguments[i + 2]))
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--snapshot"), arguments.count > i + 3 {
            // A built tile rendered in 3D from above at a slant.
            let workspace = Workspace(root: URL(fileURLWithPath: arguments[i + 1]), remembers: false)
            let p = arguments[i + 3].split(separator: "/").compactMap { Int($0) }
            guard p.count == 2 else { return fail("--snapshot WORKSPACE OUT.png X/Y") }
            workspace.tile = TileKey(z: Workspace.zoom, x: p[0], y: p[1])
            guard let view = TileView(model: workspace) else { return fail("no Metal device") }
            do {
                try view.snapshot(to: URL(fileURLWithPath: arguments[i + 2]), width: 1600, height: 1000)
                print(workspace.tileStatus)
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--gather-references"), arguments.count > i + 1 {
            // Every reference of a landmark gathered, as the editor does
            // before its agent starts: printed.
            let folder = URL(fileURLWithPath: arguments[i + 1]).standardizedFileURL
            if ProcessInfo.processInfo.environment["MAPILLARY_TOKEN"] == nil {
                let token = ClaudeSettings.mapillaryToken
                if !token.isEmpty { setenv("MAPILLARY_TOKEN", token, 1) }
            }
            let server = LandmarkMCP.Server(folder: folder)
            do {
                for item in try server.gather() { if let s = item["text"] as? String { print(s) } }
                return 0
            } catch {
                return fail("\(error)")
            }
        }
        if let i = arguments.firstIndex(of: "--street-photos"), arguments.count > i + 1 {
            // The agent's find_street_photos for a landmark's folder, its
            // report printed (with LANDMARK_STREET_OFFLINE, from the cached
            // coverage tiles alone, no token needed).
            let folder = URL(fileURLWithPath: arguments[i + 1]).standardizedFileURL
            // The token of Settings, as the agent's server gets it.
            if ProcessInfo.processInfo.environment["MAPILLARY_TOKEN"] == nil {
                let token = ClaudeSettings.mapillaryToken
                if !token.isEmpty { setenv("MAPILLARY_TOKEN", token, 1) }
            }
            let server = LandmarkMCP.Server(folder: folder)
            var args: [String: Any] = [:]
            if let r = arguments.firstIndex(of: "--radius"), arguments.count > r + 1, let v = Double(arguments[r + 1]) { args["radius"] = v }
            if let l = arguments.firstIndex(of: "--limit"), arguments.count > l + 1, let v = Int(arguments[l + 1]) { args["limit"] = v }
            do {
                for item in try server.streetPhotos(args) {
                    if let s = item["text"] as? String { print(s) }
                }
                return 0
            } catch {
                return fail("\(error)")
            }
        }
        if let i = arguments.firstIndex(of: "--landmark-snapshot"), arguments.count > i + 2 {
            // One landmark model as the Landmarks view shows it.
            guard let view = LandmarkView.make() else { return fail("no Metal device") }
            do {
                try view.snapshot(URL(fileURLWithPath: arguments[i + 1]), to: URL(fileURLWithPath: arguments[i + 2]),
                                  width: 1200, height: 900)
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--landmark-views"), arguments.count > i + 2 {
            // A landmark's model (its OSM boxes with --boxes) from around and
            // above, a PNG each, into a folder.
            let folder = URL(fileURLWithPath: arguments[i + 1])
            guard let view = LandmarkView.make() else { return fail("no Metal device") }
            let landmark = TileLandmark(id: folder.lastPathComponent, name: "", folder: folder, buildings: [])
            let source: LandmarkView.Source
            if arguments.contains("--boxes") {
                source = .boxes(id: landmark.id, landmark.boxes)
            } else {
                guard let model = landmark.model else { return fail("no model in \(folder.path)") }
                // --lit: as the engine will show it, its light baked here.
                source = arguments.contains("--lit") ? .lit(model, Lighting.Settings()) : .model(model)
            }
            do {
                for url in try view.views(source, to: URL(fileURLWithPath: arguments[i + 2])) { print(url.path) }
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        /// The light settings for --lit from the options --light-mode sky|ao, --light-size N (texels a tile),
        /// --light-samples N, --ao-radius M, --depth D, --gamma G.
        func litSettings() -> Lighting.Settings {
            var s = Lighting.Settings()
            func value(_ name: String) -> String? { arguments.firstIndex(of: name).flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil } }
            if let v = value("--light-mode") { s.mode = v }
            if let v = value("--light-size").flatMap(Int.init) { s.size = v }
            if let v = value("--light-samples").flatMap(Int.init) { s.samples = v }
            if let v = value("--ao-radius").flatMap(Double.init) { s.aoRadius = v }
            if let v = value("--depth").flatMap(Double.init) { s.depth = v }
            if let v = value("--gamma").flatMap(Double.init) { s.gamma = v }
            if let v = value("--face-radius").flatMap(Double.init) { s.faceRadius = v }
            if let v = value("--face-step").flatMap(Double.init) { s.faceStep = v }
            if let v = value("--crease-radius").flatMap(Double.init) { s.creaseRadius = v }
            if let v = value("--crease-depth").flatMap(Double.init) { s.creaseDepth = v }
            return s
        }
        if let i = arguments.firstIndex(of: "--landmark-look"), arguments.count > i + 10 {
            // A landmark's model (its OSM boxes with --boxes) as a photo's
            // camera saw it: FOLDER OUT.png X Y Z HEADING PITCH HFOV W H.
            let folder = URL(fileURLWithPath: arguments[i + 1])
            let n = arguments[(i + 3)...(i + 10)].compactMap(Double.init)
            guard n.count == 8, let view = LandmarkView.make() else { return fail("--landmark-look FOLDER OUT.png X Y Z HEADING PITCH HFOV W H [--boxes]") }
            let landmark = TileLandmark(id: folder.lastPathComponent, name: "", folder: folder, buildings: [])
            let source: LandmarkView.Source
            if arguments.contains("--boxes") || landmark.model == nil {
                source = .boxes(id: landmark.id, landmark.boxes)
            } else {
                source = arguments.contains("--lit") ? .lit(landmark.model!, litSettings()) : .model(landmark.model!)
            }
            do {
                try view.look(source, to: URL(fileURLWithPath: arguments[i + 2]), eye: SIMD3(n[0], n[1], n[2]), heading: n[3], pitch: n[4],
                              hfov: n[5], width: Int(n[6]), height: Int(n[7]))
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--map-snapshot"), arguments.count > i + 2 {
            // The map as it opens, once OpenStreetMap's tiles in view are here.
            let workspace = Workspace(root: URL(fileURLWithPath: arguments[i + 1]), remembers: false)
            let camera = MapCamera(), raster = RasterTiles()
            let size = CGSize(width: 1400, height: 900)
            camera.frame(workspace)
            await raster.prefetch(camera.rasterTiles(in: size))
            let renderer = ImageRenderer(content: MapCanvas(workspace: workspace, camera: camera, raster: raster)
                .frame(width: size.width, height: size.height))
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[i + 2]) as CFURL,
                                                            "public.png" as CFString, 1, nil) else {
                return fail("cannot render the map")
            }
            CGImageDestinationAddImage(out, image, nil)
            return CGImageDestinationFinalize(out) ? 0 : fail("cannot write the PNG")
        }
        return nil
    }
}
