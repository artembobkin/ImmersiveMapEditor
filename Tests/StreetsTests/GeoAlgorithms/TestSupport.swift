/// Helpers for the ported tests: a small GeoTestWKT reader for the polygon and line string fixtures of
/// geo's tests (as the wkt crate parses them, with `Polygon::new` closing the rings), the
/// `geo-types` macros' shorthands, and approx's `relative_eq!`.

import GeoAlgorithms

func geoC(_ x: Double, _ y: Double) -> GeoCoord { GeoCoord(x: x, y: y) }
func geoP(_ x: Double, _ y: Double) -> GeoPoint { GeoPoint(x: x, y: y) }

/// `LineString::from(vec![(x, y), ...])`.
func geoLS(_ pairs: [(Double, Double)]) -> GeoLineString {
    GeoLineString(pairs.map { GeoCoord(x: $0.0, y: $0.1) })
}

/// `polygon![...]`: a polygon without interiors.
func geoPoly(_ pairs: [(Double, Double)], _ interiors: [[(Double, Double)]] = []) -> GeoPolygon {
    GeoPolygon(geoLS(pairs), interiors.map(geoLS))
}

/// approx's `relative_eq!` for `f64`, with its defaults `epsilon = max_relative = f64::EPSILON`.
func approxRelativeEq(_ a: Double, _ b: Double, epsilon: Double = Double.ulpOfOne, maxRelative: Double = Double.ulpOfOne) -> Bool {
    if a == b { return true }
    if a.isInfinite || b.isInfinite { return false }
    let absDiff = abs(a - b)
    if absDiff <= epsilon { return true }
    let absA = abs(a)
    let absB = abs(b)
    let largest = absB > absA ? absB : absA
    return absDiff <= largest * maxRelative
}

func approxRelativeEq(_ a: GeoCoord, _ b: GeoCoord, epsilon: Double = Double.ulpOfOne) -> Bool {
    approxRelativeEq(a.x, b.x, epsilon: epsilon) && approxRelativeEq(a.y, b.y, epsilon: epsilon)
}

func approxRelativeEq(_ a: GeoLineString, _ b: GeoLineString, epsilon: Double = Double.ulpOfOne) -> Bool {
    a.count == b.count && zip(a.coords, b.coords).allSatisfy { approxRelativeEq($0, $1, epsilon: epsilon) }
}

func approxRelativeEq(_ a: GeoPolygon, _ b: GeoPolygon, epsilon: Double = Double.ulpOfOne) -> Bool {
    approxRelativeEq(a.exterior, b.exterior, epsilon: epsilon)
        && a.interiors.count == b.interiors.count
        && zip(a.interiors, b.interiors).allSatisfy { approxRelativeEq($0, $1, epsilon: epsilon) }
}

/// A GeoTestWKT reader for the geometry kinds the fixtures use.
struct GeoTestWKT {
    private let chars: [Character]
    private var pos = 0

    private init(_ text: String) {
        chars = Array(text)
    }

    private mutating func skipSpace() {
        while pos < chars.count && chars[pos].isWhitespace { pos += 1 }
    }

    private mutating func word() -> String {
        skipSpace()
        var s = ""
        while pos < chars.count && chars[pos].isLetter {
            s.append(chars[pos])
            pos += 1
        }
        return s.uppercased()
    }

    private mutating func expect(_ ch: Character) {
        skipSpace()
        precondition(pos < chars.count && chars[pos] == ch, "GeoTestWKT: expected \(ch) at \(pos)")
        pos += 1
    }

    private mutating func peek(_ ch: Character) -> Bool {
        skipSpace()
        return pos < chars.count && chars[pos] == ch
    }

    private mutating func number() -> Double {
        skipSpace()
        var s = ""
        while pos < chars.count && (chars[pos].isNumber || "+-.eE".contains(chars[pos])) {
            s.append(chars[pos])
            pos += 1
        }
        guard let v = Double(s) else { preconditionFailure("GeoTestWKT: bad number \(s)") }
        return v
    }

    private mutating func isEmpty() -> Bool {
        skipSpace()
        let save = pos
        if word() == "EMPTY" { return true }
        pos = save
        return false
    }

    private mutating func coordList() -> [GeoCoord] {
        expect("(")
        var coords: [GeoCoord] = []
        while true {
            let x = number()
            let y = number()
            coords.append(GeoCoord(x: x, y: y))
            if peek(",") { pos += 1 } else { break }
        }
        expect(")")
        return coords
    }

    private mutating func polygonBody() -> GeoPolygon {
        if isEmpty() { return GeoPolygon(GeoLineString([]), []) }
        expect("(")
        var rings: [GeoLineString] = []
        while true {
            rings.append(GeoLineString(coordList()))
            if peek(",") { pos += 1 } else { break }
        }
        expect(")")
        return GeoPolygon(rings[0], Array(rings.dropFirst()))
    }

    static func polygon(_ text: String) -> GeoPolygon {
        var r = GeoTestWKT(text)
        precondition(r.word() == "POLYGON")
        return r.polygonBody()
    }

    static func multiPolygon(_ text: String) -> GeoMultiPolygon {
        var r = GeoTestWKT(text)
        precondition(r.word() == "MULTIPOLYGON")
        if r.isEmpty() { return GeoMultiPolygon([GeoPolygon]()) }
        r.expect("(")
        var polygons: [GeoPolygon] = []
        while true {
            polygons.append(r.polygonBody())
            if r.peek(",") { r.pos += 1 } else { break }
        }
        r.expect(")")
        return GeoMultiPolygon(polygons)
    }

    /// `MultiPolygon::try_from_wkt_str`, falling back to a polygon as `check_sweep` does.
    static func multiPolygonOrPolygon(_ text: String) -> GeoMultiPolygon {
        var r = GeoTestWKT(text)
        let kind = r.word()
        return kind == "MULTIPOLYGON" ? multiPolygon(text) : GeoMultiPolygon(polygon(text))
    }

    static func lineString(_ text: String) -> GeoLineString {
        var r = GeoTestWKT(text)
        precondition(r.word() == "LINESTRING")
        if r.isEmpty() { return GeoLineString([]) }
        return GeoLineString(r.coordList())
    }
}

/// The unit regular decagon `(cos(i * 2 pi / 10), sin(i * 2 pi / 10))` of geo's numerical
/// stability tests, to 17 significant digits. Those tests compare the shape with a shifted copy
/// of itself, so they need the shape, not the last bit of `cos` and `sin`.
let unitDecagon: [GeoCoord] = [
    geoC(1.0, 0.0),
    geoC(0.80901699437494745, 0.58778525229247314),
    geoC(0.30901699437494745, 0.95105651629515353),
    geoC(-0.30901699437494734, 0.95105651629515364),
    geoC(-0.80901699437494734, 0.58778525229247325),
    geoC(-1.0, 1.2246467991473532e-16),
    geoC(-0.80901699437494756, -0.58778525229247303),
    geoC(-0.30901699437494756, -0.95105651629515353),
    geoC(0.30901699437494723, -0.95105651629515364),
    geoC(0.80901699437494734, -0.58778525229247336),
]
