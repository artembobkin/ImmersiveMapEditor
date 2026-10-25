import Foundation
import Topology

/// The port as an engine of the JTS XML tests: the operations ported so far,
/// nil (unsupported) for the rest. Grows phase by phase.
///
/// Geometries are read as GEOS's engine reads them: coordinates made precise
/// by the file's model, the geometry then of floating precision (GEOS has no
/// fixed factory here). The overlays at a fixed precision are OverlayNG with
/// snap rounding at the model GEOS's `Prec` functions make from the grid
/// size (`1 / (1 / scale)`), the others robust OverlayNG.
struct TopologyEngine: JTSTestEngine {
    func read(_ wkt: String, scale: Double?) throws -> Topology.Geometry {
        let factory = scale.map { GeometryFactory(precisionModel: PrecisionModel(scale: $0)) } ?? .default
        let hex = Array(wkt.utf8)
        let isHex = !hex.isEmpty && hex.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        let g: Topology.Geometry
        if isHex {
            var bytes: [UInt8] = []
            var i = hex.startIndex
            while i + 1 < hex.endIndex {
                bytes.append(UInt8(String(decoding: hex[i...(i + 1)], as: UTF8.self), radix: 16)!)
                i += 2
            }
            g = try WKBReader(factory).read(bytes)
        } else {
            g = try WKTReader(factory).read(wkt)
        }
        return scale == nil ? g : GeometryFactory.default.createGeometry(g)
    }

    func describe(_ g: Topology.Geometry) -> String { "\(g)" }

    func equal(_ actual: Topology.Geometry, _ expected: Topology.Geometry, tolerance: Double) -> Bool {
        actual.norm().equalsExact(expected.norm(), tolerance: tolerance)
    }

    /// JTS's `BufferResultMatcher` as GEOS's engine ran it: the area of the
    /// symmetric difference, then the Hausdorff distance of the boundaries
    /// (`DiscreteHausdorffDistance`, densified by a quarter), both ways (GEOS
    /// had no oriented one, so the runner took the symmetric distance, the
    /// stricter check).
    func bufferMatch(_ actual: Topology.Geometry, _ expected: Topology.Geometry, distance: Double) -> Bool {
        if actual.isEmpty() && expected.isEmpty() { return true }
        guard let diff = try? actual.symDifference(expected) else { return false }
        let areaDiff = diff.getArea(), area = expected.getArea()
        if areaDiff > 0 {
            let frac = area > 0 ? areaDiff / area : .infinity
            if !(frac < 1e-3) { return false }
        }
        let d = DiscreteHausdorffDistance.distance(actual.getBoundary(), expected.getBoundary(), densifyFrac: 0.25)
        return d <= max(abs(distance) / 100, 1e-8)
    }


    /// The operations of the port, by the JTS test names.
    static let supported: Set<String> = [
        "getcentroid", "getinteriorpoint", "convexhull", "getboundary", "equalsexact", "equalsnorm",
        "intersection", "intersectionng", "union", "unionng", "difference", "differenceng", "symdifference", "symdifferenceng",
        "intersectionsr", "unionsr", "differencesr", "symdifferencesr", "unionarea", "unionlength", "overlayareatest",
        "intersects", "contains", "within", "covers", "coveredby", "touches", "crosses", "overlaps", "disjoint",
        "equalstopo", "relate", "containsproperly", "distance", "iswithindistance", "buffer", "buffermitredjoin",
        "isvalid", "polygonize", "simplifytp",
    ]

