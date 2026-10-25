/// A pixel of the snap-rounding grid, a unit square around a grid point
/// (scaled): JTS's `HotPixel`. Segments that cross it are snapped to its
/// centre.
public final class HotPixel {
    static let tolerance = 0.5

    public let coordinate: Coordinate
    public let scaleFactor: Double
    let hpx: Double
    let hpy: Double
    @exclusivity(unchecked) public private(set) var isNode = false

    public init(_ pt: Coordinate, _ scaleFactor: Double) throws {
        // GEOS throws here, where JTS does too: a scale of 0 reaches it from
        // the safe scale of non-finite input.
        if scaleFactor <= 0 { throw IllegalArgumentException("Scale factor must be non-zero") }
        coordinate = pt
        self.scaleFactor = scaleFactor
        if scaleFactor != 1.0 {
            hpx = geosRound(pt.x * scaleFactor)
            hpy = geosRound(pt.y * scaleFactor)
        } else {
            hpx = pt.x
            hpy = pt.y
        }
    }

    public var width: Double { 1.0 / scaleFactor }
    public func setToNode() { isNode = true }

    func scale(_ v: Double) -> Double { v * scaleFactor }

    /// Whether a point is in the pixel (closed on the left and bottom).
    public func intersects(_ p: Coordinate) -> Bool {
        let x = scale(p.x), y = scale(p.y)
        if x >= hpx + HotPixel.tolerance { return false }
        if x < hpx - HotPixel.tolerance { return false }
        if y >= hpy + HotPixel.tolerance { return false }
        if y < hpy - HotPixel.tolerance { return false }
        return true
    }

    /// Whether a segment crosses the pixel.
    public func intersects(_ p0: Coordinate, _ p1: Coordinate) -> Bool {
        if scaleFactor == 1.0 { return intersectsScaled(p0.x, p0.y, p1.x, p1.y) }
        return intersectsScaled(scale(p0.x), scale(p0.y), scale(p1.x), scale(p1.y))
    }

    func intersectsScaled(_ p0x: Double, _ p0y: Double, _ p1x: Double, _ p1y: Double) -> Bool {
        var px = p0x, py = p0y, qx = p1x, qy = p1y
        if px > qx {
            px = p1x
            py = p1y
            qx = p0x
            qy = p0y
        }
        let maxx = hpx + HotPixel.tolerance
        let segMinx = javaMin(px, qx)
        if segMinx >= maxx { return false }
        let minx = hpx - HotPixel.tolerance
        let segMaxx = javaMax(px, qx)
        if segMaxx < minx { return false }
        let maxy = hpy + HotPixel.tolerance
        let segMiny = javaMin(py, qy)
        if segMiny >= maxy { return false }
        let miny = hpy - HotPixel.tolerance
        let segMaxy = javaMax(py, qy)
        if segMaxy < miny { return false }
        if px == qx { return true }
        if py == qy { return true }
        let orientUL = CGAlgorithmsDD.orientationIndex(px, py, qx, qy, minx, maxy)
        if orientUL == 0 { return !(py < qy) }
        let orientUR = CGAlgorithmsDD.orientationIndex(px, py, qx, qy, maxx, maxy)
        if orientUR == 0 { return !(py > qy) }
        if orientUL != orientUR { return true }
        let orientLL = CGAlgorithmsDD.orientationIndex(px, py, qx, qy, minx, miny)
        if orientLL == 0 { return true }
        if orientLL != orientUL { return true }
        let orientLR = CGAlgorithmsDD.orientationIndex(px, py, qx, qy, maxx, miny)
        if orientLR == 0 { return !(py < qy) }
        if orientLL != orientLR { return true }
        if orientLR != orientUR { return true }
        return false
    }
}
