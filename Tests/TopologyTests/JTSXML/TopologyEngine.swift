import Foundation
import Topology

/// The port as an engine of the JTS XML tests: the operations ported so far,
/// nil (unsupported) for the rest. Grows phase by phase.
struct TopologyEngine: JTSTestEngine {
    func read(_ wkt: String, scale: Double?) throws -> Topology.Geometry {
        let factory = scale.map { GeometryFactory(precisionModel: PrecisionModel(scale: $0)) } ?? .default
        let hex = Array(wkt.utf8)
        let isHex = !hex.isEmpty && hex.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        if isHex {
            var bytes: [UInt8] = []
            var i = hex.startIndex
            while i + 1 < hex.endIndex {
                bytes.append(UInt8(String(decoding: hex[i...(i + 1)], as: UTF8.self), radix: 16)!)
                i += 2
            }
            return try WKBReader(factory).read(bytes)
        }
        return try WKTReader(factory).read(wkt)
    }

    func describe(_ g: Topology.Geometry) -> String { "\(g)" }

    func equal(_ actual: Topology.Geometry, _ expected: Topology.Geometry, tolerance: Double) -> Bool {
        actual.norm().equalsExact(expected.norm(), tolerance: tolerance)
    }

    func bufferMatch(_ actual: Topology.Geometry, _ expected: Topology.Geometry, distance: Double) -> Bool { false }

    /// The operations of the port, by the JTS test names.
    static let supported: Set<String> = ["getcentroid", "getinteriorpoint", "convexhull", "getboundary", "equalsexact", "equalsnorm"]

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
        switch t.operation.lowercased() {
        case "getcentroid": return .geometry(g.getCentroid())
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
        default: return nil
        }
    }
}
