import geos
import simd

/// The `Geometry` wrapper as it stood on GEOS before phase 8 (its
/// `Sources/Geometry/Geometry.swift` at commit 50caf95, the recorder taken
/// out), kept as the oracle of the swap: the port's `Geometry` must give
/// what this gives, call for call (`Recording/WrapperReplayTests`). Its one
/// GEOS context is used by one test at a time (the suites that use it are
/// serialized).
enum GEOSWrapper {
    /// A point in plan.
    typealias P2 = SIMD2<Double>

    /// The one GEOS context. The build runs on one thread at a time.

    nonisolated(unsafe) static let ctx: GEOSContextHandle_t = {
        let c = GEOS_init_r()!
        return c
    }()

    /// A planar geometry of GEOS, owned: points, lines, polygons and their
    /// collections, with the operations the build uses, named as shapely names
    /// them (the Python build this ports was written against shapely).
    ///
    /// An operation GEOS cannot do (a topology error) gives an empty geometry.
    public final class Geometry: CustomStringConvertible {
        public let ptr: OpaquePointer

        /// Takes ownership of a GEOS geometry.
        public init(owning ptr: OpaquePointer) {
            self.ptr = ptr
        }

        deinit {
            GEOSGeom_destroy_r(ctx, ptr)
        }

        static func make(_ p: OpaquePointer?) -> Geometry {
            if let p { return Geometry(owning: p) }
            return .empty
        }

        /// A copy of a geometry GEOS owns elsewhere (a part of a collection).
        static func copy(_ p: OpaquePointer?) -> Geometry {
            guard let p, let c = GEOSGeom_clone_r(ctx, p) else { return .empty }
            return Geometry(owning: c)
        }

        public enum Kind: Int32 {
            case point = 0, lineString, linearRing, polygon, multiPoint, multiLineString, multiPolygon, collection
        }

        public enum Cap: Int32 { case round = 1, flat = 2, square = 3 }
        public enum Join: Int32 { case round = 1, mitre = 2, bevel = 3 }

        // MARK: Making

        public static var empty: Geometry {
            return Geometry(owning: GEOSGeom_createEmptyCollection_r(ctx, 7)!)
        }

        static func sequence(_ pts: [P2]) -> OpaquePointer {
            var flat = [Double]()
            flat.reserveCapacity(pts.count * 2)
            for p in pts { flat.append(p.x); flat.append(p.y) }
            return GEOSCoordSeq_copyFromBuffer_r(ctx, flat, UInt32(pts.count), 0, 0)!
        }

        public static func point(_ x: Double, _ y: Double) -> Geometry {
            return Geometry(owning: GEOSGeom_createPointFromXY_r(ctx, x, y)!)
        }

        public static func point(_ p: P2) -> Geometry { point(p.x, p.y) }

        public static func lineString(_ pts: [P2]) -> Geometry {
            guard pts.count >= 2 else { return Geometry(owning: GEOSGeom_createEmptyLineString_r(ctx)!) }
            return make(GEOSGeom_createLineString_r(ctx, sequence(pts)))
        }

        static func ring(_ pts: [P2]) -> OpaquePointer? {
            guard pts.count >= 3 else { return nil }
            var closed = pts
            if closed.first! != closed.last! { closed.append(closed[0]) }
            guard closed.count >= 4 else { return nil }
            return GEOSGeom_createLinearRing_r(ctx, sequence(closed))
        }

        /// A polygon of an outer ring and holes, open or closed.
        public static func polygon(_ shell: [P2], holes: [[P2]] = []) -> Geometry {
            guard let s = ring(shell) else { return Geometry(owning: GEOSGeom_createEmptyPolygon_r(ctx)!) }
            var hs: [OpaquePointer?] = holes.compactMap { ring($0) }
            return make(GEOSGeom_createPolygon_r(ctx, s, &hs, UInt32(hs.count)))
        }

        public static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Geometry {
            polygon([P2(x0, y0), P2(x1, y0), P2(x1, y1), P2(x0, y1)])
        }

