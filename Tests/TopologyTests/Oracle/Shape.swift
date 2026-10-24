/// A geometry as plain values, the common ground of GEOS and `Topology` in
/// the parity tests: its kind, its coordinates (x, y pairs) or its parts (a
/// polygon's rings, a collection's members). Two shapes are equal when their
/// structure is and every coordinate has the same bits (`-0.0` is not `0.0`,
/// a NaN equals a NaN of the same bits).
struct Shape: Equatable, CustomStringConvertible {
    /// The kinds, numbered as GEOS's type ids.
    enum Kind: Int {
        case point = 0, lineString, linearRing, polygon, multiPoint, multiLineString, multiPolygon, geometryCollection
    }

    var kind: Kind
    var coordinates: [Double] = []
    var parts: [Shape] = []

    static func == (a: Shape, b: Shape) -> Bool {
        a.kind == b.kind && a.parts == b.parts && a.coordinates.count == b.coordinates.count
            && zip(a.coordinates, b.coordinates).allSatisfy { $0.bitPattern == $1.bitPattern }
    }

    /// Equal but for the sign of zeros: the structure exactly, every
    /// coordinate equal as a value (`0.0 == -0.0`), NaN as NaN.
    func equalsIgnoringZeroSign(_ o: Shape) -> Bool {
        kind == o.kind && parts.count == o.parts.count && coordinates.count == o.coordinates.count
            && zip(coordinates, o.coordinates).allSatisfy { $0 == $1 || $0.bitPattern == $1.bitPattern }
            && zip(parts, o.parts).allSatisfy { $0.equalsIgnoringZeroSign($1) }
    }

    /// Equal within `tolerance` on every coordinate, the structure exactly.
    func equals(_ o: Shape, tolerance: Double) -> Bool {
        kind == o.kind && parts.count == o.parts.count && coordinates.count == o.coordinates.count
            && zip(coordinates, o.coordinates).allSatisfy { abs($0 - $1) <= tolerance || $0.bitPattern == $1.bitPattern }
            && zip(parts, o.parts).allSatisfy { $0.equals($1, tolerance: tolerance) }
    }

    /// The largest coordinate difference of two shapes of one structure, or
    /// infinity when their structures differ.
    func maxDifference(_ o: Shape) -> Double {
        guard kind == o.kind, parts.count == o.parts.count, coordinates.count == o.coordinates.count else { return .infinity }
        var d = zip(coordinates, o.coordinates).map { $0.bitPattern == $1.bitPattern ? 0 : abs($0 - $1) }.max() ?? 0
        for (a, b) in zip(parts, o.parts) { d = max(d, a.maxDifference(b)) }
        return d
    }

    var isEmpty: Bool { coordinates.isEmpty && parts.allSatisfy(\.isEmpty) }

    /// WKT with every digit (Swift's shortest round-trip form), readable back.
    var description: String {
        func list(_ c: [Double]) -> String {
            stride(from: 0, to: c.count, by: 2).map { "\(c[$0]) \(c[$0 + 1])" }.joined(separator: ", ")
        }
        let name = ["POINT", "LINESTRING", "LINEARRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING", "MULTIPOLYGON",
                    "GEOMETRYCOLLECTION"][kind.rawValue]
        switch kind {
        case .point, .lineString, .linearRing:
            return coordinates.isEmpty ? "\(name) EMPTY" : "\(name) (\(list(coordinates)))"
        case .polygon:
            return parts.isEmpty ? "\(name) EMPTY" : "\(name) (" + parts.map { "(\(list($0.coordinates)))" }.joined(separator: ", ") + ")"
        case .geometryCollection:
            return parts.isEmpty ? "\(name) EMPTY" : "\(name) (" + parts.map(\.description).joined(separator: ", ") + ")"
        default:
            // The members of a multi-geometry untagged, as WKT writes them.
            return parts.isEmpty ? "\(name) EMPTY" : "\(name) (" + parts.map(\.untagged).joined(separator: ", ") + ")"
        }
    }

    /// The text of a shape without its type name.
    var untagged: String {
        let d = description
        if d.hasSuffix(" EMPTY") { return "EMPTY" }
        guard let i = d.firstIndex(of: "(") else { return d }
        return String(d[i...])
    }
}
