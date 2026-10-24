import Foundation
import Testing

/// The recordings of `Geometry` on real data (five tiles and a road seeding,
/// Docs/PortingTopologyProgress.md): they read whole, every geometry in them
/// reads back in GEOS, and the count of calls of each function is printed,
/// the summary the progress document keeps. They stay outside git, so these
/// tests run where they were recorded (`.build/recording`, or
/// `GEOMETRY_REPLAY`).
@Suite(.enabled(if: Recording.available, "no recordings in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct RecordingTests {
    @Test func recordingsReadAndSummarize() throws {
        let oracle = GEOSOracle()
        var total: [String: Int] = [:]
        var lines: [String] = []
        for r in try Recording.load() {
            var counts: [String: Int] = [:]
            for c in r.calls {
                counts[c.name, default: 0] += 1
                for id in c.geometries { #expect(r.geometries[id] != nil, "\(r.name): \(c.name) refers to geometry \(id)") }
            }
            var unreadable = 0
            for (_, wkb) in r.geometries where oracle.read(wkb: wkb) == nil { unreadable += 1 }
            #expect(unreadable == 0, "\(r.name): \(unreadable) geometries GEOS cannot read")
            lines.append("\(r.name): \(r.calls.count) calls, \(r.geometries.count) geometries")
            for (k, v) in counts { total[k, default: 0] += v }
        }
        for (k, v) in total.sorted(by: { $0.value > $1.value }) { lines.append("  \(k) \(v)") }
        print(lines.joined(separator: "\n"))
        #expect(!total.isEmpty)
    }
}
