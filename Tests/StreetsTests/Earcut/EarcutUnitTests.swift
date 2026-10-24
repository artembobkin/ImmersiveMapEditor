/// The port of earcutr 0.4.3's `src/tests.rs`: unit tests of the node arena, the predicates, the
/// ear tests, point filtering, hole elimination and the fallbacks of the ear slicing loop. They
/// reach the internals through `@testable import`.

@testable import Earcut
import Testing

/// The number of nodes in the ring of `p`, counted as the crate's test helper `cycle_len` does
/// (a ring of one node counts 2, an index out of the arena counts 0).
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
        if i == end {
            return count
        }
        if count > ll.nodes.count {
            return count
        }
    }
}

/// The linked ring of all of `values`, wound clockwise, as the tests build it.
private func ring(_ values: [Double]) throws -> LinkedLists {
    try linkedList(Vertices(values), 0, values.count, true).0
}

@Suite("earcutr unit tests")
struct EarcutUnitTests {
    @Test func empty() throws {
        #expect(try Earcut.earcut([], holeIndices: [], dimensions: 2) == [])
    }

    @Test func linkedListOrder() throws {
        let ll = try ring([0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0])
        #expect(ll.nodes.count == 5)
        #expect(ll.nodes[1].idx == 1)
        #expect(ll.nodes[1].verticesIndex == 6 / dim)
        #expect(ll.nodes[1].verticesIndex == 3)
        #expect(ll.nodes[1].coord.x == 1.0)
        #expect(ll.nodes[1].coord.y == 0.0)
        #expect(ll.nodes[1].nextLinkedListNodeIndex == 2 && ll.nodes[1].prevLinkedListNodeIndex == 4)
        #expect(ll.nodes[4].nextLinkedListNodeIndex == 1 && ll.nodes[4].prevLinkedListNodeIndex == 3)
        ll.removeNode(2)
    }

    /// The Rust test only prints the pairs from node 1 up to node 2: there is one, node 1 and its next.
    @Test func iterPairs() throws {
        let ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        var pairs: [(Int, Int)] = []
        var cur = 1
        repeat {
            pairs.append((ll.nodes[cur].idx, ll.next(cur).idx))
            cur = ll.nodes[cur].nextLinkedListNodeIndex
        } while cur != 2
        #expect(pairs.count == 1)
        #expect(pairs[0].0 == 1 && pairs[0].1 == 2)
    }

    @Test func pointInTriangle() throws {
        let ll = try ring([0.0, 0.0, 2.0, 0.0, 2.0, 2.0, 1.0, 0.1])
        #expect(NodeTriangle(ll.nodes[1], ll.nodes[2], ll.nodes[3]).containsPoint(ll.nodes[4]))
    }

    @Test func signedArea() {
        let vertices1 = Vertices([0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0])
        let vertices2 = Vertices([1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0])
        let a1 = vertices1.signedArea(0, 4)
        let a2 = vertices2.signedArea(0, 4)
        #expect(a1 == -a2)
    }

