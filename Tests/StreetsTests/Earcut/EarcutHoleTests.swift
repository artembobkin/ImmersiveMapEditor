/// The second half of the port of earcutr 0.4.3's `src/tests.rs`: crossing segments, valid
/// diagonals, hole bridges and hole elimination, curing local intersections, splitting, and the
/// public `flatten` and `earcut` on small inputs.

@testable import Earcut
import Testing

/// The number of nodes in the ring of `p`, counted as the crate's test helper `cycle_len` does.
private func cycleLen(_ ll: LinkedLists, _ p: Int) -> Int {
    if p >= ll.nodes.count {
        return 0
    }
    let end = ll.nodes[p].prevLinkedListNodeIndex
    var i = p
    var count = 1
    while true {
        i = ll.nodes[i].nextLinkedListNodeIndex
        count += 1
        if i == end || count > ll.nodes.count {
            return count
        }
    }
}

/// The linked ring of `values[0..<end]` (all of them by default), wound clockwise.
private func ring(_ values: [Double], end: Int? = nil) throws -> LinkedLists {
    try linkedList(Vertices(values), 0, end ?? values.count, true).0
}

@Suite("earcutr unit tests of holes and splitting")
struct EarcutHoleTests {
    @Test func intersectsItself() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 0.9, 0.9, 0.0, 1.0])
        func ti(_ ok: Bool, _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            #expect(ok == pseudoIntersects(ll.nodes[a], ll.nodes[b], ll.nodes[c], ll.nodes[d]))
        }
        ti(false, 1, 2 + 1, 1, 1 + 1)
        ti(false, 1, 2 + 1, 1 + 1, 2 + 1)
        ti(false, 1, 2 + 1, 2 + 1, 3 + 1)
        ti(false, 1, 2 + 1, 3 + 1, 1)
        ti(true, 1, 2 + 1, 3 + 1, 1 + 1)
        ti(true, 1, 2 + 1, 1 + 1, 3 + 1)
        ti(true, 2 + 1, 1, 3 + 1, 1 + 1)
        ti(true, 2 + 1, 1, 1 + 1, 3 + 1)
        ti(false, 1, 1 + 1, 2 + 1, 3 + 1)
        ti(false, 1 + 1, 1, 2 + 1, 3 + 1)
        ti(false, 1, 1, 2 + 1, 3 + 1)
        ti(false, 1, 1 + 1, 3 + 1, 2 + 1)
        ti(false, 1 + 1, 1, 3 + 1, 2 + 1)

        // The special cases.
        ti(true, 1, 2 + 1, 2 + 1, 1)
        ti(true, 1, 2 + 1, 1, 2 + 1)

        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.1, 0.1, 0.9, 1.0, 0.0, 1.0])
        #expect(!pseudoIntersects(ll.nodes[4], ll.nodes[5], ll.nodes[1], ll.nodes[3]))

        // A special case.
        #expect(pseudoIntersects(ll.nodes[4], ll.nodes[5], ll.nodes[3], ll.nodes[1]))
    }

    @Test func isValidDiagonalCases() throws {
        let ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.9, 0.1])
        #expect(!ll.isValidDiagonal(ll.nodes[1], ll.nodes[2]))
        #expect(!ll.isValidDiagonal(ll.nodes[2], ll.nodes[3]))
        #expect(!ll.isValidDiagonal(ll.nodes[3], ll.nodes[4]))
        #expect(!ll.isValidDiagonal(ll.nodes[4], ll.nodes[1]))
        #expect(!ll.isValidDiagonal(ll.nodes[1], ll.nodes[3]))
        #expect(ll.isValidDiagonal(ll.nodes[2], ll.nodes[4]))
        #expect(!ll.isValidDiagonal(ll.nodes[3], ll.nodes[4]))
        #expect(ll.isValidDiagonal(ll.nodes[4], ll.nodes[2]))
    }

    @Test func findHoleBridgeCases() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        var holeIdx = ll.insertNode(0, Coord(x: 0.8, y: 0.8), nil)
        #expect(1 == findHoleBridge(ll, holeIdx, 1))

        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.4, 0.5])
        holeIdx = ll.insertNode(0, Coord(x: 0.5, y: 0.5), nil)
        #expect(5 == findHoleBridge(ll, holeIdx, 1))

        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, -0.4, 0.5])
        holeIdx = ll.insertNode(0, Coord(x: 0.5, y: 0.5), nil)
        #expect(5 == findHoleBridge(ll, holeIdx, 1))

        ll = try ring([
            0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, -0.1, 0.9, 0.1, 0.8, -0.1, 0.7, 0.1, 0.6, -0.1, 0.5,
        ])
        let cases: [(Double, Double, Int)] = [
            (0.5, 0.9, 5), (0.2, 0.1, 9), (0.2, 0.5, 9), (0.2, 0.55, 9), (0.2, 0.6, 8),
            (0.2, 0.65, 7), (0.2, 0.7, 7), (0.2, 0.75, 7), (0.2, 0.8, 6), (0.2, 0.85, 5),
            (0.2, 0.9, 5), (0.2, 0.95, 5),
        ]
        for (x, y, expected) in cases {
            holeIdx = ll.insertNode(0, Coord(x: x, y: y), nil)
            #expect(expected == findHoleBridge(ll, holeIdx, 1), "hole at \(x), \(y)")
        }
    }

    @Test func eliminateHoleLinksRings() throws {
        var body = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0]

        var bodyEnd = body.count
        body.append(contentsOf: [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9])
        var holeStart = bodyEnd
        var holeEnd = body.count
        let ll = try ring(body, end: bodyEnd)
        _ = try ll.addContour(Vertices(body), holeStart, holeEnd, false)
        #expect(cycleLen(ll, 1) == 4)
        #expect(cycleLen(ll, 5) == 4)
        ll.eliminateHole(holeStart / dim + 1, 1)
        #expect(cycleLen(ll, 1) == 10)

        bodyEnd = body.count
        body.append(contentsOf: [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8])
        holeStart = bodyEnd
        holeEnd = body.count
        _ = try ll.addContour(Vertices(body), holeStart, holeEnd, false)
        #expect(cycleLen(ll, 1) == 10)
        #expect(cycleLen(ll, 5) == 10)
        #expect(cycleLen(ll, 11) == 4)
        ll.eliminateHole(11, 2)
        #expect(cycleLen(ll, 1) == 16)
        #expect(cycleLen(ll, 10) == 16)
        #expect(cycleLen(ll, 15) == 16)
    }

    /// `test_cycle_len` and `test_cycles_report` of the crate only build these rings and log them.
    @Test func cycleLenAndCyclesReport() throws {
        var body = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.1, 0.1]
        var bodyEnd = body.count
        body.append(contentsOf: [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9])
        let ll = try ring(body, end: bodyEnd)
        _ = try ll.addContour(Vertices(body), bodyEnd, body.count, false)

        bodyEnd = body.count
        body.append(contentsOf: [0.2, 0.2, 0.8, 0.2, 0.8, 0.8])
        _ = try ll.addContour(Vertices(body), bodyEnd, body.count, false)
        #expect(ll.nodes.count == 13)
    }

    /// The crate's test only checks that this runs (from the sentinel node as the outer node).
    @Test func eliminateHolesRuns() throws {
        var body = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0]
        let ll = try ring(body)
        let hole1 = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]
        let hole2 = [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8]
        let holeIndices = [body.count / dim, (body.count + hole1.count) / dim]
        body.append(contentsOf: hole1)
        body.append(contentsOf: hole2)
        _ = try eliminateHoles(ll, Vertices(body), holeIndices, 0)
    }

    @Test func cureLocalIntersectionsCases() throws {
        // The first case cannot detect the crossing, so nothing changes.
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.1, 0.1, 0.9, 0.1, 1.0, 0.05, 1.0, 1.0, 0.0, 1.0])
        var triangles: [Int] = []
        _ = cureLocalIntersections(ll, 0, &triangles)
        #expect(cycleLen(ll, 1) == 7)
        #expect(triangles.isEmpty)

        // Three points cause a self-intersection at once, so it is detected and cleaned.
        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.1, 0.1, 1.1, 0.0, 1.0, 1.0, 0.0, 1.0])
        triangles = []
        _ = cureLocalIntersections(ll, 1, &triangles)
        #expect(cycleLen(ll, 1) == 4)
        #expect(triangles.count == 3)
    }

    @Test func splitEarcutCases() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        var triangles: [Int] = []
        try splitEarcut(ll, 1, &triangles)
        #expect(triangles.count == 6)
        #expect(ll.nodes.count == 7)

        ll = try ring([
            0.0, 0.0, 1.0, 0.0, 1.5, 0.5, 2.0, 0.0, 3.0, 0.0, 3.0, 1.0, 2.0, 1.0, 1.5, 0.6, 1.0, 1.0,
            0.0, 1.0,
        ])
        triangles = []
        try splitEarcut(ll, 1, &triangles)
        #expect(ll.nodes.count == 13)
    }

    @Test func flattenNested() {
        let data: [[[Double]]] = [
            [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]],
            [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]],
            [[0.2, 0.2], [0.8, 0.2], [0.8, 0.8], [0.2, 0.8]],
        ]
        let (coords, holeIndices, dims) = Earcut.flatten(data)
        #expect(dim == dims)
        #expect(coords.count == 24)
        #expect(holeIndices.count == 2)
        #expect(holeIndices[0] == 4)
        #expect(holeIndices[1] == 8)
    }

    @Test func iss45() throws {
        let data: [[[Double]]] = [
            [[10.0, 10.0], [25.0, 10.0], [25.0, 40.0], [10.0, 40.0]],
            [[15.0, 30.0], [20.0, 35.0], [10.0, 40.0]],
            [[15.0, 15.0], [15.0, 20.0], [20.0, 15.0]],
        ]
        let (coords, holeIndices, dims) = Earcut.flatten(data)
        #expect(dim == dims)
        let triangles = try Earcut.earcut(coords, holeIndices: holeIndices, dimensions: dim)
        #expect(triangles.count > 4)
    }

    /// The crate's test only checks that this terminates.
    @Test func infiniteLoopBug() {
        let coords = [
            3482952.0523706395, -2559865.184587028, 3482952.0523706395, -2559865.184587028,
            // A hole.
            3856285.4462009706, -1347264.3952299273, 3856285.4462009706, -1347264.3952299273,
            // A hole.
            3864938.7972431043, -1358303.0608723268, 3864938.7972431043, -1358303.0608723268,
        ]
        _ = try? Earcut.earcut(coords, holeIndices: [2, 4], dimensions: dim)
    }
}
