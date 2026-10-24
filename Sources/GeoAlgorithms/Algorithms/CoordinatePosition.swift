/// geo's `CoordinatePosition`: whether a coordinate is inside, outside or on the boundary of a
/// geometry, by the "mod 2" boundary rule, and `coord_pos_relative_to_ring`, the winding number
/// test with the robust kernel that point-in-polygon rests on.

public enum GeoCoordPos: Sendable, Equatable {
    case onBoundary
    case inside
    case outside
}

/// The accumulator of `calculate_coordinate_position`.
struct CoordPositionState {
    var isInside = false
    var boundaryCount = 0

    /// `coordinate_position`'s final decision.
    var position: GeoCoordPos {
        if boundaryCount % 2 == 1 {
            return .onBoundary
        } else if isInside {
            return .inside
        } else {
            return .outside
        }
    }
}

extension GeoCoord {
    func calculateCoordinatePosition(_ coord: GeoCoord, _ state: inout CoordPositionState) {
        if self == coord {
            state.isInside = true
        }
    }
}

extension GeoLine {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        var state = CoordPositionState()
        calculateCoordinatePosition(coord, &state)
        return state.position
    }

    func calculateCoordinatePosition(_ coord: GeoCoord, _ state: inout CoordPositionState) {
        // A degenerate line is a point.
        if start == end {
            start.calculateCoordinatePosition(coord, &state)
            return
        }
        if coord == start || coord == end {
            state.boundaryCount += 1
        } else if intersects(coord) {
            state.isInside = true
        }
    }
}

extension GeoLineString {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        var state = CoordPositionState()
        calculateCoordinatePosition(coord, &state)
        return state.position
    }

    func calculateCoordinatePosition(_ coord: GeoCoord, _ state: inout CoordPositionState) {
        if coords.count < 2 {
            // A debug assertion in geo: a line string needs two coordinates.
            return
        }
        if coords.count == 2 {
            GeoLine(coords[0], coords[1]).calculateCoordinatePosition(coord, &state)
            return
        }
        if !boundingRect!.intersects(coord) {
            return
        }
        // A closed line string has no boundary.
        if !isClosed {
            if coord == coords.first! || coord == coords.last! {
                state.boundaryCount += 1
                return
            }
        }
        if intersects(coord) {
            state.isInside = true
        }
    }
}

extension GeoPolygon {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        var state = CoordPositionState()
        calculateCoordinatePosition(coord, &state)
        return state.position
    }

    func calculateCoordinatePosition(_ coord: GeoCoord, _ state: inout CoordPositionState) {
        if exterior.isEmpty {
            return
        }
        switch coordPosRelativeToRing(coord, exterior) {
        case .outside:
            break
        case .onBoundary:
            state.boundaryCount += 1
        case .inside:
            for hole in interiors {
                switch coordPosRelativeToRing(coord, hole) {
                case .outside:
                    break
                case .onBoundary:
                    state.boundaryCount += 1
                    return
                case .inside:
                    return
                }
            }
            // The coordinate is outside every hole, so it is inside the polygon.
            state.isInside = true
        }
    }
}

extension GeoMultiPolygon {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        var state = CoordPositionState()
        for polygon in polygons {
            polygon.calculateCoordinatePosition(coord, &state)
        }
        return state.position
    }
}

extension GeoMultiLineString {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        var state = CoordPositionState()
        for lineString in lineStrings {
            lineString.calculateCoordinatePosition(coord, &state)
        }
        return state.position
    }
}

/// `coord_pos_relative_to_ring`: the winding number algorithm with a short cut for the boundary.
/// An upward edge includes its start and excludes its end, a downward edge the reverse,
/// horizontal edges are excluded, and the crossing must be strictly right of the coordinate.
public func coordPosRelativeToRing(_ coord: GeoCoord, _ lineString: GeoLineString) -> GeoCoordPos {
    let coords = lineString.coords
    if coords.isEmpty {
        return .outside
    }
    if coords.count == 1 {
        // A single coordinate makes no lines.
        return coord == coords[0] ? .onBoundary : .outside
    }

    var windingNumber = 0
    for i in 0..<(coords.count - 1) {
        let start = coords[i]
        let end = coords[i + 1]
        if start.y <= coord.y {
            if end.y >= coord.y {
                let o = RobustKernel.orient2d(start, end, coord)
                if o == .counterClockwise && end.y != coord.y {
                    windingNumber += 1
                } else if o == .collinear && valueInBetween(coord.x, start.x, end.x) {
                    return .onBoundary
                }
            }
        } else if end.y <= coord.y {
            let o = RobustKernel.orient2d(start, end, coord)
            if o == .clockwise {
                windingNumber -= 1
            } else if o == .collinear && valueInBetween(coord.x, start.x, end.x) {
                return .onBoundary
            }
        }
    }
    return windingNumber == 0 ? .outside : .inside
}

extension GeoCoord {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        self == coord ? .inside : .outside
    }
}

extension GeoPoint {
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        self.coord == coord ? .inside : .outside
    }
}

extension GeoRect {
    /// Through the rectangle's polygon, as geo 0.27 does.
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        toPolygon().coordinatePosition(coord)
    }
}

extension GeoTriangle {
    /// Through the triangle's polygon, as geo 0.27 does.
    public func coordinatePosition(_ coord: GeoCoord) -> GeoCoordPos {
        toPolygon().coordinatePosition(coord)
    }
}