    @Test func deviation() {
        let vertices1 = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0]
        let tris = [0, 1, 2, 2, 3, 0]
        #expect(Earcut.deviation(vertices1, holeIndices: [], dimensions: dim, triangles: tris) == 0.0)
    }

    @Test func splitBridgePolygonSplitsAndJoins() throws {
        var body = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0]
        body.append(contentsOf: [0.1, 0.1, 0.1, 0.2, 0.2, 0.2])
        let ll = try ring(body)
        #expect(cycleLen(ll, 1) == body.count / dim)
        let (left, right) = (1, 5)
        let np = splitBridgePolygon(ll, left, right)
        #expect(cycleLen(ll, left) == 4)
        #expect(cycleLen(ll, np) == 5)
        // Contrary to its name, this joins the two rings back together.
        let np2 = splitBridgePolygon(ll, left, np)
        #expect(cycleLen(ll, np2) == 11)
        #expect(cycleLen(ll, left) == 11)
    }

    @Test func equals() throws {
        let ll = try ring([0.0, 1.0, 0.0, 1.0])
        #expect(ll.nodes[1].xyEq(ll.nodes[2]))

        let ll2 = try ring([2.0, 1.0, 0.0, 1.0])
        #expect(!ll2.nodes[1].xyEq(ll2.nodes[2]))
    }

    @Test func area() throws {
        // Counterclockwise.
        let ll = try ring([4.0, 0.0, 4.0, 3.0, 0.0, 0.0])
        #expect(NodeTriangle(ll.nodes[1], ll.nodes[2], ll.nodes[3]).area() == -12.0)
        // Clockwise: making the ring turns every winding counterclockwise.
        let ll2 = try ring([4.0, 0.0, 0.0, 0.0, 4.0, 3.0])
        #expect(NodeTriangle(ll2.nodes[1], ll2.nodes[2], ll2.nodes[3]).area() == -12.0)
    }

    @Test func isEar() throws {
        var ll = try ring([0.0, 0.0, 0.5, 0.0, 1.0, 0.0])
        #expect(!NodeIndexTriangle(1, 2, 3).isEar(ll))
        #expect(!NodeIndexTriangle(2, 3, 1).isEar(ll))
        #expect(!NodeIndexTriangle(3, 1, 2).isEar(ll))

        ll = try ring([0.0, 0.0, 0.5, 0.5, 1.0, 0.0, 0.5, 0.4])
        #expect(!NodeIndexTriangle(4, 1, 2).isEar(ll))
        #expect(NodeIndexTriangle(1, 2, 3).isEar(ll))
        #expect(!NodeIndexTriangle(2, 3, 4).isEar(ll))
        #expect(NodeIndexTriangle(3, 4, 1).isEar(ll))

        ll = try ring([0.0, 0.0, 0.5, 0.5, 1.0, 0.0])
        #expect(NodeIndexTriangle(3, 1, 2).isEar(ll))

        ll = try ring([0.0, 0.0, 4.0, 0.0, 4.0, 3.0])
        #expect(NodeIndexTriangle(3, 1, 2).isEar(ll))
    }

    @Test func filterPointsRemovesRepeatedAndCollinear() throws {
        var ll = try ring([0.0, 0.0, 0.5, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        let r1 = filterPoints(ll, 1, ll.nodes.count - 1)
        #expect(cycleLen(ll, r1) == 4)

        ll = try ring([0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0])
        let r2 = filterPoints(ll, 1, ll.nodes.count - 1)
        #expect(cycleLen(ll, r2) == 4)

        ll = try ring([0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0])
        let r32 = filterPoints(ll, 1, 99)
        #expect(cycleLen(ll, r32) != 4)

        ll = try ring([0.0, 0.0, 0.25, 0.0, 0.5, 0.0, 1.0, 0.0, 1.0, 1.0, 0.5, 0.5])
        let r3 = filterPoints(ll, 1, ll.nodes.count - 1)
        #expect(cycleLen(ll, r3) == 3)

        ll = try ring([0.0, 0.0, 0.5, 0.5, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0])
        let r4 = filterPoints(ll, 1, ll.nodes.count - 1)
        #expect(cycleLen(ll, r4) == 5)
    }

    /// The Rust test runs on `f32` coordinates. This port has only `Double`.
    @Test func earcutLinkedPasses() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        var tris: [Int] = []
        try earcutLinked(ll, 1, &tris, pass: 0, hashed: true)
        #expect(tris.count == 6)

        ll = try ring([0.0, 0.0, 0.5, 0.5, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        tris = []
        try earcutLinked(ll, 1, &tris, pass: 0, hashed: false)
        #expect(tris.count == 9)

        ll = try ring([0.0, 0.0, 0.5, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        tris = []
        try earcutLinked(ll, 1, &tris, pass: 0, hashed: true)
        #expect(tris.count == 9)
    }

    @Test func middleInsideOfDiagonals() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        #expect(middleInside(ll, ll.nodes[1], ll.nodes[3]))
        #expect(middleInside(ll, ll.nodes[2], ll.nodes[4]))

        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.9, 0.1])
        #expect(!middleInside(ll, ll.nodes[1], ll.nodes[3]))
        #expect(middleInside(ll, ll.nodes[2], ll.nodes[4]))
    }

    @Test func locallyInsideOfDiagonals() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[1]))
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[2]))
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[3]))
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[4]))

        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.9, 0.1])
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[1]))
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[2]))
        #expect(!locallyInside(ll, ll.nodes[1], ll.nodes[3]))
        #expect(locallyInside(ll, ll.nodes[1], ll.nodes[4]))
    }

    /// The second half of the Rust test only logs its results, so only the first half asserts.
    @Test func intersectsPolygonOfDiagonals() throws {
        var ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
        #expect(!intersectsPolygon(ll, ll.nodes[0], ll.nodes[2]))
        #expect(!intersectsPolygon(ll, ll.nodes[2], ll.nodes[0]))
        #expect(!intersectsPolygon(ll, ll.nodes[1], ll.nodes[3]))
        #expect(!intersectsPolygon(ll, ll.nodes[3], ll.nodes[1]))

        ll = try ring([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.1, 0.1, 0.9, 1.0, 0.0, 1.0])
        _ = intersectsPolygon(ll, ll.nodes[0], ll.nodes[2])
        _ = intersectsPolygon(ll, ll.nodes[2], ll.nodes[0])
    }
}
