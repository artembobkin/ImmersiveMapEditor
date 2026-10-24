import Testing
import Topology

/// JTS's unit tests of the KD-tree (`KdTreeTest` of JTS 1.20).
@Suite struct KdTreeTests {
    static func build(_ wkt: String, _ tolerance: Double) throws -> KdTree<Int> {
        let index = KdTree<Int>(tolerance: tolerance)
        for c in try WKTReader().read(wkt).getCoordinates() { index.insert(c) }
        return index
    }

    static func check(_ wkt: String, _ tolerance: Double, _ env: Envelope, _ expected: String, repeated: Bool = false) throws {
        let index = try build(wkt, tolerance)
        let found = index.query(env).flatMap { i in
            [Coordinate](repeating: index.nodes[i].coordinate, count: repeated ? index.nodes[i].count : 1)
        }
        let want = try WKTReader().read(expected).getCoordinates()
        #expect(found.sorted() == want.sorted())
        if repeated {
            for p in want { #expect(index.query(p).map { index.nodes[$0].coordinate } == p) }
        }
    }

    @Test func singlePoint() {
        let index = KdTree<Int>(tolerance: 0.001)
        let n1 = index.insert(Coordinate(1, 1)), n2 = index.insert(Coordinate(1, 1))
        #expect(n1 == n2)
        let result = index.query(Envelope(0, 10, 0, 10))
        #expect(result.count == 1)
        #expect(index.nodes[result[0]].count == 2)
        #expect(index.nodes[result[0]].isRepeated)
    }

    @Test func queries() throws {
        try KdTreeTests.check("MULTIPOINT ( (1 1), (2 2) )", 0, Envelope(0, 10, 0, 10), "MULTIPOINT ( (1 1), (2 2) )")
        try KdTreeTests.check("MULTIPOINT ( (1 1), (2 2), (3 3), (4 4) )", 0, Envelope(1.5, 3.4, 1.5, 3.5), "MULTIPOINT ( (2 2), (3 3) )")
        try KdTreeTests.check("MULTIPOINT ( (0 0), (-.1 1), (.1 1) )", 1, Envelope(-9, 9, -9, 9), "MULTIPOINT ( (0 0), (-.1 1) )")
        try KdTreeTests.check("MULTIPOINT ((10 60), (20 60), (30 60), (30 63))", 9, Envelope(0, 99, 0, 99), "MULTIPOINT ((10 60), (20 60), (30 60))")
        try KdTreeTests.check("MULTIPOINT ((10 60), (20 61), (30 60), (30 63))", 9, Envelope(0, 99, 0, 99), "MULTIPOINT ((10 60), (20 61), (30 60))")
        try KdTreeTests.check("MULTIPOINT ( (10 60), (20 60), (16 60))", 5, Envelope(0, 99, 0, 99), "MULTIPOINT ( (10 60), (20 60), (20 60))",
                              repeated: true)
    }

    @Test func sizeDepth() throws {
        let index = try KdTreeTests.build("MULTIPOINT ( (10 60), (20 60), (16 60), (1 1), (23 400))", 0)
        #expect(index.size == 5)
        #expect(index.depth() > 1 && index.depth() <= 5)
    }
}