        /// A collection of copies of the geometries: a multi-geometry when they
        /// are all of one kind, else a geometry collection.
        public static func collection(_ parts: [Geometry]) -> Geometry {
            let flat = parts.flatMap { $0.isEmpty ? [] : ($0.isMulti ? $0.parts : [$0]) }
            guard !flat.isEmpty else { return .empty }
            let kinds = Set(flat.map(\.kind))
            let type: Int32
            if kinds == [.polygon] { type = 6 } else if kinds == [.lineString] { type = 5 } else if kinds == [.point] { type = 4 } else { type = 7 }
            var ptrs: [OpaquePointer?] = flat.map { GEOSGeom_clone_r(ctx, $0.ptr) }
            return make(GEOSGeom_createCollection_r(ctx, type, &ptrs, UInt32(ptrs.count)))
        }

        // MARK: Reading

        public var kind: Kind { Kind(rawValue: GEOSGeomTypeId_r(ctx, ptr)) ?? .collection }
        public var isEmpty: Bool { GEOSisEmpty_r(ctx, ptr) == 1 }
        public var isValid: Bool {
            return GEOSisValid_r(ctx, ptr) == 1
        }
        public var isMulti: Bool { [.multiPoint, .multiLineString, .multiPolygon, .collection].contains(kind) }

        public var area: Double {
            var d = 0.0
            GEOSArea_r(ctx, ptr, &d)
            return d
        }

        public var length: Double {
            var d = 0.0
            GEOSLength_r(ctx, ptr, &d)
            return d
        }

        /// (x0, y0, x1, y1).
        public var bounds: (Double, Double, Double, Double) {
            guard !isEmpty else { return (0, 0, 0, 0) }
            var a = 0.0, b = 0.0, c = 0.0, d = 0.0
            GEOSGeom_getXMin_r(ctx, ptr, &a)
            GEOSGeom_getYMin_r(ctx, ptr, &b)
            GEOSGeom_getXMax_r(ctx, ptr, &c)
            GEOSGeom_getYMax_r(ctx, ptr, &d)
            return (a, b, c, d)
        }

        /// A point's coordinates.
        public var x: Double {
            var d = 0.0
            GEOSGeomGetX_r(ctx, ptr, &d)
            return d
        }

        public var y: Double {
            var d = 0.0
            GEOSGeomGetY_r(ctx, ptr, &d)
            return d
        }

        public var xy: P2 { P2(x, y) }

        /// The coordinates of a point, line or ring.
        public var coords: [P2] {
            guard let seq = GEOSGeom_getCoordSeq_r(ctx, ptr) else { return [] }
            return Geometry.read(seq)
        }

        static func read(_ seq: OpaquePointer) -> [P2] {
            var n: UInt32 = 0
            GEOSCoordSeq_getSize_r(ctx, seq, &n)
            guard n > 0 else { return [] }
            var flat = [Double](repeating: 0, count: Int(n) * 2)
            GEOSCoordSeq_copyToBuffer_r(ctx, seq, &flat, 0, 0)
            return (0..<Int(n)).map { P2(flat[2 * $0], flat[2 * $0 + 1]) }
        }

        /// A polygon's outer ring (closed) and holes.
        public var exterior: [P2] {
            guard kind == .polygon, let r = GEOSGetExteriorRing_r(ctx, ptr), let seq = GEOSGeom_getCoordSeq_r(ctx, r)
            else { return [] }
            return Geometry.read(seq)
        }

        public var interiors: [[P2]] {
            guard kind == .polygon else { return [] }
            return (0..<GEOSGetNumInteriorRings_r(ctx, ptr)).compactMap { i in
                guard let r = GEOSGetInteriorRingN_r(ctx, ptr, i), let seq = GEOSGeom_getCoordSeq_r(ctx, r) else { return nil }
                return Geometry.read(seq)
            }
        }

        /// The parts of a collection (copies); a single geometry is its own.
        public var parts: [Geometry] {
            guard isMulti else { return [self] }
            return (0..<GEOSGetNumGeometries_r(ctx, ptr)).map { Geometry.copy(GEOSGetGeometryN_r(ctx, ptr, $0)) }
        }

        /// Every polygon in it, as shapely's `polygons` helper of the build.
        public var polygons: [Geometry] {
            if isEmpty { return [] }
            if kind == .polygon { return [self] }
            return isMulti ? parts.flatMap(\.polygons) : []
        }