    func evaluate(_ t: JTSTestFile.Test, target g: Topology.Geometry, a: Topology.Geometry?, b: Topology.Geometry?,
                  file: JTSTestFile) throws -> JTSValue<Topology.Geometry>? {
        func geometry(_ i: Int) throws -> Topology.Geometry {
            guard i < t.arguments.count else { throw JTSEngineError("missing argument \(i + 2)") }
            switch t.arguments[i].uppercased() {
            case "A": if let a { return a }
            case "B": if let b { return b }
            default: break
            }
            throw JTSEngineError("argument \(i + 2) is not a geometry")
        }
        func number(_ i: Int) throws -> Double {
            guard i < t.arguments.count, let d = Double(t.arguments[i]) else { throw JTSEngineError("argument \(i + 2) is not a number") }
            return d
        }
        // GEOS's Prec functions take a grid size and make the model of 1 / it.
        func gridModel(_ scale: Double) -> PrecisionModel { PrecisionModel(scale: 1.0 / (1.0 / scale)) }
        func overlay(_ code: Int, _ floating: (Topology.Geometry, Topology.Geometry) throws -> Topology.Geometry) throws -> JTSValue<Topology.Geometry> {
            if t.arguments.isEmpty { return .geometry(try g.union()) }
            let o = try geometry(0)
            if let scale = file.fixedScale { return .geometry(try OverlayNG.overlay(g, o, code, gridModel(scale))) }
            return .geometry(try floating(g, o))
        }
        func snapRounded(_ code: Int) throws -> JTSValue<Topology.Geometry> {
            .geometry(try OverlayNG.overlay(g, try geometry(0), code, gridModel(try number(1))))
        }
        switch t.operation.lowercased() {
        case "getcentroid": return .geometry(g.getCentroid())
        case "isvalid": return .boolean(try g.isValid())
        case "polygonize": return .geometry(try Topology.Geometry.polygonize([g]))
        case "simplifytp": return .geometry(try g.topologyPreserveSimplify(try number(0)))
        case "getinteriorpoint": return .geometry(g.getInteriorPoint())
        case "convexhull": return .geometry(g.convexHull())
        case "getboundary":
            // JTS and GEOS refuse the boundary of a collection: so does the engine.
            if type(of: g) == GeometryCollection.self { throw JTSEngineError("Operation does not support GeometryCollection arguments") }
            return .geometry(g.getBoundary())
        case "equalsexact":
            let tolerance = t.arguments.count > 1 ? Double(t.arguments[1]) ?? 0 : 0
            return .boolean(g.equalsExact(try geometry(0), tolerance: tolerance))
        case "equalsnorm": return .boolean(g.equalsNorm(try geometry(0)))
        case "intersection", "intersectionng": return try overlay(OverlayNG.intersection) { try $0.intersection($1) }
        case "union", "unionng": return try overlay(OverlayNG.union) { try $0.union($1) }
        case "difference", "differenceng": return try overlay(OverlayNG.difference) { try $0.difference($1) }
        case "symdifference", "symdifferenceng": return try overlay(OverlayNG.symDifference) { try $0.symDifference($1) }
        case "intersectionsr": return try snapRounded(OverlayNG.intersection)
        case "unionsr": return try snapRounded(OverlayNG.union)
        case "differencesr": return try snapRounded(OverlayNG.difference)
        case "symdifferencesr": return try snapRounded(OverlayNG.symDifference)
        case "unionarea": return .number(try g.union().getArea())
        case "unionlength": return .number(try g.union().getLength())
        case "overlayareatest": return .boolean(try overlayAreaTest(g, try geometry(0)))
        case "distance": return .number(g.distance(try geometry(0)))
        case "iswithindistance": return .boolean(g.isWithinDistance(try geometry(0), try number(1)))
        case "buffer":
            // GEOSBuffer: the default style, the segments a quadrant given.
            let quadSegs = t.arguments.count > 1 ? Int(try number(1)) : BufferParameters.defaultQuadrantSegments
            return .geometry(try g.buffer(try number(0), quadSegs: quadSegs))
        case "buffermitredjoin":
            return .geometry(try g.buffer(try number(0), joinStyle: BufferParameters.joinMitre))
        case "relate":
            guard t.arguments.count > 1 else { throw JTSEngineError("relate without a pattern") }
            return .boolean(try g.relate(try geometry(0), t.arguments[1]))
        default: break
        }
        let predicates: Set<String> = ["intersects", "contains", "within", "covers", "coveredby", "touches", "crosses",
                                       "overlaps", "disjoint", "equalstopo", "containsproperly"]
        guard predicates.contains(t.operation.lowercased()) else { return nil }
        let other = try geometry(0)
        if file.geometryOperation?.hasSuffix("PreparedGeometryOperation") == true {
            let p = PreparedGeometryFactory.prepare(g)
            switch t.operation.lowercased() {
            case "intersects": return .boolean(try p.intersects(other))
            case "contains": return .boolean(try p.contains(other))
            case "containsproperly": return .boolean(try p.containsProperly(other))
            case "covers": return .boolean(try p.covers(other))
            default: break
            }
        }
        switch t.operation.lowercased() {
        case "intersects": return .boolean(try g.intersects(other))
        case "contains": return .boolean(try g.contains(other))
        case "within": return .boolean(try g.within(other))
        case "covers": return .boolean(try g.covers(other))
        case "coveredby": return .boolean(try g.coveredBy(other))
        case "touches": return .boolean(try g.touches(other))
        case "crosses": return .boolean(try g.crosses(other))
        case "overlaps": return .boolean(try g.overlaps(other))
        case "disjoint": return .boolean(try g.disjoint(other))
        case "equalstopo": return .boolean(try g.equalsTopo(other))
        default: return nil
        }
    }

    /// JTS's `TestCaseGeometryFunctions.overlayAreaTest`, as GEOS's engine ran it.
    func overlayAreaTest(_ a: Topology.Geometry, _ b: Topology.Geometry) throws -> Bool {
        let areaA = a.getArea(), areaB = b.getArea()
        if areaA == 0 || areaB == 0 { return true }
        let u = try a.union(b).getArea(), i = try a.intersection(b).getArea()
        let dab = try a.difference(b).getArea(), dba = try b.difference(a).getArea(), sd = try a.symDifference(b).getArea()
        let deltas = [abs(areaA - i - dab), abs(areaB - i - dba), abs(dab + dba - sd), abs(i + sd - u), abs(u - i - dab - dba)]
        var maxDelta = 0.0
        for d in deltas where d > maxDelta { maxDelta = d }
        return maxDelta / (areaA + areaB) < 1e-6
    }
}
