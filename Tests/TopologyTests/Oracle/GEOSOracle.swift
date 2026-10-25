import Foundation
import geos
import Topology

/// GEOS 3.13 as the test oracle of the port (Docs/PortingGoal.md, "Parity"):
/// a context of its own, geometries read from WKT or WKB, and the operations
/// the parity tests compare with `Topology`. Test code only: GEOS is never
/// ported, only called through its C API.
///
/// One oracle per test: a GEOS context is used by one thread at a time, and
/// swift-testing runs tests in parallel.
final class GEOSOracle {
    let handle: GEOSContextHandle_t
    /// The last error GEOS reported, cleared by `takeError`.
    private let errors = ErrorBox()

    final class ErrorBox { var message: String? }

    init() {
        handle = GEOS_init_r()!
        GEOSContext_setErrorMessageHandler_r(handle, { message, data in
            let box = Unmanaged<ErrorBox>.fromOpaque(data!).takeUnretainedValue()
            box.message = message.map { String(cString: $0) }
        }, Unmanaged.passUnretained(errors).toOpaque())
        GEOSContext_setNoticeMessageHandler_r(handle, { _, _ in }, nil)
    }

    deinit { GEOS_finish_r(handle) }

    /// The error GEOS reported since the last call, if any.
    func takeError() -> String? {
        defer { errors.message = nil }
        return errors.message
    }

    // MARK: Reading and writing

    func read(wkt: String) -> GEOSGeom? {
        let reader = GEOSWKTReader_create_r(handle)
        defer { GEOSWKTReader_destroy_r(handle, reader) }
        return wrap(GEOSWKTReader_read_r(handle, reader, wkt))
    }

    func read(wkb: [UInt8]) -> GEOSGeom? {
        let reader = GEOSWKBReader_create_r(handle)
        defer { GEOSWKBReader_destroy_r(handle, reader) }
        return wrap(GEOSWKBReader_read_r(handle, reader, wkb, wkb.count))
    }

    /// WKB written as hexadecimal text.
    func read(hex: String) -> GEOSGeom? {
        let reader = GEOSWKBReader_create_r(handle)
        defer { GEOSWKBReader_destroy_r(handle, reader) }
        let bytes = Array(hex.utf8)
        return wrap(GEOSWKBReader_readHEX_r(handle, reader, bytes, bytes.count))
    }

    /// WKT with every digit a double needs to read back the same.
    func wkt(_ g: GEOSGeom) -> String {
        let writer = GEOSWKTWriter_create_r(handle)
        defer { GEOSWKTWriter_destroy_r(handle, writer) }
        GEOSWKTWriter_setTrim_r(handle, writer, 1)
        GEOSWKTWriter_setRoundingPrecision_r(handle, writer, -1)
        GEOSWKTWriter_setOutputDimension_r(handle, writer, 2)
        guard let s = GEOSWKTWriter_write_r(handle, writer, g.ptr) else { return "?" }
        defer { GEOSFree_r(handle, s) }
        return String(cString: s)
    }

    func wkb(_ g: GEOSGeom) -> [UInt8] {
        let writer = GEOSWKBWriter_create_r(handle)
        defer { GEOSWKBWriter_destroy_r(handle, writer) }
        GEOSWKBWriter_setByteOrder_r(handle, writer, 1)
        var size = 0
        guard let p = GEOSWKBWriter_write_r(handle, writer, g.ptr, &size) else { return [] }
        defer { GEOSFree_r(handle, p) }
        return Array(UnsafeBufferPointer(start: p, count: size))
    }

    /// A geometry GEOS returned, or nil when it failed.
    func wrap(_ p: OpaquePointer?) -> GEOSGeom? {
        p.map { GEOSGeom(ptr: $0, oracle: self) }
    }

    /// A copy in GEOS's normal form (`GEOSNormalize`, JTS `normalize()`).
    func normalized(_ g: GEOSGeom) -> GEOSGeom {
        let c = GEOSGeom_clone_r(handle, g.ptr)!
        GEOSNormalize_r(handle, c)
        return GEOSGeom(ptr: c, oracle: self)
    }

    /// Every coordinate moved by `f`, the structure kept.
    func transformed(_ g: GEOSGeom, _ f: @escaping (Double, Double) -> (Double, Double)) -> GEOSGeom? {
        final class Box { let f: (Double, Double) -> (Double, Double); init(_ f: @escaping (Double, Double) -> (Double, Double)) { self.f = f } }
        let box = Box(f)
        let p = GEOSGeom_transformXY_r(handle, g.ptr, { x, y, data in
            let b = Unmanaged<Box>.fromOpaque(data!).takeUnretainedValue()
            let r = b.f(x!.pointee, y!.pointee)
            x!.pointee = r.0
            y!.pointee = r.1
            return 1
        }, Unmanaged.passUnretained(box).toOpaque())
        return withExtendedLifetime(box) { wrap(p) }
    }

