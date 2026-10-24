/// geo's `MapCoordsInPlace` and `MapCoords`: apply a function to every coordinate. For a polygon
/// the rings are closed again afterwards, as geo does through `exterior_mut` and `interiors_mut`.

extension GeoLineString {
    public mutating func mapCoordsInPlace(_ transform: (GeoCoord) -> GeoCoord) {
        for i in coords.indices {
            coords[i] = transform(coords[i])
        }
    }

    public func mapCoords(_ transform: (GeoCoord) -> GeoCoord) -> GeoLineString {
        GeoLineString(coords.map(transform))
    }
}

extension GeoPolygon {
    public mutating func mapCoordsInPlace(_ transform: (GeoCoord) -> GeoCoord) {
        exteriorMut { $0.mapCoordsInPlace(transform) }
        interiorsMut { rings in
            for i in rings.indices {
                rings[i].mapCoordsInPlace(transform)
            }
        }
    }

    /// `MapCoords::map_coords`, which builds a new polygon with `Polygon::new`.
    public func mapCoords(_ transform: (GeoCoord) -> GeoCoord) -> GeoPolygon {
        GeoPolygon(exterior.mapCoords(transform), interiors.map { $0.mapCoords(transform) })
    }
}

extension GeoMultiPolygon {
    public mutating func mapCoordsInPlace(_ transform: (GeoCoord) -> GeoCoord) {
        for i in polygons.indices {
            polygons[i].mapCoordsInPlace(transform)
        }
    }

    public func mapCoords(_ transform: (GeoCoord) -> GeoCoord) -> GeoMultiPolygon {
        GeoMultiPolygon(polygons.map { $0.mapCoords(transform) })
    }
}

extension GeoMultiLineString {
    public mutating func mapCoordsInPlace(_ transform: (GeoCoord) -> GeoCoord) {
        for i in lineStrings.indices {
            lineStrings[i].mapCoordsInPlace(transform)
        }
    }
}

extension GeoPoint {
    public func mapCoords(_ transform: (GeoCoord) -> GeoCoord) -> GeoPoint {
        GeoPoint(transform(coord))
    }
}

extension GeoLine {
    public func mapCoords(_ transform: (GeoCoord) -> GeoCoord) -> GeoLine {
        GeoLine(transform(start), transform(end))
    }
}
