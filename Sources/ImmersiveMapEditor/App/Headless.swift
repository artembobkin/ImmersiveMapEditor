import Foundation
import ImageIO
import SwiftUI

/// What the editor does without a window, for checks from the command line:
/// a road document read and written again, the tiles in 3D or the map
/// rendered to a PNG. nil when the arguments ask for none of these.
@MainActor
enum Headless {
    /// Whether the arguments ask for a run without a window.
    nonisolated static func asked(_ arguments: [String]) -> Bool {
        arguments.contains { ["--resave", "--snapshot", "--map-snapshot", "--landmark-snapshot", "--landmark-views", "--landmark-look", "--erase-people"].contains($0) }
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
            let landmark = TileLandmark(id: folder.lastPathComponent, name: "", folder: folder, buildings: [], detail: "normal")
            let source: LandmarkView.Source
            if arguments.contains("--boxes") {
                source = .boxes(id: landmark.id, landmark.boxes)
            } else {
                guard let model = landmark.model else { return fail("no model in \(folder.path)") }
                source = .model(model)
            }
            do {
                for url in try view.views(source, to: URL(fileURLWithPath: arguments[i + 2])) { print(url.path) }
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--landmark-look"), arguments.count > i + 10 {
            // A landmark's model (its OSM boxes with --boxes) as a photo's
            // camera saw it: FOLDER OUT.png X Y Z HEADING PITCH HFOV W H.
            let folder = URL(fileURLWithPath: arguments[i + 1])
            let n = arguments[(i + 3)...(i + 10)].compactMap(Double.init)
            guard n.count == 8, let view = LandmarkView.make() else { return fail("--landmark-look FOLDER OUT.png X Y Z HEADING PITCH HFOV W H [--boxes]") }
            let landmark = TileLandmark(id: folder.lastPathComponent, name: "", folder: folder, buildings: [], detail: "normal")
            let source: LandmarkView.Source
            if arguments.contains("--boxes") || landmark.model == nil {
                source = .boxes(id: landmark.id, landmark.boxes)
            } else {
                source = .model(landmark.model!)
            }
            do {
                try view.look(source, to: URL(fileURLWithPath: arguments[i + 2]), eye: SIMD3(n[0], n[1], n[2]), heading: n[3], pitch: n[4],
                              hfov: n[5], width: Int(n[6]), height: Int(n[7]))
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--erase-people"), arguments.count > i + 2 {
            // A photo's people and traffic painted black, to check the models.
            Segmenter.folder = DataFolder.current.appendingPathComponent("config/models")
            let out = URL(fileURLWithPath: arguments[i + 2])
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: arguments[i + 1]), to: out)
            print(PeopleMask.erase(out) ? "people painted" : "no people found")
            return 0
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
