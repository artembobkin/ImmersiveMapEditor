/// The transformations the Rust binary does not run, checked on small
/// made-up networks: removing disconnected roads and the driving path that
/// zipping sidepaths stands on.

import StreetGeom
@testable import Streets
import Testing

/// Two lanes each way for roads, one lane for anything else.
private struct SimpleLanes: LaneSpecSource {
    func laneSpecsLTR(_ tags: Tags, _ config: MapConfig) -> [LaneSpec] {
        if tags.is("highway", "cycleway") {
            return [LaneSpec(lt: .biking, dir: .forward, width: .meters(2))]
        }
        return [LaneSpec(lt: .driving, dir: .backward, width: .meters(3)),
                LaneSpec(lt: .driving, dir: .forward, width: .meters(3))]
    }
}

private func network(_ ways: [[(Double, Double)]], highway: [String]) throws -> StreetNetwork {
    var xml = "<?xml version=\"1.0\"?>\n<osm>\n<bounds minlat=\"0\" minlon=\"0\" maxlat=\"0.01\" maxlon=\"0.01\"/>\n"
    var id = 0
    var refs: [[Int]] = []
    var seen: [String: Int] = [:]
    for way in ways {
        var r: [Int] = []
        for (lon, lat) in way {
            let key = "\(lon),\(lat)"
            if let existing = seen[key] { r.append(existing); continue }
            id += 1
            seen[key] = id
            xml += "<node id=\"\(id)\" lat=\"\(lat)\" lon=\"\(lon)\"/>\n"
            r.append(id)
        }
        refs.append(r)
    }
    for (k, r) in refs.enumerated() {
        xml += "<way id=\"\(k + 1)\">" + r.map { "<nd ref=\"\($0)\"/>" }.joined() + "<tag k=\"highway\" v=\"\(highway[k])\"/></way>\n"
    }
    xml += "</osm>\n"
    return try StreetNetwork.fromOSM(Array(xml.utf8), clip: nil, config: MapConfig(), laneSpecs: SimpleLanes())
}

@Suite struct TransformationTests {
    @Test func removesTheSmallerGroups() throws {
        var s = try network([
            [(0.001, 0.001), (0.002, 0.001)], [(0.002, 0.001), (0.003, 0.001)], [(0.003, 0.001), (0.004, 0.001)],
            [(0.001, 0.008), (0.002, 0.008)],
        ], highway: ["residential", "residential", "residential", "residential"])
        #expect(s.roads.count == 4)
        s.applyTransformations([.removeDisconnectedRoads])
        #expect(s.roads.values.map { $0.osmIDs[0].id } == [1, 2, 3])
        #expect(s.intersections.count == 4)
        s.checkInvariants()
    }

    @Test func findsTheShortestDrivingPath() throws {
        // A square of roads, one side much longer around: the path takes the short way.
        let s = try network([
            [(0.001, 0.001), (0.005, 0.001)], [(0.005, 0.001), (0.005, 0.002)],
            [(0.001, 0.001), (0.001, 0.009)], [(0.001, 0.009), (0.005, 0.009)], [(0.005, 0.009), (0.005, 0.002)],
        ], highway: ["residential", "residential", "residential", "residential", "residential"])
        let start = s.intersections.values.first { $0.osmIDs.map(\.id) == [1] }!.id
        let end = s.intersections.values.first { $0.osmIDs.map(\.id) == [3] }!.id
        let path = s.simplePath(start, end, [.driving])!
        #expect(path.map { s.roads[$0.0]!.osmIDs[0].id } == [1, 2])
        #expect(path.map(\.1) == [.forward, .forward])
        let back = s.simplePath(end, start, [.driving])!
        #expect(back.map(\.1) == [.backward, .backward])
        #expect(s.simplePath(start, end, [.bus]) == nil)
    }
}
