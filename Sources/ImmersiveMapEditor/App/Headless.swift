import Foundation
import ImageIO
import SwiftUI

/// What the editor does without a window, for checks from the command line:
/// a road document read and written again, the tiles in 3D or the map
/// rendered to a PNG. nil when the arguments ask for none of these.
@MainActor
enum Headless {
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
            // Built tiles rendered together in 3D from above at a slant.
            let workspace = Workspace(root: URL(fileURLWithPath: arguments[i + 1]))
            workspace.shown = arguments[(i + 3)...].compactMap { t in
                let p = t.split(separator: "/").compactMap { Int($0) }
                return p.count == 2 ? TileKey(z: Workspace.zoom, x: p[0], y: p[1]) : nil
            }
            guard let view = TileView(model: workspace) else { return fail("no Metal device") }
            do {
                try view.snapshot(to: URL(fileURLWithPath: arguments[i + 2]), width: 1600, height: 1000)
                print(workspace.tileStatus)
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        }
        if let i = arguments.firstIndex(of: "--map-snapshot"), arguments.count > i + 2 {
            // The map as it opens, once OpenStreetMap's tiles in view are here.
            let workspace = Workspace(root: URL(fileURLWithPath: arguments[i + 1]))
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
