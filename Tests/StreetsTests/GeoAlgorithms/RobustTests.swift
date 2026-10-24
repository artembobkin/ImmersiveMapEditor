/// The `orient2d` tests of the robust crate 1.2.0 (`src/tests.rs`): the fixture signs and the
/// collinear and near-collinear points around the diagonal. The 3D and in-circle predicates are
/// not ported, nor their tests.

import GeoAlgorithms
import Testing

enum RobustFixtures {
    /// The fixture lines, each split into numbers after the leading index.
    static var rows: [[Double]] {
        [orient2dPart1, orient2dPart2, orient2dPart3, orient2dPart4]
            .flatMap { $0.split(separator: "\n") }
            .map { line in line.split(separator: " ").dropFirst().map { Double(String($0))! } }
    }
}

/// Rust's `f64::signum`: the sign as plus or minus one (zeros keep their sign), NaN for NaN.
private func signum(_ x: Double) -> Double {
    if x.isNaN { return .nan }
    return x.sign == .minus ? -1.0 : 1.0
}

@Suite struct RobustTests {
    @Test func orient2dFixtures() {
        let fixtures = RobustFixtures.rows
        #expect(fixtures.count == 1000)
        for (idx, fixture) in fixtures.enumerated() {
            let c1 = GeoCoord(x: fixture[0], y: fixture[1])
            let c2 = GeoCoord(x: fixture[2], y: fixture[3])
            let c3 = GeoCoord(x: fixture[4], y: fixture[5])
            let sign = fixture[6]
            let res = Robust.orient2d(c1, c2, c3)
            #expect(signum(res) == signum(sign), "Line \(idx + 1): \(res) vs \(sign) for \(c1) \(c2) \(c3)")
        }
    }

    @Test func orient2d() {
        let from = GeoCoord(x: -1, y: -1)
        let to = GeoCoord(x: 1, y: 1)
        let m = Double.leastNormalMagnitude
        let p1 = GeoCoord(x: m, y: m)
        let p2 = GeoCoord(x: -m, y: -m)
        let p3 = GeoCoord(x: -m, y: m)
        let p4 = GeoCoord(x: m, y: -m)
        for (p, sign) in [(p1, 0.0), (p2, 0.0), (p3, 1.0), (p4, -1.0)] {
            let det = Robust.orient2d(from, to, p)
            #expect(det == sign || signum(det) == signum(sign))
        }
    }
}