        /// Every line string in it.
        public var lines: [Geometry] {
            if isEmpty { return [] }
            if kind == .lineString || kind == .linearRing { return [self] }
            return isMulti ? parts.flatMap(\.lines) : []
        }

        public var centroid: Geometry {
            return Geometry.make(GEOSGetCentroid_r(ctx, ptr))
        }

        public var representativePoint: Geometry {
            return Geometry.make(GEOSPointOnSurface_r(ctx, ptr))
        }

        public var description: String {
            let w = GEOSWKTWriter_create_r(ctx)
            defer { GEOSWKTWriter_destroy_r(ctx, w) }
            GEOSWKTWriter_setRoundingPrecision_r(ctx, w, 3)
            guard let s = GEOSWKTWriter_write_r(ctx, w, ptr) else { return "?" }
            defer { GEOSFree_r(ctx, s) }
            return String(cString: s)
        }

        // MARK: Operations

        public func buffer(_ d: Double, quadSegs: Int = 16, cap: Cap = .round, join: Join = .round,
                           mitreLimit: Double = 5) -> Geometry {
            return Geometry.make(GEOSBufferWithStyle_r(ctx, ptr, d, Int32(quadSegs), cap.rawValue, join.rawValue, mitreLimit))
        }

        public func union(_ o: Geometry) -> Geometry {
            return Geometry.make(GEOSUnion_r(ctx, ptr, o.ptr))
        }

        public func intersection(_ o: Geometry) -> Geometry {
            return Geometry.make(GEOSIntersection_r(ctx, ptr, o.ptr))
        }

        public func difference(_ o: Geometry) -> Geometry {
            return Geometry.make(GEOSDifference_r(ctx, ptr, o.ptr))
        }

        public static func unaryUnion(_ parts: [Geometry]) -> Geometry {
            let c = collection(parts)
            if c.isEmpty { return c }
            return make(GEOSUnaryUnion_r(ctx, c.ptr))
        }

        /// Douglas-Peucker keeping the topology, as shapely's `simplify`.
        public func simplify(_ tolerance: Double) -> Geometry {
            return Geometry.make(GEOSTopologyPreserveSimplify_r(ctx, ptr, tolerance))
        }

        public func makeValid() -> Geometry {
            return Geometry.make(GEOSMakeValid_r(ctx, ptr))
        }

        public func setPrecision(_ grid: Double) -> Geometry {
            return Geometry.make(GEOSGeom_setPrecision_r(ctx, ptr, grid, 0))
        }

        public var convexHull: Geometry {
            return Geometry.make(GEOSConvexHull_r(ctx, ptr))
        }

        public var envelope: Geometry {
            return Geometry.make(GEOSEnvelope_r(ctx, ptr))
        }

        public var boundary: Geometry {
            return Geometry.make(GEOSBoundary_r(ctx, ptr))
        }

        public var minimumRotatedRectangle: Geometry {
            return Geometry.make(GEOSMinimumRotatedRectangle_r(ctx, ptr))
        }


        public func offsetCurve(_ d: Double, quadSegs: Int = 16, join: Join = .round, mitreLimit: Double = 5) -> Geometry {
            return Geometry.make(GEOSOffsetCurve_r(ctx, ptr, d, Int32(quadSegs), join.rawValue, mitreLimit))
        }

        /// The point `d` along a line (or a share of its length).
        public func interpolate(_ d: Double, normalized: Bool = false) -> Geometry {
            return Geometry.make(normalized ? GEOSInterpolateNormalized_r(ctx, ptr, d) : GEOSInterpolate_r(ctx, ptr, d))
        }

        /// How far along a line the point nearest to `p` is.
        public func project(_ p: Geometry) -> Double {
            return GEOSProject_r(ctx, ptr, p.ptr)
        }

        public func distance(_ o: Geometry) -> Double {
            var d = 0.0
            GEOSDistance_r(ctx, ptr, o.ptr, &d)
            return d
        }

        public func intersects(_ o: Geometry) -> Bool {
            return GEOSIntersects_r(ctx, ptr, o.ptr) == 1
        }

        public func contains(_ o: Geometry) -> Bool {
            return GEOSContains_r(ctx, ptr, o.ptr) == 1
        }

