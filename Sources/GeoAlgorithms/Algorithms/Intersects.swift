/// geo's `Intersects` for the primitive pairs: coordinates, points, lines and rectangles, with
/// the `value_in_range`, `point_in_rect` and bounding box helpers geo uses. The collection and
/// polygon pairs are in `IntersectsPolygon.swift`.

/// `value_in_range`: `min <= value <= max`.
@inline(__always)
func valueInRange(_ value: Double, _ min: Double, _ max: Double) -> Bool {
    value >= min && value <= max
}

/// `value_in_between`: the bounds may come in either order.
@inline(__always)
func valueInBetween(_ value: Double, _ bound1: Double, _ bound2: Double) -> Bool {
    if bound1 < bound2 {
        return valueInRange(value, bound1, bound2)
    } else {
        return valueInRange(value, bound2, bound1)
    }
}

/// `point_in_rect`: the rectangle spanned by two corners in any order contains `value`.
@inline(__always)
func pointInRect(_ value: GeoCoord, _ bound1: GeoCoord, _ bound2: GeoCoord) -> Bool {
    valueInBetween(value.x, bound1.x, bound2.x) && valueInBetween(value.y, bound1.y, bound2.y)
}

/// `has_disjoint_bboxes`: both bounding boxes exist and do not intersect.
func hasDisjointBboxes(_ a: GeoRect?, _ b: GeoRect?) -> Bool {
    if let a, let b, !a.intersects(b) {
        return true
    }
    return false
}

extension GeoCoord {
    public func intersects(_ rhs: GeoCoord) -> Bool { self == rhs }
    public func intersects(_ rhs: GeoPoint) -> Bool { self == rhs.coord }
    public func intersects(_ rhs: GeoLine) -> Bool { rhs.intersects(self) }
    public func intersects(_ rhs: GeoRect) -> Bool { rhs.intersects(self) }
    public func intersects(_ rhs: GeoLineString) -> Bool { rhs.intersects(self) }
    public func intersects(_ rhs: GeoPolygon) -> Bool { rhs.intersects(self) }
}

extension GeoPoint {
    public func intersects(_ rhs: GeoCoord) -> Bool { coord.intersects(rhs) }
    public func intersects(_ rhs: GeoPoint) -> Bool { coord.intersects(rhs) }
    public func intersects(_ rhs: GeoLine) -> Bool { coord.intersects(rhs) }
    public func intersects(_ rhs: GeoRect) -> Bool { coord.intersects(rhs) }
    public func intersects(_ rhs: GeoLineString) -> Bool { coord.intersects(rhs) }
    public func intersects(_ rhs: GeoPolygon) -> Bool { coord.intersects(rhs) }
    public func intersects(_ rhs: GeoMultiPolygon) -> Bool { rhs.intersects(self) }
}

extension GeoLine {
    /// `Line: Intersects<Coord>`: the coordinate is collinear and inside the line's box.
    public func intersects(_ rhs: GeoCoord) -> Bool {
        RobustKernel.orient2d(start, end, rhs) == .collinear && pointInRect(rhs, start, end)
    }

    public func intersects(_ rhs: GeoPoint) -> Bool { intersects(rhs.coord) }

    /// `Line: Intersects<Line>`. The collinear case tests `self.end` twice and never
    /// `self.start`, as geo 0.27 does.
    public func intersects(_ line: GeoLine) -> Bool {
        if start == end {
            return line.intersects(start)
        }
        let check11 = RobustKernel.orient2d(start, end, line.start)
        let check12 = RobustKernel.orient2d(start, end, line.end)
        if check11 != check12 {
            let check21 = RobustKernel.orient2d(line.start, line.end, start)
            let check22 = RobustKernel.orient2d(line.start, line.end, end)
            return check21 != check22
        } else if check11 == .collinear {
            return pointInRect(line.start, start, end)
                || pointInRect(line.end, start, end)
                || pointInRect(end, line.start, line.end)
                || pointInRect(end, line.start, line.end)
        } else {
            return false
        }
    }

    public func intersects(_ rhs: GeoRect) -> Bool { rhs.intersects(self) }
    public func intersects(_ rhs: GeoLineString) -> Bool { rhs.intersects(self) }
    public func intersects(_ rhs: GeoPolygon) -> Bool { rhs.intersects(self) }
    public func intersects(_ rhs: GeoMultiPolygon) -> Bool { rhs.intersects(self) }
}

extension GeoRect {
    /// `Rect: Intersects<Coord>`.
    public func intersects(_ rhs: GeoCoord) -> Bool {
        valueInRange(rhs.x, min.x, max.x) && valueInRange(rhs.y, min.y, max.y)
    }

    public func intersects(_ rhs: GeoPoint) -> Bool { intersects(rhs.coord) }

    /// `Rect: Intersects<Rect>`.
    public func intersects(_ other: GeoRect) -> Bool {
        if max.x < other.min.x { return false }
        if max.y < other.min.y { return false }
        if min.x > other.max.x { return false }
        if min.y > other.max.y { return false }
        return true
    }

    /// `Rect: Intersects<Line>`: an end inside, or a crossing of one of the four sides.
    public func intersects(_ rhs: GeoLine) -> Bool {
        let lt = min
        let rb = max
        let lb = GeoCoord(x: lt.x, y: rb.y)
        let rt = GeoCoord(x: rb.x, y: lt.y)
        return intersects(rhs.start)
            || intersects(rhs.end)
            || GeoLine(lt, rt).intersects(rhs)
            || GeoLine(rt, rb).intersects(rhs)
            || GeoLine(lb, rb).intersects(rhs)
            || GeoLine(lt, lb).intersects(rhs)
    }

    public func intersects(_ rhs: GeoLineString) -> Bool { rhs.intersects(self) }

    /// `Rect: Intersects<Polygon>`, symmetric to `Polygon: Intersects<Rect>`.
    public func intersects(_ rhs: GeoPolygon) -> Bool { rhs.intersects(self) }
}
