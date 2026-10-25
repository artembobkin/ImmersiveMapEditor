import Foundation
import Geometry
import TileKit

/// Where the views over the open tile look from, one camera for all of them:
/// the ground point in the middle of the view (latitude and longitude, so no
/// view's own metres), how many metres of ground a point of the screen
/// covers there, and the 3D view's heading and tilt. A view takes it when it
/// is shown and gives it back as it moves, so switching views keeps the
/// place in sight. The Roads and Light views look straight down and leave
/// the heading and tilt as the 3D view left them. Opening another tile
/// forgets it: the views frame their new tile.
@MainActor
final class SharedCamera {
    private(set) var latitude: Double?
    private(set) var longitude: Double?
    private(set) var metresPerPoint = 1.0
    var yaw = 20.0
    var pitch = -50.0

    var isSet: Bool { latitude != nil }

    func forget() {
        latitude = nil
        longitude = nil
    }

    /// The middle of the view, in a projection's metres.
    func centre(in p: Projecting) -> Vec2? {
        guard let latitude, let longitude else { return nil }
        let m = p.metres(lat: latitude, lon: longitude)
        return Vec2(m.x, m.y)
    }

    /// Takes a view's middle (in a projection's metres) and scale.
    func set(centre: Vec2, in p: Projecting, metresPerPoint: Double) {
        let (lon, lat) = p.lonLat(P2(centre.x, centre.y))
        latitude = lat
        longitude = lon
        if metresPerPoint.isFinite && metresPerPoint > 0 { self.metresPerPoint = metresPerPoint }
    }

    /// The middle of the view in z`z` tile units (x east, y south), for the
    /// Light view's grid of tiles.
    func tileUnits(z: Int) -> SIMD2<Double>? {
        guard let latitude, let longitude else { return nil }
        let n = pow(2, Double(z)), r = latitude * .pi / 180
        return SIMD2((longitude + 180) / 360 * n, (1 - asinh(tan(r)) / .pi) / 2 * n)
    }

    /// Takes a middle in z`z` tile units and points per tile.
    func set(tileUnits c: SIMD2<Double>, z: Int, pointsPerTile: Double) {
        let n = pow(2, Double(z))
        longitude = c.x / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * c.y / n))) * 180 / .pi
        latitude = lat
        metresPerPoint = Self.tileMetres(z: z, latitude: lat) / max(pointsPerTile, 1e-6)
    }

    /// A z`z` tile's width in metres at a latitude.
    static func tileMetres(z: Int, latitude: Double) -> Double {
        40_075_016.686 * cos(latitude * .pi / 180) / pow(2, Double(z))
    }
}