        public func contains(_ p: P2) -> Bool { contains(.point(p)) }

        public func within(_ o: Geometry) -> Bool {
            return GEOSWithin_r(ctx, ptr, o.ptr) == 1
        }

        /// The nearest points of this and `o`: this one's first.
        public func nearestPoints(_ o: Geometry) -> (P2, P2) {
            guard let seq = GEOSNearestPoints_r(ctx, ptr, o.ptr) else { return (.zero, .zero) }
            defer { GEOSCoordSeq_destroy_r(ctx, seq) }
            let pts = Geometry.read(seq)
            return (pts[0], pts[1])
        }

        /// Triangles of a polygon, its edges kept.
        public func constrainedDelaunay() -> [[P2]] {
            let t = Geometry.make(GEOSConstrainedDelaunayTriangulation_r(ctx, ptr))
            return t.polygons.map { Array($0.exterior.prefix(3)) }
        }

        public static func polygonize(_ lines: [Geometry]) -> Geometry {
            var ptrs: [OpaquePointer?] = lines.map { $0.ptr }
            return make(GEOSPolygonize_r(ctx, &ptrs, UInt32(ptrs.count)))
        }

        public func lineMerge() -> Geometry {
            return Geometry.make(GEOSLineMerge_r(ctx, ptr))
        }

        // MARK: Done in Swift

        /// Every coordinate moved by `f`, the structure kept.
        public func map(_ f: (P2) -> P2) -> Geometry {
            switch kind {
            case .point: return .point(f(xy))
            case .lineString: return .lineString(coords.map(f))
            case .linearRing: return .lineString(coords.map(f))
            case .polygon: return .polygon(exterior.map(f), holes: interiors.map { $0.map(f) })
            default: return .collection(parts.map { $0.map(f) })
            }
        }

        public func translate(_ dx: Double, _ dy: Double) -> Geometry { map { $0 + P2(dx, dy) } }

        /// Turned by `degrees` (or radians) about `origin`.
        public func rotate(_ angle: Double, origin: P2, radians: Bool = false) -> Geometry {
            let r = radians ? angle : angle * .pi / 180
            let c = cos(r), s = sin(r)
            return map { p in
                let d = p - origin
                return origin + P2(d.x * c - d.y * s, d.x * s + d.y * c)
            }
        }

        public func scale(_ sx: Double, _ sy: Double, origin: P2) -> Geometry {
            map { origin + ($0 - origin) * P2(sx, sy) }
        }

        /// A polygon with its outer ring counter-clockwise (sign 1) or clockwise
        /// (-1), its holes the other way, as shapely's `orient`.
        public func oriented(_ sign: Double = 1) -> Geometry {
            guard kind == .polygon else { return .collection(parts.map { $0.oriented(sign) }) }
            func wound(_ r: [P2], ccw: Bool) -> [P2] { (signedArea(r) > 0) == ccw ? r : r.reversed() }
            return .polygon(wound(exterior, ccw: sign > 0), holes: interiors.map { wound($0, ccw: sign < 0) })
        }

