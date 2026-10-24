/// geo's `BoundingRect` for the geometry types, and geo-types' `get_bounding_rect` helper it is
/// built on (with its `get_min_max` comparisons, not `f64::min`).

/// geo-types' `get_bounding_rect`: `nil` for no coordinates.
func getBoundingRect<S: Sequence>(_ coords: S) -> GeoRect? where S.Element == GeoCoord {
    var iterator = coords.makeIterator()
    guard let first = iterator.next() else { return nil }
    var xrange = (first.x, first.x)
    var yrange = (first.y, first.y)
    while let pnt = iterator.next() {
        xrange = getMinMax(pnt.x, xrange.0, xrange.1)
        yrange = getMinMax(pnt.y, yrange.0, yrange.1)
    }
    return GeoRect(GeoCoord(x: xrange.0, y: yrange.0), GeoCoord(x: xrange.1, y: yrange.1))
}

private func getMinMax(_ p: Double, _ min: Double, _ max: Double) -> (Double, Double) {
    if p > max {
        return (min, p)
    } else if p < min {
        return (p, max)
    } else {
        return (min, max)
    }
}

extension GeoCoord {
    public var boundingRect: GeoRect { GeoRect(self, self) }
}

extension GeoPoint {
    public var boundingRect: GeoRect { GeoRect(coord, coord) }
}

extension GeoLine {
    public var boundingRect: GeoRect { GeoRect(start, end) }
}

extension GeoLineString {
    public var boundingRect: GeoRect? { getBoundingRect(coords) }
}

extension GeoMultiLineString {
    public var boundingRect: GeoRect? { getBoundingRect(lineStrings.lazy.flatMap(\.coords)) }
}

extension GeoPolygon {
    /// The bounding rectangle of the exterior.
    public var boundingRect: GeoRect? { getBoundingRect(exterior.coords) }
}

extension GeoMultiPolygon {
    public var boundingRect: GeoRect? { getBoundingRect(polygons.lazy.flatMap(\.exterior.coords)) }
}

extension GeoMultiPoint {
    public var boundingRect: GeoRect? { getBoundingRect(points.lazy.map(\.coord)) }
}

extension GeoTriangle {
    public var boundingRect: GeoRect { getBoundingRect(vertices)! }
}

extension GeoRect {
    public var boundingRect: GeoRect { self }
}
