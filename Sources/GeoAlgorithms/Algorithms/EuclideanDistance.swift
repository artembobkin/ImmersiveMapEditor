/// geo's `EuclideanDistance` and `EuclideanLength` for points, lines, line strings and polygons,
/// with geo-types' private distance helpers (`line_segment_distance` and its own point-on-line
/// string test with an epsilon) that geo calls for them.

import Foundation

extension GeoLine {
    /// `EuclideanLength`: `dx.hypot(dy)`.
    public var euclideanLength: Double { hypot(dx, dy) }
}

extension GeoLineString {
    /// `EuclideanLength`: the sum of the line lengths.
    public var euclideanLength: Double {
        // Rust's `Sum` for `f64` starts from -0.0.
        lines.reduce(-0.0) { $0 + $1.euclideanLength }
    }
}

/// geo-types' `line_segment_distance`.
func lineSegmentDistance(_ point: GeoCoord, _ start: GeoCoord, _ end: GeoCoord) -> Double {
    if start == end {
        return GeoLine(point, start).euclideanLength
    }
    let dx = end.x - start.x
    let dy = end.y - start.y
    let dSquared = dx * dx + dy * dy
    let r = ((point.x - start.x) * dx + (point.y - start.y) * dy) / dSquared
    if r <= 0 {
        return GeoLine(point, start).euclideanLength
    }
    if r >= 1 {
        return GeoLine(point, end).euclideanLength
    }
    let s = ((start.y - point.y) * dx - (start.x - point.x) * dy) / dSquared
    return abs(s) * hypot(dx, dy)
}

/// geo-types' `point_line_euclidean_distance`.
func pointLineEuclideanDistance(_ p: GeoCoord, _ l: GeoLine) -> Double {
    lineSegmentDistance(p, l.start, l.end)
}

/// geo-types' `point_contains_point`: the distance, cast to `f32`, is approximately zero by
/// approx's `relative_eq!` with its `f32` defaults.
private func pointContainsPoint(_ p1: GeoCoord, _ p2: GeoCoord) -> Bool {
    let distance = Float(GeoLine(p1, p2).euclideanLength)
    if distance == 0 {
        return true
    }
    if distance.isInfinite {
        return false
    }
    let absDiff = abs(distance - 0)
    if absDiff <= Float.ulpOfOne {
        return true
    }
    let largest = Swift.max(abs(distance), 0)
    return absDiff <= largest * Float.ulpOfOne
}

/// geo-types' `line_string_contains_point`, used only by the point to line string distance.
private func lineStringContainsPoint(_ lineString: GeoLineString, _ point: GeoCoord) -> Bool {
    if lineString.coords.isEmpty {
        return false
    }
    if lineString.coords.count == 1 {
        return pointContainsPoint(lineString.coords[0], point)
    }
    if lineString.coords.contains(point) {
        return true
    }
    for line in lineString.lines {
        let tx: Double? = line.dx == 0 ? nil : (point.x - line.start.x) / line.dx
        let ty: Double? = line.dy == 0 ? nil : (point.y - line.start.y) / line.dy
        let contains: Bool
        switch (tx, ty) {
        case (nil, nil):
            contains = point == line.start
        case (let t?, nil):
            contains = point.y == line.start.y && 0 <= t && t <= 1
        case (nil, let t?):
            contains = point.x == line.start.x && 0 <= t && t <= 1
        case (let tX?, let tY?):
            contains = abs(tX - tY) <= Double.ulpOfOne && 0 <= tX && tX <= 1
        }
        if contains {
            return true
        }
    }
    return false
}

/// geo-types' `point_line_string_euclidean_distance`.
func pointLineStringEuclideanDistance(_ p: GeoCoord, _ l: GeoLineString) -> Double {
    if lineStringContainsPoint(l, p) || l.coords.isEmpty {
        return 0
    }
    return l.lines.reduce(Double.greatestFiniteMagnitude) { accum, line in
        rustMin(accum, lineSegmentDistance(p, line.start, line.end))
    }
}

extension GeoCoord {
    public func euclideanDistance(_ c: GeoCoord) -> Double { GeoLine(self, c).euclideanLength }
    public func euclideanDistance(_ line: GeoLine) -> Double { line.euclideanDistance(self) }
}

extension GeoPoint {
    public func euclideanDistance(_ p: GeoPoint) -> Double { coord.euclideanDistance(p.coord) }
    public func euclideanDistance(_ line: GeoLine) -> Double { coord.euclideanDistance(line) }

    public func euclideanDistance(_ lineString: GeoLineString) -> Double {
        pointLineStringEuclideanDistance(coord, lineString)
    }

    /// `Point: EuclideanDistance<Polygon>`: zero inside, else the distance to the nearest ring.
    public func euclideanDistance(_ polygon: GeoPolygon) -> Double {
        if polygon.exterior.coords.isEmpty || polygon.intersects(self) {
            return 0
        }
        let interiorMin = polygon.interiors
            .map { euclideanDistance($0) }
            .reduce(Double.greatestFiniteMagnitude) { rustMin($0, $1) }
        let exteriorMin = polygon.exterior.lines
            .map { lineSegmentDistance(coord, $0.start, $0.end) }
            .reduce(Double.greatestFiniteMagnitude) { rustMin($0, $1) }
        return rustMin(interiorMin, exteriorMin)
    }
}

extension GeoLine {
    public func euclideanDistance(_ coord: GeoCoord) -> Double {
        pointLineEuclideanDistance(coord, self)
    }

    public func euclideanDistance(_ point: GeoPoint) -> Double { euclideanDistance(point.coord) }
}

extension GeoLineString {
    public func euclideanDistance(_ point: GeoPoint) -> Double { point.euclideanDistance(self) }
}

extension GeoPolygon {
    public func euclideanDistance(_ point: GeoPoint) -> Double { point.euclideanDistance(self) }
}
