import Topology
import simd

/// A point in plan.
public typealias P2 = SIMD2<Double>

/// A planar geometry: points, lines, polygons and their collections, with
/// the operations the build uses, named as shapely names them (the Python
/// build this ports was written against shapely).
///
/// It stands on `Topology`, the Swift port of JTS, and behaves exactly as
/// the wrapper of GEOS 3.13's C API it replaces did (Docs/PortingGoal.md,
/// phase 8): every operation is the one the C API ran, with its defaults,
/// and a failure gives what the C API gave then (`Failure`): an operation
/// GEOS cannot do (a topology error) gives an empty geometry.
public final class Geometry: CustomStringConvertible {
    /// The port's geometry. Never changed once wrapped: the operations make
    /// new ones, and the parts of a collection are copies.
    let geometry: Topology.Geometry
    /// Its id in the recording (`Recorder`), 0 until it is written.
    var recordID: UInt32 = 0

    init(_ geometry: Topology.Geometry) {
        self.geometry = geometry
    }

    /// The factory of the geometries made here: floating precision, as the
    /// GEOS context's was.
    static let factory = GeometryFactory.default

    /// The result of an operation, or `.empty` where it fails.
    static func make(_ body: () throws -> Topology.Geometry) -> Geometry {
        Failure.attempt(nil) { Geometry(try body()) } ?? .empty
    }

    public enum Kind: Int32 {
        case point = 0, lineString, linearRing, polygon, multiPoint, multiLineString, multiPolygon, collection
    }

    public enum Cap: Int32 { case round = 1, flat = 2, square = 3 }
    public enum Join: Int32 { case round = 1, mitre = 2, bevel = 3 }

    // MARK: Making

    public static var empty: Geometry {
        Recorder.shared?.count("empty")
        return Geometry(factory.createGeometryCollection())
    }

    static func coordinates(_ pts: [P2]) -> [Coordinate] { pts.map { Coordinate($0.x, $0.y) } }

    public static func point(_ x: Double, _ y: Double) -> Geometry {
        Recorder.shared?.count("point")
        return Geometry(factory.createPoint(Coordinate(x, y)))
    }

    public static func point(_ p: P2) -> Geometry { point(p.x, p.y) }

    public static func lineString(_ pts: [P2]) -> Geometry {
        Recorder.shared?.count("lineString")
        guard pts.count >= 2 else { return Geometry(factory.createLineString()) }
        return Geometry(factory.createLineString(coordinates(pts)))
    }

    /// A closed ring of the points, or nil where GEOS refused one: too few
    /// points, or not closed after closing it (a NaN first point).
    static func ring(_ pts: [P2]) -> LinearRing? {
        guard pts.count >= 3 else { return nil }
        var closed = pts
        if closed.first! != closed.last! { closed.append(closed[0]) }
        guard closed.count >= 4 else { return nil }
        return try? factory.createLinearRingChecked(coordinates(closed))
    }

    /// A polygon of an outer ring and holes, open or closed. Without a shell
    /// it is an empty polygon. A hole that cannot be a ring (too few points,
    /// a NaN first point) makes no polygon at all, an empty geometry: the
    /// wrapper of GEOS gave GEOS a null hole there, which it refused.
    public static func polygon(_ shell: [P2], holes: [[P2]] = []) -> Geometry {
        Recorder.shared?.count("polygon")
        guard let s = ring(shell) else { return Geometry(factory.createPolygon()) }
        var rings: [LinearRing] = []
        for h in holes {
            guard let r = ring(h) else { return .empty }
            rings.append(r)
        }
        return Geometry(factory.createPolygon(s, rings))
    }

    public static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Geometry {
        polygon([P2(x0, y0), P2(x1, y0), P2(x1, y1), P2(x0, y1)])
    }

