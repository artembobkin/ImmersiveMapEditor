import Geometry
import Testing
@testable import ImmersiveMapEditor

/// The Roads view's edits, as plain operations on a document.
@Suite struct RoadEditsTests {
    /// A document with one square area 10 m across, counter-clockwise, with
    /// a point in the middle of each side.
    func square() -> RoadPlan {
        var doc = RoadPlan(tiles: .init(z: 15, x0: 19808, y0: 10243, x1: 19808, y1: 10243),
                               seededDate: "", seededRevision: "")
        doc.add(RoadwayArea(id: "", op: "add", rings: [[Vec2(0, 0), Vec2(5, 0), Vec2(10, 0), Vec2(10, 5), Vec2(10, 10),
                                                         Vec2(5, 10), Vec2(0, 10), Vec2(0, 5)]]))
        return doc
    }

    func vertex(_ i: Int) -> Item { .vertex("a1", ring: 0, index: i) }

    @Test func movingTwoPointsOfOneRingMovesBoth() {
        let doc = square().moved([vertex(1), vertex(2)], by: Vec2(0, -1))
        #expect(doc.areas[0].rings[0][1] == Vec2(5, -1))
        #expect(doc.areas[0].rings[0][2] == Vec2(10, -1))
        #expect(doc.areas[0].rings[0][0] == Vec2(0, 0))
    }

    @Test func straighteningDropsThePointsBetween() {
        var doc = square()
        let done = doc.straighten([vertex(0), vertex(2)])
        #expect(done)
        #expect(doc.areas[0].rings[0].count == 7)
        #expect(!doc.areas[0].rings[0].contains(Vec2(5, 0)))
    }

    @Test func straighteningTakesTheShorterWayRound() {
        var doc = square()
        // From the last point to the second: across the first, not round the ring.
        doc.straighten([vertex(7), vertex(1)])
        #expect(doc.areas[0].rings[0].count == 7)
        #expect(!doc.areas[0].rings[0].contains(Vec2(0, 0)))
    }

    @Test func aligningKeepsThePointsOnTheLine() {
        var doc = square()
        doc.areas[0].rings[0][1] = Vec2(5, 2)
        doc.straighten([vertex(0), vertex(2)], keep: true)
        #expect(doc.areas[0].rings[0][1] == Vec2(5, 0))
    }

    @Test func deletingPointsKeepsARingOfThree() {
        var doc = square()
        doc.delete(Set((0..<5).map(vertex)))
        #expect(doc.areas[0].rings[0].count == 3)
        doc.delete([vertex(0)])
        #expect(doc.areas.isEmpty)
    }

    @Test func roundingAddsAnArcTangentToBothEdges() {
        var doc = square()
        doc.roundCorners([vertex(2)], radius: 3)
        let ring = doc.areas[0].rings[0]
        #expect(ring.count > 8)
        #expect(ring.allSatisfy { $0.x <= 10 + 1e-9 && $0.y >= -1e-9 })
        #expect(!ring.contains(Vec2(10, 0)))
    }

    @Test func insertingAPointPutsItAfterTheEdgesStart() {
        var doc = square()
        doc.insert(Vec2(2, 0), "a1", 0, after: 0)
        #expect(doc.areas[0].rings[0][1] == Vec2(2, 0))
    }

    @Test func newAreasAreWoundCounterClockwise() {
        var doc = square()
        let id = doc.add(RoadwayArea(id: "", op: "cut", rings: [counterClockwise([Vec2(0, 0), Vec2(0, 1), Vec2(1, 1)])]))
        #expect(signedArea(doc.object(id)!.rings[0]) > 0)
        #expect(id == "a2")
    }

    @Test func deletingAnObjectLeavesNoneOfItsId() {
        var doc = square()
        let id = doc.add(BusShelter(id: "", position: Vec2(3, 3), heading: 0))
        doc.delete([.object(id)])
        #expect(doc.object(id) == nil)
        #expect(doc.shelters.isEmpty)
    }

    @Test func aCopyKeepsTheOriginalAsItWas() {
        let doc = square()
        let moved = doc.moved([.object("a1")], by: Vec2(1, 0))
        #expect(doc.areas[0].rings[0][0] == Vec2(0, 0))
        #expect(moved.areas[0].rings[0][0] == Vec2(1, 0))
    }
}
