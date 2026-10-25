import Topology

/// The operations of `Geometry`, each the port's equivalent of the GEOS C
/// API function the wrapper called (Docs/PortingTopologyProgress.md has the
/// table), failing as it did (`Failure`).
extension Geometry {
    public func buffer(_ d: Double, quadSegs: Int = 16, cap: Cap = .round, join: Join = .round,
                       mitreLimit: Double = 5) -> Geometry {
        Recorder.shared?.call("buffer", [self], [d, Double(quadSegs), Double(cap.rawValue), Double(join.rawValue), mitreLimit])
        return Geometry.make {
            try geometry.buffer(d, quadSegs: quadSegs, endCapStyle: Int(cap.rawValue), joinStyle: Int(join.rawValue), mitreLimit: mitreLimit)
        }
    }

    public func union(_ o: Geometry) -> Geometry {
        Recorder.shared?.call("union", [self, o])
        return Geometry.make { try geometry.union(o.geometry) }
    }

    public func intersection(_ o: Geometry) -> Geometry {
        Recorder.shared?.call("intersection", [self, o])
        return Geometry.make { try geometry.intersection(o.geometry) }
    }

    public func difference(_ o: Geometry) -> Geometry {
        Recorder.shared?.call("difference", [self, o])
        return Geometry.make { try geometry.difference(o.geometry) }
    }

    public static func unaryUnion(_ parts: [Geometry]) -> Geometry {
        Recorder.shared?.call("unaryUnion", parts)
        let c = collection(parts)
        if c.isEmpty { return c }
        return make { try c.geometry.union() }
    }

    /// Douglas-Peucker keeping the topology, as shapely's `simplify`.
    public func simplify(_ tolerance: Double) -> Geometry {
        Recorder.shared?.call("simplify", [self], [tolerance])
        return Geometry.make { try geometry.topologyPreserveSimplify(tolerance) }
    }

    public func makeValid() -> Geometry {
        Recorder.shared?.call("makeValid", [self])
        return Geometry.make { try geometry.makeValid() }
    }

    public func setPrecision(_ grid: Double) -> Geometry {
        Recorder.shared?.call("setPrecision", [self], [grid])
        return Geometry.make { try geometry.setPrecision(grid) }
    }

    public var convexHull: Geometry {
        Recorder.shared?.call("convexHull", [self])
        return Geometry.make { geometry.convexHull() }
    }

    public var envelope: Geometry {
        Recorder.shared?.call("envelope", [self])
        return Geometry.make { geometry.getEnvelope() }
    }

    /// The boundary; empty for a geometry collection, which GEOS refuses.
    public var boundary: Geometry {
        Recorder.shared?.call("boundary", [self])
        if type(of: geometry) == GeometryCollection.self { return .empty }
        return Geometry.make { geometry.getBoundary() }
    }

    public var minimumRotatedRectangle: Geometry {
        Recorder.shared?.call("minimumRotatedRectangle", [self])
        return Geometry.make { MinimumAreaRectangle.getMinimumRectangle(geometry) }
    }

    public func offsetCurve(_ d: Double, quadSegs: Int = 16, join: Join = .round, mitreLimit: Double = 5) -> Geometry {
        Recorder.shared?.call("offsetCurve", [self], [d, Double(quadSegs), Double(join.rawValue), mitreLimit])
        return Geometry.make { try geometry.offsetCurve(d, quadSegs: quadSegs, joinStyle: Int(join.rawValue), mitreLimit: mitreLimit) }
    }

    /// The point `d` along a line (or a share of its length).
    public func interpolate(_ d: Double, normalized: Bool = false) -> Geometry {
        Recorder.shared?.call("interpolate", [self], [d, normalized ? 1 : 0])
        return Geometry.make { try geometry.interpolate(d, normalized: normalized) }
    }

    /// How far along a line the point nearest to `p` is (-1 where it fails).
    public func project(_ p: Geometry) -> Double {
        Recorder.shared?.call("project", [self, p])
        return Failure.attempt(-1) { try geometry.project(p.geometry) }
    }

    public func distance(_ o: Geometry) -> Double {
        Recorder.shared?.call("distance", [self, o])
        return Failure.attempt(0) { geometry.distance(o.geometry) }
    }

    public func intersects(_ o: Geometry) -> Bool {
        Recorder.shared?.call("intersects", [self, o])
        return Failure.attempt(false) { try geometry.intersects(o.geometry) }
    }

    public func contains(_ o: Geometry) -> Bool {
        Recorder.shared?.call("contains", [self, o])
        return Failure.attempt(false) { try geometry.contains(o.geometry) }
    }

    public func contains(_ p: P2) -> Bool { contains(.point(p)) }

    public func within(_ o: Geometry) -> Bool {
        Recorder.shared?.call("within", [self, o])
        return Failure.attempt(false) { try geometry.within(o.geometry) }
    }

    /// The nearest points of this and `o`: this one's first; zeros when
    /// either is empty.
    public func nearestPoints(_ o: Geometry) -> (P2, P2) {
        Recorder.shared?.call("nearestPoints", [self, o])
        guard !isEmpty && !o.isEmpty,
              let pts = Failure.attempt(nil, { DistanceOp.nearestPoints(geometry, o.geometry) }) else { return (.zero, .zero) }
        return (P2(pts[0].x, pts[0].y), P2(pts[1].x, pts[1].y))
    }

    /// Triangles of a polygon, its edges kept.
    public func constrainedDelaunay() -> [[P2]] {
        Recorder.shared?.call("constrainedDelaunay", [self])
        let t = Geometry.make { try ConstrainedDelaunayTriangulator.triangulate(geometry) }
        return t.polygons.map { Array($0.exterior.prefix(3)) }
    }

    public static func polygonize(_ lines: [Geometry]) -> Geometry {
        Recorder.shared?.call("polygonize", lines)
        return make { try Topology.Geometry.polygonize(lines.map(\.geometry)) }
    }

    public func lineMerge() -> Geometry {
        Recorder.shared?.call("lineMerge", [self])
        return Geometry.make { try geometry.lineMerge() }
    }
}