        /// The part of a line from `start` to `end` along it, as shapely's
        /// `substring`.
        public func substring(_ start: Double, _ end: Double) -> Geometry {
            let pts = coords
            guard pts.count >= 2 else { return self }
            var out: [P2] = []
            var at = 0.0
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                let l = simd_length(b - a)
                let s0 = at, s1 = at + l
                if s1 >= start && s0 <= end && l > 0 {
                    let t0 = max(0, (start - s0) / l), t1 = min(1, (end - s0) / l)
                    let p0 = a + (b - a) * t0, p1 = a + (b - a) * t1
                    if out.isEmpty || out.last! != p0 { out.append(p0) }
                    if out.last! != p1 { out.append(p1) }
                }
                at = s1
            }
            return out.count >= 2 ? .lineString(out) : .point(out.first ?? pts[0])
        }
    }

    /// Twice the signed area of a ring: positive when counter-clockwise.
    static func signedArea(_ r: [P2]) -> Double {
        guard r.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<r.count {
            let a = r[i], b = r[(i + 1) % r.count]
            s += a.x * b.y - a.y * b.x
        }
        return s
    }

    /// A geometry prepared for many tests against it.
    public final class Prepared {
        let geometry: Geometry
        let ptr: OpaquePointer

        public init(_ g: Geometry) {
            geometry = g
            ptr = GEOSPrepare_r(ctx, g.ptr)
        }

        deinit { GEOSPreparedGeom_destroy_r(ctx, ptr) }

        public func contains(_ o: Geometry) -> Bool {
            return GEOSPreparedContains_r(ctx, ptr, o.ptr) == 1
        }

        public func contains(_ p: P2) -> Bool { contains(.point(p)) }

        public func intersects(_ o: Geometry) -> Bool {
            return GEOSPreparedIntersects_r(ctx, ptr, o.ptr) == 1
        }
    }

    /// An STR tree over geometries, as shapely's STRtree: `query` gives the
    /// indices whose envelopes meet a geometry's, `nearest` the index of the
    /// nearest geometry.
    public final class STRtree {
        let tree: OpaquePointer
        let items: [Geometry]
        var index: [OpaquePointer: Int] = [:]

        public init(_ items: [Geometry]) {
            self.items = items
            tree = GEOSSTRtree_create_r(ctx, 10)
            for (i, g) in items.enumerated() {
                index[g.ptr] = i
                GEOSSTRtree_insert_r(ctx, tree, g.ptr, UnsafeMutableRawPointer(g.ptr))
            }
        }

        deinit { GEOSSTRtree_destroy_r(ctx, tree) }

        public func query(_ g: Geometry) -> [Int] {
            final class Box { var found: [Int] = []; var index: [OpaquePointer: Int] = [:] }
            let box = Box()
            box.index = index
            let u = Unmanaged.passRetained(box)
            GEOSSTRtree_query_r(ctx, tree, g.ptr, { item, data in
                let b = Unmanaged<AnyObject>.fromOpaque(data!).takeUnretainedValue() as! Box
                if let item, let i = b.index[OpaquePointer(item)] { b.found.append(i) }
            }, u.toOpaque())
            u.release()
            return box.found.sorted()
        }

        public func nearest(_ g: Geometry) -> Int? {
            guard !items.isEmpty, let p = GEOSSTRtree_nearest_r(ctx, tree, g.ptr) else { return nil }
            return index[p]
        }
    }
}

/// What the replay reads of the old wrapper's geometries besides its API:
/// recorded WKB in and out, and the grid of the precision model GEOS keeps
/// with a geometry (it decides how later operations node it).
extension GEOSWrapper.Geometry {
    static func read(wkb: [UInt8]) -> GEOSWrapper.Geometry {
        let ctx = GEOSWrapper.ctx
        let reader = GEOSWKBReader_create_r(ctx)
        defer { GEOSWKBReader_destroy_r(ctx, reader) }
        return GEOSWrapper.Geometry(owning: GEOSWKBReader_read_r(ctx, reader, wkb, wkb.count)!)
    }

    /// Its WKB: two dimensions, little-endian, as the recording keeps it.
    var wkb: [UInt8] {
        let ctx = GEOSWrapper.ctx
        let writer = GEOSWKBWriter_create_r(ctx)
        defer { GEOSWKBWriter_destroy_r(ctx, writer) }
        GEOSWKBWriter_setOutputDimension_r(ctx, writer, 2)
        GEOSWKBWriter_setByteOrder_r(ctx, writer, 1)
        var size = 0
        guard let p = GEOSWKBWriter_write_r(ctx, writer, ptr, &size) else { return [] }
        defer { GEOSFree_r(ctx, p) }
        return Array(UnsafeBufferPointer(start: p, count: size))
    }

    /// The grid size of its precision model (0 when floating), and of each
    /// member's in turn, depth first.
    var grids: [Double] {
        let ctx = GEOSWrapper.ctx
        func walk(_ g: OpaquePointer, _ out: inout [Double]) {
            out.append(GEOSGeom_getPrecision_r(ctx, g))
            let t = GEOSGeomTypeId_r(ctx, g)
            guard t >= 4 else { return }
            for i in 0..<GEOSGetNumGeometries_r(ctx, g) { walk(GEOSGetGeometryN_r(ctx, g, i)!, &out) }
        }
        var out: [Double] = []
        walk(ptr, &out)
        return out
    }
}
