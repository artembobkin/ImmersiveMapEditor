import Foundation
import QuartzCore
import simd

/// The camera's input, without any drawing: orbiting or flying, the keys
/// held in flight and its speed. The view gives it gestures in points (Y up)
/// and asks it for a step every frame.
///
/// Orbit, as the engine: drag to move over the ground, right-drag (or
/// option-drag) to turn and tilt, scroll or pinch to zoom toward the cursor.
/// Flight: W A S D, Q down, E up, shift faster, right-drag to look, scroll
/// for speed.
struct CameraController {
    var camera = OrbitCamera()
    /// Metres a second in flight.
    private(set) var speed = 30.0
    private var keys = Set<Key>()
    private var lastStep = CACurrentMediaTime()

    enum Key: Hashable { case forward, back, left, right, up, down }

    /// Orbit and flight start from different distances: the eye goes close in
    /// flight and back out to orbit.
    mutating func setFlying(_ flying: Bool) {
        camera.distance = flying ? 20 : max(camera.distance, 200)
        keys = []
    }

    /// The defaults key of the app's setting: turning the other way round
    /// (on unless turned off in Settings).
    static let invertTurningKey = "camera.invertTurning"
    static var invertTurning: Bool { UserDefaults.standard.object(forKey: invertTurningKey) as? Bool ?? true }

    mutating func drag(_ dx: Double, _ dy: Double, turning: Bool, size: SIMD2<Double>, flying: Bool) {
        if turning {
            let k = Self.invertTurning ? -1.0 : 1.0
            camera.turn(dx * k, dy * k, size: size, flying: flying)
        } else {
            camera.pan(dx, dy, height: size.y)
        }
    }

    /// The wheel or a trackpad's scroll (up is positive): a zoom toward the
    /// point, or the flight's speed. Returns the speed when it changed.
    mutating func scroll(_ dy: Double, precise: Bool, at p: SIMD2<Double>, size: SIMD2<Double>, flying: Bool) -> Double? {
        if flying {
            speed = min(500, max(2, speed * exp(dy / 50)))
            return speed
        }
        camera.zoom(by: exp(-(precise ? dy / 100 : dy / 10)), at: p, size: size)
        return nil
    }

    mutating func magnify(_ m: Double, at p: SIMD2<Double>, size: SIMD2<Double>) {
        camera.zoom(by: 1 / (1 + m), at: p, size: size)
    }

    mutating func press(_ key: Key) {
        if keys.isEmpty { lastStep = CACurrentMediaTime() }
        keys.insert(key)
    }

    mutating func release(_ key: Key) { keys.remove(key) }

    /// Moves in flight by the keys held, for the time since the last step.
    mutating func step(flying: Bool, fast: Bool) {
        let now = CACurrentMediaTime()
        let dt = min(now - lastStep, 0.1)
        lastStep = now
        guard flying, !keys.isEmpty else { return }
        var move = SIMD3<Double>(0, 0, 0)
        if keys.contains(.forward) { move.z += 1 }
        if keys.contains(.back) { move.z -= 1 }
        if keys.contains(.right) { move.x += 1 }
        if keys.contains(.left) { move.x -= 1 }
        if keys.contains(.up) { move.y += 1 }
        if keys.contains(.down) { move.y -= 1 }
        camera.fly(move, metres: speed * (fast ? 4 : 1) * dt)
    }
}
