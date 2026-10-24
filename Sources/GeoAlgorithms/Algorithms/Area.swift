/// geo's `Area`: the signed and unsigned planar area of rings, polygons and multi-polygons, by
/// the shoelace formula over coordinates shifted to the ring's first coordinate.

/// `twice_signed_ring_area`: zero for a ring with fewer than three coordinates or not closed.
func twiceSignedRingArea(_ lineString: GeoLineString) -> Double {
    let coords = lineString.coords
    if coords.count < 3 {
        return 0
    }
    if coords.first! != coords.last! {
        return 0
    }
    // Shift the coordinates to limit the numerical error of summing the determinants.
    let shift = coords[0]
    var tmp = 0.0
    for i in 0..<(coords.count - 1) {
        let line = GeoLine(coords[i] - shift, coords[i + 1] - shift)
        tmp = tmp + line.determinant
    }
    return tmp
}

/// `get_linestring_area`.
func getLineStringArea(_ lineString: GeoLineString) -> Double {
    twiceSignedRingArea(lineString) / (1.0 + 1.0)
}

extension GeoPoint {
    public var signedArea: Double { 0 }
    public var unsignedArea: Double { 0 }
}

extension GeoLine {
    public var signedArea: Double { 0 }
    public var unsignedArea: Double { 0 }
}

extension GeoLineString {
    public var signedArea: Double { 0 }
    public var unsignedArea: Double { 0 }
}

extension GeoPolygon {
    /// The exterior's area less the holes' areas, with the sign of the exterior's winding
    /// (positive counterclockwise).
    public var signedArea: Double {
        let area = getLineStringArea(exterior)
        // Testing the sign here avoids computing the shoelace formula twice.
        let isNegative = area < 0
        let total = interiors.reduce(abs(area)) { total, next in
            total - abs(getLineStringArea(next))
        }
        return isNegative ? -total : total
    }

    public var unsignedArea: Double { abs(signedArea) }
}

extension GeoMultiPolygon {
    /// The sum of the polygons' signed areas.
    public var signedArea: Double {
        polygons.reduce(0.0) { $0 + $1.signedArea }
    }

    /// The sum of the absolute signed areas of the polygons.
    public var unsignedArea: Double {
        polygons.reduce(0.0) { $0 + abs($1.signedArea) }
    }
}

extension GeoRect {
    public var signedArea: Double { width * height }
    public var unsignedArea: Double { width * height }
}

extension GeoTriangle {
    public var signedArea: Double {
        toLines().reduce(0.0) { $0 + $1.determinant } / (1.0 + 1.0)
    }

    public var unsignedArea: Double { abs(signedArea) }
}
