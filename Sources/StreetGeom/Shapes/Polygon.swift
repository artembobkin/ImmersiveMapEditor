/// geom's `Polygon`: an outer ring and holes, with an optional tessellation
/// computed together with the rings. Operations backed by geo are in
/// `PolygonGeo.swift`.

public struct Polygon: Equatable, Sendable, CustomStringConvertible {
    /// [0] is the exterior, the others are holes.
    public internal(set) var rings: [Ring]
    /// Some callers make the rings and the tessellation at the same time.
    public internal(set) var tessellation: Tessellation?

    public static func withHoles(_ outer: Ring, _ inner: [Ring]) -> Polygon {
        Polygon(rings: [outer] + inner, tessellation: nil)
    }

    public static func fromRings(_ rings: [Ring]) -> Polygon {
        precondition(!rings.isEmpty)
        return Polygon(rings: rings, tessellation: nil)
    }

    static func pretessellated(_ rings: [Ring], _ tessellation: Tessellation) -> Polygon {
        Polygon(rings: rings, tessellation: tessellation)
    }

    public static func fromTriangle(_ tri: Triangle) -> Polygon {
        Ring.mustNew([tri.pt1, tri.pt2, tri.pt3, tri.pt1]).intoPolygon()
    }

    public func triangles() -> [Triangle] { Tessellation.from(self).triangles() }

    public func getBounds() -> Bounds { .from(getOuterRing().points) }

    /// Transformations must preserve rings.
    func transform(_ f: (Pt2D) -> Pt2D) throws -> Polygon {
        var rings: [Ring] = []
        for ring in self.rings { rings.append(try Ring.new(ring.points.map(f))) }
        var t = tessellation
        if t != nil { t!.points = t!.points.map(f) }
        return Polygon(rings: rings, tessellation: t)
    }

    public func translate(_ dx: Double, _ dy: Double) -> Polygon {
        do { return try transform { $0.offset(dx, dy) } } catch { fatalError("translate shouldn't collapse Rings") }
    }

    public func scale(_ factor: Double) throws -> Polygon {
        try transform { Pt2D($0.x * factor, $0.y * factor) }
    }

    public func getOuterRing() -> Ring { rings[0] }

    public func intoOuterRing() -> Ring { rings[0] }

    /// The mean of the outer ring's points (without the repeated last one).
    public func center() -> Pt2D {
        var pts = getOuterRing().points
        pts.removeLast()
        return Pt2D.center(pts)
    }

    /// Top-left at the origin.
    public static func maybeRectangle(_ width: Double, _ height: Double) throws -> Polygon {
        try Ring.new([Pt2D(0.0, 0.0), Pt2D(width, 0.0), Pt2D(width, height), Pt2D(0.0, height), Pt2D(0.0, 0.0)])
            .intoPolygon()
    }

    public static func rectangle(_ width: Double, _ height: Double) -> Polygon {
        do { return try maybeRectangle(width, height) } catch { fatalError("\(error)") }
    }

    public static func rectangleCentered(_ center: Pt2D, _ width: Distance, _ height: Distance) -> Polygon {
        rectangle(width.innerMeters, height.innerMeters)
            .translate(center.x - width.innerMeters / 2.0, center.y - height.innerMeters / 2.0)
    }

    /// The exterior and holes outlined with a thickness, as one tessellation.
    public func toOutline(_ thickness: Distance) -> Tessellation {
        Tessellation.unionAll(rings.map { Tessellation.from($0.toOutline(thickness)) })
    }

    /// Doesn't handle multiple crossings in and out.
    public func clipPolyline(_ input: PolyLine) -> [Pt2D]? {
        let hits = getOuterRing().allIntersections(input)
        if hits.isEmpty {
            return containsPt(input.firstPt()) ? input.points : nil
        } else if hits.count == 1 {
            if containsPt(input.firstPt()) {
                return input.getSliceEndingAt(hits[0])?.points
            }
            return input.getSliceStartingAt(hits[0])?.points
        } else if hits.count == 2 {
            return input.trimToEndpts(hits[0], hits[1]).points
        }
        return nil
    }

    /// The rings as GeoJSON, mapped back to GPS when given bounds. A ring
    /// whose ends are not exactly equal is closed, as geo's `Polygon::new` does.
    public func toGeoJSON(_ gps: GPSBounds?) -> GeoJSONGeometry {
        var rings: [[[Double]]] = []
        for ring in self.rings {
            var pts = ring.points
            if let first = pts.first, let last = pts.last, first.x != last.x || first.y != last.y {
                pts.append(first)
            }
            if let gps {
                rings.append(pts.map { let g = $0.toGPS(gps); return [g.x, g.y] })
            } else {
                rings.append(pts.map { [$0.x, $0.y] })
            }
        }
        return .polygon(rings)
    }

    /// A placeholder value.
    public static func dummy() -> Polygon { rectangle(0.1, 0.1) }

    public var description: String {
        "Polygon with \(rings.count) rings\n" + rings.map { "  \($0)\n" }.joined()
    }
}

extension Tessellation {
    /// geom's `From<Ring outline>`: an outline's tessellation is itself.
    static func from(_ t: Tessellation) -> Tessellation { t }
}
