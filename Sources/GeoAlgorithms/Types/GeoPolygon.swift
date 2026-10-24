/// geo-types' `Polygon<f64>` and `MultiPolygon<f64>`. A polygon closes its rings on construction
/// and after every mutation of them, exactly as geo-types does.

/// A polygon: an exterior ring and zero or more interior rings (holes).
public struct GeoPolygon: Hashable, Sendable {
    public private(set) var exterior: GeoLineString
    public private(set) var interiors: [GeoLineString]

    /// `Polygon::new`: closes the exterior and every interior that is not closed yet.
    public init(_ exterior: GeoLineString, _ interiors: [GeoLineString]) {
        var exterior = exterior
        exterior.close()
        var interiors = interiors
        for i in interiors.indices {
            interiors[i].close()
        }
        self.exterior = exterior
        self.interiors = interiors
    }

    /// `Polygon::empty()`.
    public static let empty = GeoPolygon(.empty, [])

    /// `Polygon::exterior_mut`: mutates the exterior, then closes it again.
    public mutating func exteriorMut(_ body: (inout GeoLineString) throws -> Void) rethrows {
        try body(&exterior)
        exterior.close()
    }

    /// `Polygon::interiors_mut`: mutates the interiors, then closes each of them again.
    public mutating func interiorsMut(_ body: (inout [GeoLineString]) throws -> Void) rethrows {
        try body(&interiors)
        for i in interiors.indices {
            interiors[i].close()
        }
    }

    /// `Polygon::interiors_push`: closes the new interior and appends it.
    public mutating func interiorsPush(_ interior: GeoLineString) {
        var interior = interior
        interior.close()
        interiors.append(interior)
    }

    public var numRings: Int { interiors.count + 1 }
    public var numInteriorRings: Int { interiors.count }
}

/// A collection of polygons, geo-types' `MultiPolygon<f64>`.
public struct GeoMultiPolygon: Hashable, Sendable {
    public var polygons: [GeoPolygon]

    public init(_ polygons: [GeoPolygon]) {
        self.polygons = polygons
    }

    /// `MultiPolygon::from(Polygon)`.
    public init(_ polygon: GeoPolygon) {
        self.polygons = [polygon]
    }
}

// MARK: - Coordinate counts, as geo's `CoordsIter::coords_count`

extension GeoPolygon {
    /// The number of coordinates of the exterior and all interiors.
    public var coordsCount: Int {
        exterior.count + interiors.reduce(0) { $0 + $1.count }
    }
}

extension GeoMultiPolygon {
    public var coordsCount: Int {
        polygons.reduce(0) { $0 + $1.coordsCount }
    }

    /// `MultiPolygon::exterior_coords_iter`, collected.
    public var exteriorCoords: [GeoCoord] {
        polygons.flatMap(\.exterior.coords)
    }
}

extension GeoMultiLineString {
    public var coordsCount: Int {
        lineStrings.reduce(0) { $0 + $1.count }
    }
}
