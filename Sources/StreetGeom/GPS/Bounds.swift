/// geom's `Bounds` (a box in world space) and `GPSBounds` (a box of
/// longitudes and latitudes, the frame that maps them to metres).

/// Rust's `f64::min` and `f64::max`: a NaN argument yields the other one.
@inlinable func rustMin(_ a: Double, _ b: Double) -> Double { Double.minimum(a, b) }
@inlinable func rustMax(_ a: Double, _ b: Double) -> Double { Double.maximum(a, b) }

public struct Bounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    /// A boundary including no points.
    public init() {
        minX = Double.greatestFiniteMagnitude
        minY = Double.greatestFiniteMagnitude
        maxX = -Double.greatestFiniteMagnitude
        maxY = -Double.greatestFiniteMagnitude
    }

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public static func from(_ pts: [Pt2D]) -> Bounds {
        var b = Bounds()
        for pt in pts { b.update(pt) }
        return b
    }

    public static func fromPolygons(_ polygons: [Polygon]) -> Bounds {
        var b = Bounds()
        for poly in polygons {
            for ring in poly.rings {
                for pt in ring.points { b.update(pt) }
            }
        }
        return b
    }

    public mutating func update(_ pt: Pt2D) {
        minX = rustMin(minX, pt.x)
        maxX = rustMax(maxX, pt.x)
        minY = rustMin(minY, pt.y)
        maxY = rustMax(maxY, pt.y)
    }

    public mutating func union(_ other: Bounds) {
        update(Pt2D(other.minX, other.minY))
        update(Pt2D(other.maxX, other.maxY))
    }

    public mutating func addBuffer(_ sides: Distance) {
        minX -= sides.innerMeters
        maxX += sides.innerMeters
        minY -= sides.innerMeters
        maxY += sides.innerMeters
    }

    public func contains(_ pt: Pt2D) -> Bool {
        pt.x >= minX && pt.x <= maxX && pt.y >= minY && pt.y <= maxY
    }

    public func getRectangle() -> Polygon {
        Ring.mustNew([
            Pt2D(minX, minY), Pt2D(maxX, minY), Pt2D(maxX, maxY), Pt2D(minX, maxY), Pt2D(minX, minY),
        ]).intoPolygon()
    }

    public func width() -> Double { maxX - minX }
    public func height() -> Double { maxY - minY }

    public func center() -> Pt2D { Pt2D(minX + width() / 2.0, minY + height() / 2.0) }
}

/// A box of longitudes and latitudes. World space puts its top-left at the
/// origin and grows right and down, in metres.
public struct GPSBounds: Equatable, Sendable {
    public var minLon: Double
    public var minLat: Double
    public var maxLon: Double
    public var maxLat: Double

    /// A boundary including no points.
    public init() {
        minLon = Double.greatestFiniteMagnitude
        minLat = Double.greatestFiniteMagnitude
        maxLon = -Double.greatestFiniteMagnitude
        maxLat = -Double.greatestFiniteMagnitude
    }

    public static func from(_ pts: [LonLat]) -> GPSBounds {
        var b = GPSBounds()
        for pt in pts { b.update(pt) }
        return b
    }

    public mutating func update(_ pt: LonLat) {
        minLon = rustMin(minLon, pt.x)
        maxLon = rustMax(maxLon, pt.x)
        minLat = rustMin(minLat, pt.y)
        maxLat = rustMax(maxLat, pt.y)
    }

    public func contains(_ pt: LonLat) -> Bool {
        pt.x >= minLon && pt.x <= maxLon && pt.y >= minLat && pt.y <= maxLat
    }

    /// The bottom-right corner in world space.
    public func getMaxWorldPt() -> Pt2D {
        let width = LonLat(minLon, minLat).gpsDist(LonLat(maxLon, minLat))
        let height = LonLat(minLon, minLat).gpsDist(LonLat(minLon, maxLat))
        return Pt2D(width.innerMeters, height.innerMeters)
    }

    public func toBounds() -> Bounds {
        var b = Bounds()
        b.update(Pt2D(0.0, 0.0))
        b.update(getMaxWorldPt())
        return b
    }

    public func tryConvert(_ pts: [LonLat]) -> [Pt2D]? {
        var result: [Pt2D] = []
        for gps in pts {
            if !contains(gps) { return nil }
            result.append(gps.toPt(self))
        }
        return result
    }

    public func convert(_ pts: [LonLat]) -> [Pt2D] { pts.map { $0.toPt(self) } }

    public func convertBack(_ pts: [Pt2D]) -> [LonLat] { pts.map { $0.toGPS(self) } }

    public func convertBackXY(_ x: Double, _ y: Double) -> LonLat {
        let max = getMaxWorldPt()
        let width = max.x
        let height = max.y
        let lon = (x / width * (maxLon - minLon)) + minLon
        let lat = minLat + ((maxLat - minLat) * (height - y) / height)
        return LonLat(lon, lat)
    }

    public func getRectangle() -> [LonLat] {
        [LonLat(minLon, minLat), LonLat(maxLon, minLat), LonLat(maxLon, maxLat), LonLat(minLon, maxLat),
         LonLat(minLon, minLat)]
    }
}
