import Foundation
import Geometry

/// The projections of the build: local metres, X east and Y north from a
/// Mercator centre, at the Mercator scale of that latitude, the way the
/// engine's baker places a model (TilePipeline's CLAUDE.md, "Fitting the
/// engine"). A `Tile` projects around its own centre, a `Region` (a range
/// of tiles) around the range's.

public let tileExtent = 4096.0
public let earthCircumference = 40075016.686

public func latitudeOfRow(_ row: Double, _ z: Int) -> Double {
    atan(sinh(.pi * (1 - 2 * row / pow(2, Double(z))))) * 180 / .pi
}

/// Longitude and latitude of a point in global tile units at zoom z.
public func mercatorLonLat(_ z: Int, _ gx: Double, _ gy: Double) -> (Double, Double) {
    let n = pow(2, Double(z)) * tileExtent
    return (gx / n * 360 - 180, atan(sinh(.pi * (1 - 2 * gy / n))) * 180 / .pi)
}

/// Anything that turns latitude and longitude into local metres and back.
public protocol Projecting {
    var z: Int { get }
    var folder: URL { get }
    func metres(lat: Double, lon: Double) -> P2
    func lonLat(_ p: P2) -> (Double, Double)
}

/// A fetched tile (data/<z>_<x>_<y>/tile.json): its projection around its
/// own Mercator centre.
public final class Tile: Projecting {
    public let z, x, y: Int
    public let unitsPerMetre: Double
    public let size: Double
    public let folder: URL
    public let info: [String: Any]

    public init(folder: URL) throws {
        let data = try Data(contentsOf: folder.appendingPathComponent("tile.json"))
        info = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let t = info["tile"] as? [String: Int] ?? [:]
        z = t["z"] ?? 15
        x = t["x"] ?? 0
        y = t["y"] ?? 0
        unitsPerMetre = info["units_per_metre"] as? Double ?? 1
        size = info["size_m"] as? Double ?? 0
        self.folder = folder
    }

    public var centreLatitude: Double { ((info["centre"] as? [String: Double]) ?? [:])["latitude"] ?? 0 }
    public var centreLongitude: Double { ((info["centre"] as? [String: Double]) ?? [:])["longitude"] ?? 0 }

    public func metres(lat: Double, lon: Double) -> P2 {
        let n = pow(2, Double(z)) * tileExtent
        let mx = (lon + 180) / 360 * n - Double(x) * tileExtent
        let my = (1 - asinh(tan(lat * .pi / 180)) / .pi) / 2 * n - Double(y) * tileExtent
        return P2((mx - tileExtent / 2) / unitsPerMetre, (tileExtent / 2 - my) / unitsPerMetre)
    }

    public func lonLat(_ p: P2) -> (Double, Double) {
        mercatorLonLat(z, Double(x) * tileExtent + tileExtent / 2 + p.x * unitsPerMetre,
                       Double(y) * tileExtent + tileExtent / 2 - p.y * unitsPerMetre)
    }

    public var bounds: Geometry {
        let h = size / 2
        return .box(-h, -h, h, h)
    }
}

/// A range of tiles projected as one: local metres around the range's
/// Mercator centre, at the Mercator scale of that latitude.
public final class Region: Projecting {
    public let z, x0, y0, x1, y1: Int
    public var folder: URL
    public let gx, gy, unitsPerMetre: Double

    public init(z: Int, x0: Int, y0: Int, x1: Int, y1: Int, folder: URL = URL(fileURLWithPath: "/")) {
        self.z = z
        self.x0 = min(x0, x1); self.x1 = max(x0, x1)
        self.y0 = min(y0, y1); self.y1 = max(y0, y1)
        self.folder = folder
        gx = Double(self.x0 + self.x1 + 1) / 2 * tileExtent
        gy = Double(self.y0 + self.y1 + 1) / 2 * tileExtent
        let lat = latitudeOfRow(Double(self.y0 + self.y1 + 1) / 2, z)
        unitsPerMetre = tileExtent * pow(2, Double(z)) / (earthCircumference * cos(lat * .pi / 180))
    }

    public var name: String { "\(z)_\(x0)_\(y0)_\(x1)_\(y1)" }

    public var tiles: [(Int, Int)] { (y0...y1).flatMap { y in (x0...x1).map { ($0, y) } } }

    public func metres(lat: Double, lon: Double) -> P2 {
        let n = pow(2, Double(z)) * tileExtent
        let mx = (lon + 180) / 360 * n
        let my = (1 - asinh(tan(lat * .pi / 180)) / .pi) / 2 * n
        return P2((mx - gx) / unitsPerMetre, (gy - my) / unitsPerMetre)
    }

    public func lonLat(_ p: P2) -> (Double, Double) {
        mercatorLonLat(z, gx + p.x * unitsPerMetre, gy - p.y * unitsPerMetre)
    }

    /// One tile's edges in the range's metres: its south-west and north-east
    /// corners.
    public func tileRect(x: Int, y: Int) -> (P2, P2) {
        let u = unitsPerMetre
        return (P2((Double(x) * tileExtent - gx) / u, (gy - Double(y + 1) * tileExtent) / u),
                P2((Double(x + 1) * tileExtent - gx) / u, (gy - Double(y) * tileExtent) / u))
    }

    public var bounds: Geometry {
        let u = unitsPerMetre
        return .box((Double(x0) * tileExtent - gx) / u, (gy - Double(y1 + 1) * tileExtent) / u,
                    (Double(x1 + 1) * tileExtent - gx) / u, (gy - Double(y0) * tileExtent) / u)
    }
}