    /// A collection of copies of the geometries: a multi-geometry when they
    /// are all of one kind, else a geometry collection. A multi-geometry
    /// given gives its parts (empty ones too), an empty geometry nothing.
    public static func collection(_ parts: [Geometry]) -> Geometry {
        Recorder.shared?.count("collection")
        var flat: [Topology.Geometry] = []
        var kinds = Set<Kind>()
        for p in parts where !p.isEmpty {
            if p.isMulti {
                for i in 0..<p.geometry.getNumGeometries() {
                    let m = p.geometry.getGeometryN(i)
                    flat.append(m.copy())
                    kinds.insert(Geometry.kind(of: m))
                }
            } else {
                flat.append(p.geometry.copy())
                kinds.insert(p.kind)
            }
        }
        guard !flat.isEmpty else { return .empty }
        if kinds == [.polygon] { return Geometry(factory.createMultiPolygon(flat.map { $0 as! Polygon })) }
        if kinds == [.lineString] { return Geometry(factory.createMultiLineString(flat.map { $0 as! LineString })) }
        if kinds == [.point] { return Geometry(factory.createMultiPoint(flat.map { $0 as! Point })) }
        return Geometry(factory.createGeometryCollection(flat))
    }

    // MARK: Reading

    static func kind(of g: Topology.Geometry) -> Kind {
        switch g {
        case is Point: return .point
        case is LinearRing: return .linearRing
        case is LineString: return .lineString
        case is Polygon: return .polygon
        case is MultiPoint: return .multiPoint
        case is MultiLineString: return .multiLineString
        case is MultiPolygon: return .multiPolygon
        default: return .collection
        }
    }

    public var kind: Kind { Geometry.kind(of: geometry) }
    public var isEmpty: Bool { geometry.isEmpty() }
    public var isValid: Bool {
        Recorder.shared?.call("isValid", [self])
        return Failure.attempt(false) { try geometry.isValid() }
    }
    public var isMulti: Bool { geometry is GeometryCollection }

    public var area: Double {
        Recorder.shared?.call("area", [self])
        return Failure.attempt(0) { geometry.getArea() }
    }

    public var length: Double {
        Recorder.shared?.call("length", [self])
        return Failure.attempt(0) { geometry.getLength() }
    }

    /// (x0, y0, x1, y1).
    public var bounds: (Double, Double, Double, Double) {
        Recorder.shared?.call("bounds", [self])
        guard !isEmpty else { return (0, 0, 0, 0) }
        let e = geometry.getEnvelopeInternal()
        return (e.minX, e.minY, e.maxX, e.maxY)
    }

    /// A point's coordinates (0 for an empty point or another geometry).
    public var x: Double { (geometry as? Point)?.getCoordinate()?.x ?? 0 }
    public var y: Double { (geometry as? Point)?.getCoordinate()?.y ?? 0 }

    public var xy: P2 { P2(x, y) }

    /// The coordinates of a point, line or ring.
    public var coords: [P2] {
        switch geometry {
        case let p as Point: return Geometry.points(p.coordinates)
        case let l as LineString: return Geometry.points(l.points)
        default: return []
        }
    }

    static func points(_ cs: [Coordinate]) -> [P2] { cs.map { P2($0.x, $0.y) } }

    /// A polygon's outer ring (closed) and holes.
    public var exterior: [P2] {
        guard let p = geometry as? Polygon else { return [] }
        return Geometry.points(p.shell.points)
    }

    public var interiors: [[P2]] {
        guard let p = geometry as? Polygon else { return [] }
        return p.holes.map { Geometry.points($0.points) }
    }

    /// The parts of a collection (copies); a single geometry is its own.
    public var parts: [Geometry] {
        guard isMulti else { return [self] }
        return (0..<geometry.getNumGeometries()).map { Geometry(geometry.getGeometryN($0).copy()) }
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
        Recorder.shared?.call("centroid", [self])
        return Geometry.make { geometry.getCentroid() }
    }

    public var representativePoint: Geometry {
        Recorder.shared?.call("representativePoint", [self])
        return Geometry.make { geometry.getInteriorPoint() }
    }

    /// Well-known text, three decimals (GEOS's writer at rounding precision 3).
    public var description: String {
        Recorder.shared?.call("description", [self])
        return WKTWriter(roundingPrecision: 3).write(geometry)
    }
}

/// What GEOS's C API did with an exception: it caught it and returned the
/// function's failure value (NULL, 0, 2 for a predicate). Here an operation
/// fails when it throws, or when a NaN or infinite coordinate reached the
/// orientation test inside it (`NonFinite`, where GEOS throws), so the C
/// API's catch is the scope of every operation.
enum Failure {
    static func attempt<T>(_ failure: T, _ body: () throws -> T) -> T {
        (try? NonFinite.scope(body)) ?? failure
    }
}
