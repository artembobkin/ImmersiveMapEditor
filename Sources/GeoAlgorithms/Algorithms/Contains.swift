/// geo's `Contains` for the pairs geom uses: a point in a polygon, a multi-polygon, a line
/// string or a line, and the line-in-line string case. The pairs geo derives from `Relate`
/// (DE-9IM) are not ported.

extension GeoPoint {
    public func contains(_ coord: GeoCoord) -> Bool { self.coord == coord }
    public func contains(_ p: GeoPoint) -> Bool { contains(p.coord) }
}

extension GeoLine {
    /// `Line: Contains<Coord>`: on the line and not one of its ends.
    public func contains(_ coord: GeoCoord) -> Bool {
        if start == end {
            return start == coord
        }
        return coord != start && coord != end && intersects(coord)
    }

    public func contains(_ p: GeoPoint) -> Bool { contains(p.coord) }

    /// `Line: Contains<Line>`.
    public func contains(_ line: GeoLine) -> Bool {
        if line.start == line.end {
            return contains(line.start)
        }
        return intersects(line.start) && intersects(line.end)
    }
}

extension GeoLineString {
    /// `LineString: Contains<Coord>`: the ends of an open line string are not contained.
    public func contains(_ coord: GeoCoord) -> Bool {
        if coords.isEmpty {
            return false
        }
        if coord == coords[0] || coord == coords[coords.count - 1] {
            return isClosed
        }
        for (i, line) in lines.enumerated() {
            if line.contains(coord) || (i > 0 && coord == line.start) {
                return true
            }
        }
        return false
    }

    public func contains(_ p: GeoPoint) -> Bool { contains(p.coord) }
}

extension GeoPolygon {
    /// `Polygon: Contains<Coord>`: strictly inside, not on the boundary.
    public func contains(_ coord: GeoCoord) -> Bool {
        coordinatePosition(coord) == .inside
    }

    public func contains(_ p: GeoPoint) -> Bool { contains(p.coord) }
}

extension GeoMultiPolygon {
    public func contains(_ coord: GeoCoord) -> Bool {
        polygons.contains { $0.contains(coord) }
    }

    public func contains(_ p: GeoPoint) -> Bool { contains(p.coord) }

    public func contains(_ rhs: GeoMultiPoint) -> Bool {
        rhs.points.allSatisfy { contains($0) }
    }
}
