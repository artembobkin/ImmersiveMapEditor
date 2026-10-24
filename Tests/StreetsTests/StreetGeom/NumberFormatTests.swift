/// Rust's number formatting as the port reproduces it: serde_json (ryu),
/// `Display` and `Debug`. Checked on fixed cases and on every number of a
/// GeoJSON file the Rust osm2streets wrote.

import Foundation
import StreetGeom
import Testing

@Suite struct NumberFormatTests {
    @Test func serdeJSONFixedCases() {
        let cases: [(Double, String)] = [
            (0.0, "0.0"), (-0.0, "-0.0"), (1.0, "1.0"), (3.0, "3.0"), (0.1, "0.1"), (1.5, "1.5"),
            (100.0, "100.0"), (1e15, "1000000000000000.0"), (1e16, "1e16"), (1.5e16, "1.5e16"),
            (1e-5, "0.00001"), (1e-6, "1e-6"), (1.25e-7, "1.25e-7"), (123456.789, "123456.789"),
            (-88.43141399279669, "-88.43141399279669"), (44.24213357723116, "44.24213357723116"),
            (Double.greatestFiniteMagnitude, "1.7976931348623157e308"), (5e-324, "5e-324"),
            (Double.nan, "null"), (Double.infinity, "null"),
        ]
        for (x, s) in cases { #expect(serdeJSONNumber(x) == s, "\(x)") }
    }

    @Test func rustDisplayAndDebug() {
        #expect(rustDisplay(30.0) == "30")
        #expect(rustDisplay(8.3333) == "8.3333")
        #expect(rustDisplay(1e-7) == "0.0000001")
        #expect(rustDisplay(1e21) == "1000000000000000000000")
        #expect(rustDisplay(-0.0) == "-0")
        #expect(rustDebugF64(30.0) == "30.0")
        #expect(rustDebugF64(8.3333) == "8.3333")
        #expect(rustDebugF64(1e-5) == "1e-5")
        #expect(rustDebugF64(1e16) == "1e16")
        #expect(rustDebugF64(0.0001) == "0.0001")
    }

    /// Every number the Rust wrote in a lane polygons file reads back and
    /// prints as the same text.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: rustOutput.path), "no Rust output to read"))
    func roundTripsRustOutput() throws {
        let text = try String(contentsOf: rustOutput, encoding: .utf8)
        var count = 0
        // Pretty printed: a number in an array or after a key ends its line.
        for line in text.split(separator: "\n") {
            var token = line.trimmingCharacters(in: .whitespaces)
            if let colon = token.range(of: "\": ") { token = String(token[colon.upperBound...]) }
            if token.hasSuffix(",") { token.removeLast() }
            guard token.contains(".") || token.contains("e"), !token.hasPrefix("\""), let x = Double(token) else { continue }
            #expect(serdeJSONNumber(x) == token)
            count += 1
        }
        #expect(count > 1000)
    }

    static let rustOutput = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Desktop/TilePipeline/data/regions/15_19808_10242_19809_10243/streets/lanes.geojson")
    var rustOutput: URL { Self.rustOutput }
}

/// geom's own unit tests that apply to what is ported.
@Suite struct GeomTests {
    @Test func f64Trimming() {
        let p = Pt2D(1.2345678, 9.876543)
        #expect(p.x == 1.2346)
        #expect(p.y == 9.8765)
    }

    @Test func angleAverage() {
        #expect(Angle.degrees(30.0) == Angle.average([Angle.degrees(30.0)]))
    }

    @Test func pointsEqualWithinOneCentimetre() {
        #expect(Pt2D(0, 0) == Pt2D(0.007, 0.007))
        #expect(Pt2D(0, 0) != Pt2D(0.01, 0.01))
    }

    @Test func polylineSlices() throws {
        let pl = PolyLine.mustNew([Pt2D(0, 0), Pt2D(0, 10), Pt2D(10, 20)])
        #expect(pl.length == Distance.meters(10.0 + 200.0.squareRoot()))
        let s = try pl.maybeExactSlice(.meters(5), .meters(15))
        #expect(s.points.count == 3)
        #expect(s.firstPt() == Pt2D(0, 5))
        #expect(pl.middle() == pl.mustDistAlong(pl.length / 2.0).0)
    }

    @Test func shiftKeepsTheShape() throws {
        let pl = PolyLine.mustNew([Pt2D(0, 0), Pt2D(10, 0), Pt2D(10, 10)])
        let right = try pl.shiftRight(.meters(1))
        #expect(right.points == [Pt2D(0, 1), Pt2D(9, 1), Pt2D(9, 10)])
        let left = try pl.shiftLeft(.meters(1))
        #expect(left.points == [Pt2D(0, -1), Pt2D(11, -1), Pt2D(11, 10)])
    }

    @Test func prettyJSON() {
        let v = JSONValue.orderedObject([("type", .string("A")), ("b", .array([])), ("c", .object(["z": .int(1), "a": .null]))])
        #expect(v.prettyString() == "{\n  \"type\": \"A\",\n  \"b\": [],\n  \"c\": {\n    \"a\": null,\n    \"z\": 1\n  }\n}")
    }
}
