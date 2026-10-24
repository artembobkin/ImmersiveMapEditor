/// The unit tests of osm2streets and osm2lanes that do not go through Muv:
/// placement parsing, turn directions, crossing kinds, maxspeed parsing,
/// sidewalk inference, the order of conflicts, and the sorted map.

import StreetGeom
@testable import Streets
import Testing

@Suite struct StreetsUnitTests {
    @Test func theRevision() {
        #expect(StreetsPort.source == "osm2streets fc119c4")
    }

    @Test func roadPositionParses() throws {
        #expect(try RoadPosition.parse("") == .center)
        #expect(try RoadPosition.parse("separation") == .separation)
        #expect(try RoadPosition.parse("left_of:1") == .leftOf(.forward(1)))
        #expect(try RoadPosition.parse("middle_of:1") == .middleOf(.forward(1)))
        #expect(try RoadPosition.parse("right_of:1") == .rightOf(.forward(1)))
        #expect(throws: (any Error).self) { try RoadPosition.parse("right_of:x") }
        #expect(throws: (any Error).self) { try RoadPosition.parse("bogus") }
    }

    @Test func placementParses() throws {
        #expect(try Placement.parse(Tags(["placement": "transition"])) == .transition)
        #expect(try Placement.parse(Tags(["placement": "right_of:1"])) == .consistent(.rightOf(.forward(1))))
        #expect(try Placement.parse(Tags(["placement:forward": "right_of:1"])) == .consistent(.rightOf(.forward(1))))
        #expect(try Placement.parse(Tags(["placement:backward": "right_of:1"])) == .consistent(.rightOf(.backward(1))))
        #expect(try Placement.parse(Tags(["placement:start": "right_of:1", "placement:end": "right_of:2"]))
            == .varying(.rightOf(.forward(1)), .rightOf(.forward(2))))
        #expect(try Placement.parse(Tags(["placement:backward:start": "right_of:1", "placement:backward:end": "right_of:2"]))
            == .varying(.rightOf(.backward(1)), .rightOf(.backward(2))))
    }

    @Test func crossingKindOrder() {
        #expect(CrossingKind.signalized > CrossingKind.marked)
    }

    @Test func parsesMaxspeed() {
        #expect(parseMaxspeed("0") == Speed.zero)
        #expect(parseMaxspeed("30.5") == Speed.kmPerHour(30.5))
        #expect(parseMaxspeed("30.5 mph") == Speed.milesPerHour(30.5))
        #expect(parseMaxspeed("30.5 mysteryunits") == nil)
        #expect(Speed.kmPerHour(30).rustDebug == "Speed(8.3333)")
    }

    @Test func turnDirectionsIterateInDeclarationOrder() {
        var set = TurnDirections()
        set.insert(.reverse)
        set.insert(.through)
        set.insert(.slightLeft)
        #expect(set.members.map { $0.tagValue() } == ["through", "slight_left", "reverse"])
    }

    @Test func infersSidewalks() {
        var cfg = MapConfig()
        cfg.inferredSidewalks = true
        func inferred(_ tags: [String: String], _ side: DrivingSide = .right) -> String? {
            var c = cfg
            c.drivingSide = side
            var t = Tags(tags)
            inferSidewalkTags(&t, c)
            return t.get("sidewalk")
        }
        #expect(inferred(["highway": "residential"]) == "both")
        #expect(inferred(["highway": "footway"]) == nil)
        #expect(inferred(["highway": "primary", "sidewalk:right": "no"]) == "left")
        #expect(inferred(["highway": "motorway"]) == "none")
        #expect(inferred(["highway": "primary", "oneway": "yes"]) == "right")
        #expect(inferred(["highway": "primary", "oneway": "yes"], .left) == "left")
        #expect(inferred(["highway": "residential", "oneway": "yes"]) == "both")
        #expect(inferred(["highway": "residential", "sidewalk": "no"]) == "no")
    }

    @Test func conflicts() {
        #expect(calcConflict((0, 1), (0, 1), .right) == .uncontested)
        #expect(calcConflict((0, 1), (0, 2), .right) == .diverge)
        #expect(calcConflict((0, 2), (1, 2), .right) == .merge)
        #expect(calcConflict((0, 2), (1, 3), .right) == .cross)
        #expect(calcConflict((0, 1), (2, 3), .right) == .uncontested)
    }

    @Test func tagsIterateInByteOrder() {
        let t = Tags(["b": "1", "a": "2", "B": "3", "é": "4", "z": "5"])
        #expect(t.inner().map(\.0) == ["B", "a", "b", "z", "é"])
    }

    @Test func sortedMapKeepsKeyOrder() {
        var m = SortedMap<Int, String>()
        for k in [5, 1, 3, 9, 7] { m[k] = "\(k)" }
        m.removeValue(forKey: 3)
        m[2] = "2"
        #expect(m.keys == [1, 2, 5, 7, 9])
        #expect(m.values == ["1", "2", "5", "7", "9"])
    }

    @Test func rustTieBreaking() {
        let xs = [(1, "a"), (3, "b"), (3, "c"), (0, "d")]
        #expect(xs.rustMaxByKey { $0.0 }?.1 == "c")
        #expect(xs.rustMinByKey { -$0.0 }?.1 == "b")
        #expect(xs.stableSorted { $0.0 }.map(\.1) == ["d", "a", "b", "c"])
        #expect(rustAsI64(.nan) == 0)
        #expect(rustAsI64(-1.9) == -1)
        #expect(wraparoundGet([1, 2, 3], -1) == 3)
    }
}
