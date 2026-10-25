import Foundation
import Testing
import Topology

/// WKT written by the port as `Geometry.description` asked GEOS for it (a
/// writer with rounding precision 3, otherwise GEOS's defaults), against
/// GEOS's stored text: the same text.
@Suite struct WKTParityTests {
    @Test func descriptionText() {
        let o = Oracles.make("WKTParityTests.descriptionText")
        defer { o.finish() }
        var tally = ParityTally("WKT, rounding precision 3 (Geometry.description)")
        var r = RandomGeometries(seed: 40)
        var shapes: [Shape] = (0..<20_000).map { _ in r.geometry() }
        // Numbers at the edges of the format: halves, tiny, huge, negative zero.
        for v in [0.0005, 0.0015, 0.0025, -0.0005, 1e-9, -1e-9, 123456789.0005, 1e15, 1e16, 1.5e17, 1e21, 2.675, 1.0005, -0.0, 5e-4, 4.9999e-4, 0.1 + 0.2] {
            shapes.append(Shape(kind: .point, coordinates: [v, -v]))
        }
        for s in shapes {
            let mine = WKTWriter(roundingPrecision: 3).write(s.topology())
            let theirs = o.wkt(.shape(s))
            tally.check(theirs.matches(Array(mine.utf8)),
                        "\(s):\n  port \(mine)\n  GEOS \(theirs.whole.map { String(decoding: $0, as: UTF8.self) } ?? "(a digest)")")
        }
        tally.report()
    }
}
