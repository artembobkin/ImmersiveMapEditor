import Foundation
import geos

/// GEOS as an engine of the JTS XML tests: each JTS operation mapped to the
/// GEOS function that does the same (JTS's old overlay names to GEOS's
/// overlay, which is OverlayNG; the `SR` overlays to the `Prec` ones with the
/// grid of the scale). Run first, to check the runner: what GEOS passes is
/// recorded in `GEOSBaseline`.
struct GEOSEngine: JTSTestEngine {
    let oracle: GEOSOracle

    func read(_ wkt: String, scale: Double?) throws -> GEOSGeom {
        // As JTS's WKTOrWKBReader: hexadecimal text is WKB.
        let hex = Array(wkt.utf8)
        let isHex = !hex.isEmpty && hex.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        guard let g = isHex ? oracle.read(hex: wkt) : oracle.read(wkt: wkt) else { throw JTSEngineError("unreadable: \(oracle.takeError() ?? wkt)") }
        guard let scale else { return g }
        // JTS's WKTReader makes every coordinate precise to the model.
        let precise = { (v: Double) in (v * scale + 0.5).rounded(.down) / scale }
        guard let p = oracle.transformed(g, { (precise($0), precise($1)) }) else { throw JTSEngineError("transform failed") }
        return p
    }

    func describe(_ g: GEOSGeom) -> String { g.wkt }

    func equal(_ actual: GEOSGeom, _ expected: GEOSGeom, tolerance: Double) -> Bool {
        let a = actual.normalized, e = expected.normalized
        return GEOSEqualsExact_r(oracle.handle, a.ptr, e.ptr, tolerance) == 1
    }

    func bufferMatch(_ actual: GEOSGeom, _ expected: GEOSGeom, distance: Double) -> Bool {
        if actual.isEmpty && expected.isEmpty { return true }
        guard let diff = actual.binary(expected, GEOSSymDifference_r), let areaDiff = diff.area, let area = expected.area
        else { return false }
        if areaDiff > 0 {
            let frac = area > 0 ? areaDiff / area : .infinity
            if !(frac < 1e-3) { return false }
        }
        guard let ab = actual.unary(GEOSBoundary_r), let eb = expected.unary(GEOSBoundary_r) else { return false }
        // GEOS has no oriented Hausdorff distance: the symmetric one is at
        // least as large, so this is the stricter check.
        var d = 0.0
        guard GEOSHausdorffDistanceDensify_r(oracle.handle, ab.ptr, eb.ptr, 0.25, &d) == 1 else { return false }
        return d <= max(abs(distance) / 100, 1e-8)
    }

