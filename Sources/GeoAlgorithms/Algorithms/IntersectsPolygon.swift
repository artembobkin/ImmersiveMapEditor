/// geo's `Intersects` for line strings, polygons and multi-polygons: the blanket
/// implementations over `lines()` with their bounding box pre-checks, and the polygon pairs.

extension GeoLineString {
    public func intersects(_ rhs: GeoCoord) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return lines.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoPoint) -> Bool { intersects(rhs.coord) }

    public func intersects(_ rhs: GeoLine) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return lines.contains { $0.intersects(rhs) }
    }

    /// `LineString: Intersects<LineString>`, through `Line: Intersects<LineString>`.
    public func intersects(_ rhs: GeoLineString) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return lines.contains { rhs.intersects($0) }
    }

    public func intersects(_ rhs: GeoRect) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return lines.contains { rhs.intersects($0) }
    }

    public func intersects(_ rhs: GeoPolygon) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return lines.contains { rhs.intersects($0) }
    }

    public func intersects(_ rhs: GeoMultiPolygon) -> Bool { rhs.intersects(self) }
}

extension GeoPolygon {
    /// `Polygon: Intersects<Coord>`: not outside the exterior and not inside any interior.
    public func intersects(_ p: GeoCoord) -> Bool {
        coordPosRelativeToRing(p, exterior) != .outside
            && interiors.allSatisfy { coordPosRelativeToRing(p, $0) != .inside }
    }

    public func intersects(_ p: GeoPoint) -> Bool { intersects(p.coord) }

    public func intersects(_ line: GeoLine) -> Bool {
        exterior.intersects(line)
            || interiors.contains { $0.intersects(line) }
            || intersects(line.start)
            || intersects(line.end)
    }

    public func intersects(_ rhs: GeoLineString) -> Bool { rhs.intersects(self) }

    public func intersects(_ rect: GeoRect) -> Bool { intersects(rect.toPolygon()) }

    public func intersects(_ polygon: GeoPolygon) -> Bool {
        if hasDisjointBboxes(boundingRect, polygon.boundingRect) {
            return false
        }
        return intersects(polygon.exterior)
            || polygon.interiors.contains { intersects($0) }
            || polygon.intersects(exterior)
    }

    public func intersects(_ rhs: GeoMultiPolygon) -> Bool { rhs.intersects(self) }
}

extension GeoMultiPolygon {
    public func intersects(_ rhs: GeoCoord) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoPoint) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoLine) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoLineString) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoRect) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoPolygon) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }

    public func intersects(_ rhs: GeoMultiPolygon) -> Bool {
        if hasDisjointBboxes(boundingRect, rhs.boundingRect) { return false }
        return polygons.contains { $0.intersects(rhs) }
    }
}
