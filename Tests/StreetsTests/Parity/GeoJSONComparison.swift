/// Compares two GeoJSON documents as the parity bar asks: the same text, or
/// else the same features in the same order with the same properties and
/// coordinates within 1e-9 degrees, and says where they first differ.

import StreetGeom

struct GeoJSONComparison {
    var identicalText: Bool
    var featuresExpected: Int
    var featuresActual: Int
    /// Numbers that differ by at most the tolerance (formatting only).
    var numbersWithinTolerance = 0
    /// The first real difference, if any.
    var firstDifference: String?

    var matches: Bool { firstDifference == nil }

    static let tolerance = 1e-9

    static func compare(expected: String, actual: String) -> GeoJSONComparison {
        if expected == actual {
            let n = expected.components(separatedBy: "\"type\": \"Feature\"").count - 1
            return GeoJSONComparison(identicalText: true, featuresExpected: n, featuresActual: n)
        }
        guard let e = try? JSONValue.parse(expected), let a = try? JSONValue.parse(actual) else {
            return GeoJSONComparison(identicalText: false, featuresExpected: -1, featuresActual: -1,
                                     firstDifference: "not parseable")
        }
        let ef = e["features"]?.arrayValue ?? []
        let af = a["features"]?.arrayValue ?? []
        var result = GeoJSONComparison(identicalText: false, featuresExpected: ef.count, featuresActual: af.count)
        for k in 0..<min(ef.count, af.count) {
            if let d = result.diff(ef[k], af[k], path: "features[\(k)]") {
                result.firstDifference = d
                return result
            }
        }
        if ef.count != af.count {
            result.firstDifference = "feature count \(ef.count) expected, \(af.count) actual"
            return result
        }
        let rest = e.prettyString() == a.prettyString() ? nil : "outside the features"
        result.firstDifference = result.numbersWithinTolerance > 0 ? rest : (rest ?? "text differs, values equal")
        if result.firstDifference == "text differs, values equal" { result.firstDifference = nil }
        return result
    }

    private mutating func diff(_ e: JSONValue, _ a: JSONValue, path: String) -> String? {
        switch (e, a) {
        case (.array(let x), .array(let y)):
            if x.count != y.count { return "\(path): \(x.count) items expected, \(y.count) actual" }
            for k in x.indices { if let d = diff(x[k], y[k], path: "\(path)[\(k)]") { return d } }
            return nil
        case (.object(let x), .object(let y)):
            if Set(x.keys) != Set(y.keys) { return "\(path): keys \(x.keys.sorted()) expected, \(y.keys.sorted()) actual" }
            for k in x.keys.sorted() { if let d = diff(x[k]!, y[k]!, path: "\(path).\(k)") { return d } }
            return nil
        default:
            if let x = e.doubleValue, let y = a.doubleValue {
                if x == y { return nil }
                if Swift.abs(x - y) <= GeoJSONComparison.tolerance {
                    numbersWithinTolerance += 1
                    return nil
                }
                return "\(path): \(serdeJSONNumber(x)) expected, \(serdeJSONNumber(y)) actual"
            }
            return e.prettyString() == a.prettyString() ? nil : "\(path): \(e.prettyString()) expected, \(a.prettyString()) actual"
        }
    }
}