    func evaluate(_ t: JTSTestFile.Test, target g: GEOSGeom, a: GEOSGeom?, b: GEOSGeom?,
                  file: JTSTestFile) throws -> JTSValue<GEOSGeom>? {
        func arg(_ i: Int) throws -> String {
            guard i < t.arguments.count else { throw JTSEngineError("missing argument \(i + 2)") }
            return t.arguments[i]
        }
        func geometry(_ i: Int) throws -> GEOSGeom {
            switch try arg(i).uppercased() {
            case "A": if let a { return a }
            case "B": if let b { return b }
            default: break
            }
            throw JTSEngineError("argument \(i + 2) is not a geometry")
        }
        func number(_ i: Int) throws -> Double {
            guard let d = Double(try arg(i)) else { throw JTSEngineError("argument \(i + 2) is not a number") }
            return d
        }
        func result(_ r: GEOSGeom?) throws -> JTSValue<GEOSGeom> {
            guard let r else { throw JTSEngineError(oracle.takeError() ?? "GEOS failed") }
            return .geometry(r)
        }
        func truth(_ r: Bool?) throws -> JTSValue<GEOSGeom> {
            guard let r else { throw JTSEngineError(oracle.takeError() ?? "GEOS failed") }
            return .boolean(r)
        }
        func value(_ r: Double?) throws -> JTSValue<GEOSGeom> {
            guard let r else { throw JTSEngineError(oracle.takeError() ?? "GEOS failed") }
            return .number(r)
        }
        let prepared = file.geometryOperation?.hasSuffix("PreparedGeometryOperation") == true
        let grid = file.fixedScale.map { 1 / $0 }
        func overlay(_ f: (OpaquePointer?, OpaquePointer?, OpaquePointer?) -> OpaquePointer?,
                     _ fp: (OpaquePointer?, OpaquePointer?, OpaquePointer?, Double) -> OpaquePointer?) throws -> JTSValue<GEOSGeom> {
            if t.arguments.isEmpty { return try result(g.unaryUnion) }
            let o = try geometry(0)
            if let grid { return try result(g.binary(o, fp, grid)) }
            return try result(g.binary(o, f))
        }
        switch t.operation.lowercased() {
        case "getcentroid": return try result(g.unary(GEOSGetCentroid_r))
        case "getinteriorpoint": return try result(g.unary(GEOSPointOnSurface_r))
        case "convexhull": return try result(g.unary(GEOSConvexHull_r))
        case "getboundary": return try result(g.unary(GEOSBoundary_r))
        case "isvalid": return try truth(g.predicate(GEOSisValid_r))
        case "issimple": return try truth(g.predicate(GEOSisSimple_r))
        case "buffer":
            let quadrantSegments = t.arguments.count > 1 ? Int32(try number(1)) : 8
            return try result(oracle.wrap(GEOSBuffer_r(oracle.handle, g.ptr, try number(0), quadrantSegments)))
        case "buffermitredjoin":
            return try result(oracle.wrap(GEOSBufferWithStyle_r(oracle.handle, g.ptr, try number(0), 8, 1, 2, 5)))
        case "densify": return try result(g.unary(GEOSDensify_r, try number(0)))
        case "simplifydp": return try result(g.unary(GEOSSimplify_r, try number(0)))
        case "simplifytp": return try result(g.unary(GEOSTopologyPreserveSimplify_r, try number(0)))
        case "minclearance":
            var d = 0.0
            guard GEOSMinimumClearance_r(oracle.handle, g.ptr, &d) == 0 else { throw JTSEngineError("GEOS failed") }
            return .number(d)
        case "minclearanceline": return try result(g.unary(GEOSMinimumClearanceLine_r))
        case "polygonize":
            var p: [OpaquePointer?] = [g.ptr]
            return try result(oracle.wrap(GEOSPolygonize_r(oracle.handle, &p, 1)))
        case "intersection", "intersectionng": return try overlay(GEOSIntersection_r, GEOSIntersectionPrec_r)
        case "union", "unionng": return try overlay(GEOSUnion_r, GEOSUnionPrec_r)
        case "difference", "differenceng": return try overlay(GEOSDifference_r, GEOSDifferencePrec_r)
        case "symdifference", "symdifferenceng": return try overlay(GEOSSymDifference_r, GEOSSymDifferencePrec_r)
        case "intersectionsr": return try result(g.binary(try geometry(0), GEOSIntersectionPrec_r, 1 / (try number(1))))
        case "unionsr": return try result(g.binary(try geometry(0), GEOSUnionPrec_r, 1 / (try number(1))))
        case "differencesr": return try result(g.binary(try geometry(0), GEOSDifferencePrec_r, 1 / (try number(1))))
        case "symdifferencesr": return try result(g.binary(try geometry(0), GEOSSymDifferencePrec_r, 1 / (try number(1))))
        case "unionarea": return try value(g.unaryUnion?.area)
        case "unionlength": return try value(g.unaryUnion?.length)
        case "distance": return try value(g.measure(try geometry(0), GEOSDistance_r))
        case "iswithindistance": return try truth(g.predicate(try geometry(0), GEOSDistanceWithin_r, try number(1)))
        case "equalsexact":
            let tolerance = t.arguments.count > 1 ? try number(1) : 0
            return try truth(g.predicate(try geometry(0), GEOSEqualsExact_r, tolerance))
        case "equalsnorm": return try truth(g.normalized.predicate(try geometry(0).normalized, GEOSEqualsExact_r, 0))
        case "equalstopo": return try truth(g.predicate(try geometry(0), GEOSEquals_r))
        case "relate":
            let r = GEOSRelatePattern_r(oracle.handle, g.ptr, try geometry(0).ptr, try arg(1))
            return try truth(r == 2 ? nil : r == 1)
        case "overlayareatest": return try truth(overlayAreaTest(g, try geometry(0)))
        default: break
        }
        let other = try geometry(0)
        if prepared {
            let p = g.prepared()
            switch t.operation.lowercased() {
            case "intersects": return try truth(p.predicate(other, GEOSPreparedIntersects_r))
            case "contains": return try truth(p.predicate(other, GEOSPreparedContains_r))
            case "containsproperly": return try truth(p.predicate(other, GEOSPreparedContainsProperly_r))
            case "covers": return try truth(p.predicate(other, GEOSPreparedCovers_r))
            default: break
            }
        }
        switch t.operation.lowercased() {
        case "intersects": return try truth(g.predicate(other, GEOSIntersects_r))
        case "contains": return try truth(g.predicate(other, GEOSContains_r))
        case "covers": return try truth(g.predicate(other, GEOSCovers_r))
        case "coveredby": return try truth(g.predicate(other, GEOSCoveredBy_r))
        case "within": return try truth(g.predicate(other, GEOSWithin_r))
        case "touches": return try truth(g.predicate(other, GEOSTouches_r))
        case "overlaps": return try truth(g.predicate(other, GEOSOverlaps_r))
        case "disjoint": return try truth(g.predicate(other, GEOSDisjoint_r))
        case "crosses": return try truth(g.predicate(other, GEOSCrosses_r))
        default: return nil
        }
    }

    /// JTS's `TestCaseGeometryFunctions.overlayAreaTest`: the areas of the
    /// overlays agree with each other within 1e-6 of the inputs' areas.
    func overlayAreaTest(_ a: GEOSGeom, _ b: GEOSGeom) -> Bool? {
        guard let areaA = a.area, let areaB = b.area else { return nil }
        if areaA == 0 || areaB == 0 { return true }
        guard let u = a.binary(b, GEOSUnion_r)?.area, let i = a.binary(b, GEOSIntersection_r)?.area,
              let dab = a.binary(b, GEOSDifference_r)?.area, let dba = b.binary(a, GEOSDifference_r)?.area,
              let sd = a.binary(b, GEOSSymDifference_r)?.area else { return nil }
        let deltas = [abs(areaA - i - dab), abs(areaB - i - dba), abs(dab + dba - sd), abs(i + sd - u), abs(u - i - dab - dba)]
        var maxDelta = 0.0
        for d in deltas where d > maxDelta { maxDelta = d }
        return maxDelta / (areaA + areaB) < 1e-6
    }
}
