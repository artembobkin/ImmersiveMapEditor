import geos

/// The shapes of GEOS's C API calls, so a test names the GEOS function it
/// compares with: `g.unary(GEOSGetCentroid_r)`, `a.predicate(b, GEOSIntersects_r)`.
/// A nil result is GEOS's failure (an exception in C++), its message in
/// `GEOSOracle.takeError`.
extension GEOSGeom {
    typealias Handle = GEOSContextHandle_t

    func unary(_ f: (Handle?, OpaquePointer?) -> OpaquePointer?) -> GEOSGeom? {
        oracle.wrap(f(handle, ptr))
    }

    func unary(_ f: (Handle?, OpaquePointer?, Double) -> OpaquePointer?, _ d: Double) -> GEOSGeom? {
        oracle.wrap(f(handle, ptr, d))
    }

    func unary(_ f: (Handle?, OpaquePointer?, Double, Int32) -> OpaquePointer?, _ d: Double, _ n: Int32) -> GEOSGeom? {
        oracle.wrap(f(handle, ptr, d, n))
    }

    func binary(_ o: GEOSGeom, _ f: (Handle?, OpaquePointer?, OpaquePointer?) -> OpaquePointer?) -> GEOSGeom? {
        oracle.wrap(f(handle, ptr, o.ptr))
    }

    func binary(_ o: GEOSGeom, _ f: (Handle?, OpaquePointer?, OpaquePointer?, Double) -> OpaquePointer?, _ d: Double) -> GEOSGeom? {
        oracle.wrap(f(handle, ptr, o.ptr, d))
    }

    func predicate(_ f: (Handle?, OpaquePointer?) -> Int8) -> Bool? {
        let r = f(handle, ptr)
        return r == 2 ? nil : r == 1
    }

    func predicate(_ o: GEOSGeom, _ f: (Handle?, OpaquePointer?, OpaquePointer?) -> Int8) -> Bool? {
        let r = f(handle, ptr, o.ptr)
        return r == 2 ? nil : r == 1
    }

    func predicate(_ o: GEOSGeom, _ f: (Handle?, OpaquePointer?, OpaquePointer?, Double) -> Int8, _ d: Double) -> Bool? {
        let r = f(handle, ptr, o.ptr, d)
        return r == 2 ? nil : r == 1
    }

    func measure(_ f: (Handle?, OpaquePointer?, UnsafeMutablePointer<Double>?) -> Int32) -> Double? {
        var d = 0.0
        return f(handle, ptr, &d) == 0 ? nil : d
    }

    func measure(_ o: GEOSGeom, _ f: (Handle?, OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<Double>?) -> Int32) -> Double? {
        var d = 0.0
        return f(handle, ptr, o.ptr, &d) == 0 ? nil : d
    }

    /// The prepared form of this geometry, for many predicates against it.
    func prepared() -> GEOSPrepared { GEOSPrepared(self) }

    /// `GEOSUnaryUnion` of this geometry.
    var unaryUnion: GEOSGeom? { unary(GEOSUnaryUnion_r) }

    var area: Double? { measure(GEOSArea_r) }
    var length: Double? { measure(GEOSLength_r) }
}

/// A prepared geometry of GEOS, with the geometry it was made from kept.
final class GEOSPrepared {
    let base: GEOSGeom
    let ptr: OpaquePointer

    init(_ g: GEOSGeom) {
        base = g
        ptr = GEOSPrepare_r(g.handle, g.ptr)
    }

    deinit { GEOSPreparedGeom_destroy_r(base.handle, ptr) }

    func predicate(_ o: GEOSGeom, _ f: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8) -> Bool? {
        let r = f(base.handle, ptr, o.ptr)
        return r == 2 ? nil : r == 1
    }
}
