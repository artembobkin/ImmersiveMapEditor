/// geom's `Tessellation` (triangles over points, ready to draw) and
/// `Circle`.

import Earcut

public struct Triangle: Sendable {
    public var pt1: Pt2D
    public var pt2: Pt2D
    public var pt3: Pt2D
}

public struct Tessellation: Equatable, Sendable {
    /// Not in any meaningful order.
    public internal(set) var points: [Pt2D]
    /// Groups of three indices are the triangles (u16 in geom).
    public internal(set) var indices: [UInt16]

    public init(points: [Pt2D], indices: [Int]) {
        self.points = points
        self.indices = downsize(indices)
    }

    init(points: [Pt2D], rawIndices: [UInt16]) {
        self.points = points
        self.indices = rawIndices
    }

    /// geom's `From<Polygon>`: the polygon's own tessellation if it has one,
    /// else earcut over its rings.
    public static func from(_ polygon: Polygon) -> Tessellation {
        if let t = polygon.tessellation { return t }
        let geojsonStyle = polygon.rings.map { ring in ring.points.map { [$0.x, $0.y] } }
        let (vertices, holes, dims) = Earcut.flatten(geojsonStyle)
        let indices = downsize(try! Earcut.earcut(vertices, holeIndices: holes, dimensions: dims))
        var points: [Pt2D] = []
        var i = 0
        while i + 1 < vertices.count {
            points.append(Pt2D(vertices[i], vertices[i + 1]))
            i += 2
        }
        return Tessellation(points: points, rawIndices: indices)
    }

    public func triangles() -> [Triangle] {
        var result: [Triangle] = []
        var i = 0
        while i + 2 < indices.count {
            result.append(Triangle(pt1: points[Int(indices[i])], pt2: points[Int(indices[i + 1])],
                                   pt3: points[Int(indices[i + 2])]))
            i += 3
        }
        return result
    }

    public func getBounds() -> Bounds { .from(points) }

    public func center() -> Pt2D { getBounds().center() }

    public func union(_ other: Tessellation) -> Tessellation {
        var points = self.points
        var indices = self.indices
        let offset = UInt16(points.count)
        points.append(contentsOf: other.points)
        for idx in other.indices { indices.append(offset + idx) }
        return Tessellation(points: points, rawIndices: indices)
    }

    /// The last one first, then the others in order, as geom does.
    public static func unionAll(_ list: [Tessellation]) -> Tessellation {
        var list = list
        var result = list.removeLast()
        for p in list { result = result.union(p) }
        return result
    }

    /// One polygon per triangle.
    public func toGeoJSON(_ gps: GPSBounds?) -> GeoJSONGeometry {
        var polygons: [[[[Double]]]] = []
        for t in triangles() {
            let raw = [t.pt1, t.pt2, t.pt3, t.pt1]
            let pts = gps.map { $0.convertBack(raw).map { [$0.x, $0.y] } } ?? raw.map { [$0.x, $0.y] }
            polygons.append([pts])
        }
        return .multiPolygon(polygons)
    }
}

func downsize(_ input: [Int]) -> [UInt16] {
    input.map { x in
        guard let v = UInt16(exactly: x) else { fatalError("\(x) can't fit in u16, some polygon is too huge") }
        return v
    }
}

private let trianglesPerCircle = 60

public struct Circle: Sendable {
    public var center: Pt2D
    public var radius: Distance

    public init(center: Pt2D, radius: Distance) {
        self.center = center
        self.radius = radius
    }

    public func toPolygon() -> Polygon { toRing().intoPolygon() }

    func toRing() -> Ring {
        var pts = (0...trianglesPerCircle).map { i in
            center.projectAway(radius, .degrees(Double(i) / Double(trianglesPerCircle) * 360.0))
        }
        pts.dedup()
        return .mustNew(pts)
    }
}
