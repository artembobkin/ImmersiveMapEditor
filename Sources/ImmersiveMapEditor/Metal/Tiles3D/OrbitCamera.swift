import simd

/// The 3D view's camera, pure geometry: a target on or over the ground, the
/// distance to it and the way it looks (yaw, pitch). World axes as the
/// tiles': X east, Y up, -Z north. Every move here works as the engine's
/// camera does (MapGestureControllerMac), so the two feel alike.
struct OrbitCamera: Equatable {
    var target = SIMD3<Double>(0, 0, 0)
    var distance = 900.0
    /// Degrees from north, clockwise.
    var yaw = 20.0
    /// Degrees, down is negative.
    var pitch = -45.0

    /// The half of the vertical field of view, in radians.
    static let halfFov = 25.0 * .pi / 180

    var forward: SIMD3<Double> {
        let p = pitch * .pi / 180, y = yaw * .pi / 180
        return SIMD3(cos(p) * sin(y), sin(p), -cos(p) * cos(y))
    }

    var eye: SIMD3<Double> { target - forward * distance }

    private var right: SIMD3<Double> { simd_normalize(simd_cross(forward, SIMD3(0, 1, 0))) }

    /// The view and projection in one, for a view of `aspect` (width over
    /// height). Near and far follow the height, so the street and the whole
    /// block both keep their depth.
    func viewProjection(aspect: Double) -> simd_float4x4 {
        let f = forward, e = eye, r = right
        let up = simd_cross(r, f)
        let view = simd_double4x4(rows: [
            SIMD4(r.x, r.y, r.z, -simd_dot(r, e)),
            SIMD4(up.x, up.y, up.z, -simd_dot(up, e)),
            SIMD4(-f.x, -f.y, -f.z, simd_dot(f, e)),
            SIMD4(0, 0, 0, 1),
        ])
        let near = max(0.1, min(5, max(e.y, 1) * 0.02)), far = max(20000, distance * 10)
        let ys = 1 / tan(Self.halfFov), xs = ys / aspect, zs = far / (near - far)
        let projection = simd_double4x4(rows: [
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, zs * near),
            SIMD4(0, 0, -1, 0),
        ])
        let m = projection * view
        return simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                       SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }

    /// Over a group of tiles: their centre (in plan, east and north) and how
    /// far they reach, looking down at a slant.
    mutating func frame(centre: SIMD2<Double>, span: Double) {
        target = SIMD3(centre.x, 0, -centre.y)
        distance = span * 1.1
        pitch = -50
        yaw = 20
    }

    /// Moves the target over the ground by screen points, the ground
    /// following the mouse, in a view `height` points high.
    mutating func pan(_ dx: Double, _ dy: Double, height: Double) {
        let metresPerPoint = distance * tan(Self.halfFov) * 2 / max(height, 1)
        let y = yaw * .pi / 180
        let r = SIMD3(cos(y), 0, sin(y)), ahead = SIMD3(sin(y), 0, -cos(y))
        target -= (r * dx + ahead * dy) * metresPerPoint
    }

    /// Turns as the engine does: across the whole width is half a turn, down
    /// the whole height tilts twice the pitch range (the engine's
    /// `tiltGestureSensitivity` 2), dragging down tilts toward the horizon.
    /// In flight it looks around from the eye, which stays where it is.
    mutating func turn(_ dx: Double, _ dy: Double, size: SIMD2<Double>, flying: Bool) {
        let w = max(size.x, 1), h = max(size.y, 1)
        let e = eye
        yaw += dx / w * 180
        if flying {
            pitch = min(89, max(-89, pitch - dy / h * 2 * 88))
            target = e + forward * distance
        } else {
            pitch = min(-2, max(-89, pitch - dy / h * 2 * 87))
        }
    }

    /// Zooms by `factor` toward the ground under a point of the view (Y up),
    /// as the engine does: the camera comes closer along the way to that
    /// point, which stays under the cursor. Off the ground, toward the target.
    mutating func zoom(by factor: Double, at p: SIMD2<Double>, size: SIMD2<Double>) {
        let k = min(20000, max(5, distance * factor)) / distance
        let w = max(size.x, 1), h = max(size.y, 1)
        let f = forward, r = right
        let up = simd_cross(r, f)
        let t = tan(Self.halfFov)
        let ray = f + r * ((p.x / w * 2 - 1) * t * w / h) + up * ((p.y / h * 2 - 1) * t)
        let e = eye
        if ray.y < -1e-3 {
            let ground = e + ray * (-e.y / ray.y)
            target = ground + (target - ground) * k
        }
        distance *= k
    }

    /// Moves eye and target together: `move` in the camera's own axes
    /// (x right, y up the world, z ahead), `metres` long.
    mutating func fly(_ move: SIMD3<Double>, metres: Double) {
        let d = right * move.x + SIMD3(0, move.y, 0) + forward * move.z
        guard simd_length(d) > 0 else { return }
        target += simd_normalize(d) * metres
    }
}
