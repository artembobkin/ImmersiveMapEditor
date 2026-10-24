/// The inline tests of geo 0.27's sweep (`sweep/point.rs`, `segment.rs`, `iter.rs`), run on the
/// module's internal types.

@testable import GeoAlgorithms
import Testing

private func sp(_ x: Double, _ y: Double) -> SweepPoint { SweepPoint(x: x, y: y) }

@Suite struct SweepTests {
    @Test func sweepPointOrdering() {
        let p1 = sp(0, 0)
        let p2 = sp(1, 0)
        let p3 = sp(1, 1)
        let p4 = sp(1, 1)
        #expect(p1.lt(p2))
        #expect(p1.lt(p3))
        #expect(p2.lt(p3))
        #expect(p3.le(p4))
    }

    @Test func split() throws {
        let lines = try [
            LineOrPoint(sp(0, 0), sp(10, 10)),
            LineOrPoint(sp(10, 0), sp(0, 10)),
            LineOrPoint(sp(0, 0), sp(0, 10)),
            LineOrPoint(sp(0, 0), sp(5, 5)),
            LineOrPoint(sp(10, 10), sp(5, 5)),
        ]

        struct Case {
            let a: Int
            let b: Int
            let isec: LineOrPoint?
            let split: SplitSegments?
        }

        func splitEqual(_ l: SplitSegments, _ r: SplitSegments) -> Bool {
            switch (l, r) {
            case let (.unchanged(lo), .unchanged(ro)): return lo == ro
            case let (.splitOnce(lo, lr), .splitOnce(ro, rr)): return lo == ro && lr.coordsEqual(rr)
            case let (.splitTwice(lr), .splitTwice(rr)): return lr.coordsEqual(rr)
            default: return false
            }
        }

        let cases = try [
            Case(a: 0, b: 0, isec: lines[0], split: .unchanged(overlap: true)),
            Case(a: 0, b: 1, isec: .point(sp(5, 5)),
                 split: .splitOnce(overlap: nil, right: LineOrPoint(sp(5, 5), sp(10, 10)))),
            Case(a: 0, b: 2, isec: .point(sp(0, 0)), split: .unchanged(overlap: false)),
            Case(a: 0, b: 3, isec: LineOrPoint(sp(0, 0), sp(5, 5)),
                 split: .splitOnce(overlap: false, right: LineOrPoint(sp(5, 5), sp(10, 10)))),
            Case(a: 0, b: 4, isec: LineOrPoint(sp(5, 5), sp(10, 10)),
                 split: .splitOnce(overlap: true, right: LineOrPoint(sp(5, 5), sp(10, 10)))),
        ]

        for t in cases {
            let isec = try lines[t.a].intersectLineOrdered(lines[t.b])
            // `assert_eq!` on `Option<LineOrPoint>` uses the ordering-based `PartialEq`.
            switch (isec, t.isec) {
            case (nil, nil): break
            case let (got?, want?): #expect(got.eq(want), "\(got) vs \(want)")
            default: Issue.record("intersection \(String(describing: isec)) vs \(String(describing: t.isec))")
            }
            guard let isec else { continue }
            let segment = IMSegment(cross: try LineCross(lines[t.a].geoLine), geom: nil, serial: 0)
            let split = try segment.adjustSegment(isec)
            #expect(splitEqual(split, t.split!), "\(split) vs \(t.split!)")
        }
    }

    @Test func simpleIter() throws {
        let input = try [
            LineCross(GeoLine(geoC(1, 0), geoC(0, 1))),
            LineCross(GeoLine(geoC(0, 0), geoC(1, 1))),
        ]
        var iter = try CrossingsIter(input)
        var count = 0
        while try iter.next() != nil {
            count += 1
        }
        #expect(count == 5)
    }

    @Test func overlapIntersect() throws {
        let input = [
            GeoLine(geoC(0, 0), geoC(1, 1)),
            GeoLine(geoC(1, 0), geoC(0, 1)),
            GeoLine(geoC(0, 0.5), geoC(1, 0.5)),
            GeoLine(geoC(-1, 0.5), geoC(0.5, 0.5)),
            GeoLine(geoC(0.5, 0.5), geoC(0.5, 0.5)),
            GeoLine(geoC(0, 0), geoC(0, 0)),
        ]
        // Intersections by index: (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (1, 2), (1, 3),
        // (1, 4), (2, 3).
        var verify = 0
        for (i, l1) in input.enumerated() {
            for (j, l2) in input.enumerated() where j > i {
                if lineIntersection(l1, l2) != nil {
                    verify += 1
                }
            }
        }
        var iter = try Intersections(input.map { try LineCross($0) })
        var count = 0
        while try iter.next() != nil {
            count += 1
        }
        #expect(count == verify)
    }
}
