import CoreGraphics
import Testing
import simd
@testable import ImmersiveMapEditor

/// The cameras keep what is under the pointer under it as they zoom.
@Suite struct CameraTests {
    @Test func theRoadsViewZoomsAboutThePointer() {
        var t = ViewTransform2D(centre: Vec2(100, 50), scale: 2)
        let size = CGSize(width: 800, height: 600), p = CGPoint(x: 120, y: 470)
        let before = t.world(p, in: size)
        t.zoom(by: 3, at: p, in: size)
        let after = t.world(p, in: size)
        #expect(simd_length(before - after) < 1e-9)
        #expect(t.scale == 6)
    }

    @Test func theRoadsViewFramesARectangleWhole() {
        var t = ViewTransform2D()
        let size = CGSize(width: 1000, height: 500)
        t.frame(Vec2(-100, -50), Vec2(100, 50), in: size)
        let (lo, hi) = t.visible(in: size)
        #expect(lo.x <= -100 && hi.x >= 100 && lo.y <= -50 && hi.y >= 50)
    }

    /// Where a ground point lands on the screen, in points from the bottom left.
    func screen(_ camera: OrbitCamera, _ g: SIMD3<Double>, _ size: SIMD2<Double>) -> SIMD2<Double> {
        let c = camera.viewProjection(aspect: size.x / size.y) * SIMD4<Float>(Float(g.x), Float(g.y), Float(g.z), 1)
        return SIMD2(Double(c.x / c.w + 1) / 2 * size.x, Double(c.y / c.w + 1) / 2 * size.y)
    }

    @Test func theTilesViewZoomsTowardTheGroundUnderThePointer() {
        var camera = OrbitCamera()
        let size = SIMD2<Double>(1600, 1000), p = SIMD2<Double>(1200, 300)
        // The ground point under p, found by its screen position: a coarse
        // search, then finer ones around the best.
        var best = SIMD3<Double>.zero
        for step in [10.0, 1, 0.1, 0.01] {
            var found = best, bestD = Double.infinity
            for i in -200...200 {
                for j in -200...200 {
                    let g = best + SIMD3(Double(i) * step, 0, Double(j) * step)
                    let d = simd_length(screen(camera, g, size) - p)
                    if d < bestD { bestD = d; found = g }
                }
            }
            best = found
        }
        #expect(simd_length(screen(camera, best, size) - p) < 0.5)
        camera.zoom(by: 0.5, at: p, size: size)
        #expect(simd_length(screen(camera, best, size) - p) < 0.5)
        #expect(camera.distance == 450)
    }
}