    /// The structure and coordinates of a geometry, to compare bit for bit.
    func shape(_ g: GEOSGeom) -> Shape { shape(g.ptr) }

    func shape(_ p: OpaquePointer) -> Shape {
        let type = GEOSGeomTypeId_r(handle, p)
        switch type {
        case 0, 1, 2:
            return Shape(kind: Shape.Kind(rawValue: Int(type))!, coordinates: coordinates(p))
        case 3:
            var rings: [Shape] = []
            if GEOSisEmpty_r(handle, p) == 0 {
                rings.append(Shape(kind: .linearRing, coordinates: coordinates(GEOSGetExteriorRing_r(handle, p)!)))
                for i in 0..<GEOSGetNumInteriorRings_r(handle, p) {
                    rings.append(Shape(kind: .linearRing, coordinates: coordinates(GEOSGetInteriorRingN_r(handle, p, i)!)))
                }
            }
            return Shape(kind: .polygon, parts: rings)
        default:
            let parts = (0..<GEOSGetNumGeometries_r(handle, p)).map { shape(GEOSGetGeometryN_r(handle, p, $0)!) }
            return Shape(kind: Shape.Kind(rawValue: Int(type)) ?? .geometryCollection, parts: parts)
        }
    }

    func coordinates(_ p: OpaquePointer) -> [Double] {
        guard GEOSisEmpty_r(handle, p) == 0, let seq = GEOSGeom_getCoordSeq_r(handle, p) else { return [] }
        var n: UInt32 = 0
        GEOSCoordSeq_getSize_r(handle, seq, &n)
        var flat = [Double](repeating: 0, count: Int(n) * 2)
        GEOSCoordSeq_copyToBuffer_r(handle, seq, &flat, 0, 0)
        return flat
    }

    /// A geometry of a shape, read back through WKT is lossy, so built
    /// through the coordinate sequences.
    func geometry(_ s: Shape) -> GEOSGeom? { wrap(make(s)) }

    func make(_ s: Shape) -> OpaquePointer? {
        func sequence(_ c: [Double]) -> OpaquePointer { GEOSCoordSeq_copyFromBuffer_r(handle, c, UInt32(c.count / 2), 0, 0)! }
        switch s.kind {
        case .point:
            return s.coordinates.isEmpty ? GEOSGeom_createEmptyPoint_r(handle) : GEOSGeom_createPoint_r(handle, sequence(s.coordinates))
        case .lineString:
            return s.coordinates.isEmpty ? GEOSGeom_createEmptyLineString_r(handle) : GEOSGeom_createLineString_r(handle, sequence(s.coordinates))
        case .linearRing:
            return GEOSGeom_createLinearRing_r(handle, sequence(s.coordinates))
        case .polygon:
            guard let shell = s.parts.first else { return GEOSGeom_createEmptyPolygon_r(handle) }
            var holes: [OpaquePointer?] = s.parts.dropFirst().map { make($0) }
            return GEOSGeom_createPolygon_r(handle, make(shell), &holes, UInt32(holes.count))
        default:
            var parts: [OpaquePointer?] = s.parts.map { make($0) }
            return GEOSGeom_createCollection_r(handle, Int32(s.kind.rawValue), &parts, UInt32(parts.count))
        }
    }
}

/// A geometry GEOS owns, freed with its wrapper.
final class GEOSGeom {
    let ptr: OpaquePointer
    let oracle: GEOSOracle

    init(ptr: OpaquePointer, oracle: GEOSOracle) {
        self.ptr = ptr
        self.oracle = oracle
    }

    deinit { GEOSGeom_destroy_r(oracle.handle, ptr) }

    var handle: GEOSContextHandle_t { oracle.handle }
    var typeID: Int32 { GEOSGeomTypeId_r(handle, ptr) }
    var isEmpty: Bool { GEOSisEmpty_r(handle, ptr) == 1 }
    var numGeometries: Int { Int(GEOSGetNumGeometries_r(handle, ptr)) }

    /// The `n`th part, a copy.
    func geometry(_ n: Int) -> GEOSGeom {
        GEOSGeom(ptr: GEOSGeom_clone_r(handle, GEOSGetGeometryN_r(handle, ptr, Int32(n)))!, oracle: oracle)
    }

    var wkt: String { oracle.wkt(self) }
    var shape: Shape { oracle.shape(self) }
    var normalized: GEOSGeom { oracle.normalized(self) }
}


extension GEOSOracle {
    /// A geometry of the port as a GEOS geometry, exactly.
    func geos(_ g: Topology.Geometry) -> GEOSGeom { geometry(Shape(g))! }

    /// GEOS's normal form of a port's result and of GEOS's, as shapes:
    /// equal when the results are the same geometry, bit for bit.
    func normalizedShapes(_ topology: Topology.Geometry, _ geos: GEOSGeom) -> (Shape, Shape) {
        (normalized(self.geos(topology)).shape, normalized(geos).shape)
    }
}
