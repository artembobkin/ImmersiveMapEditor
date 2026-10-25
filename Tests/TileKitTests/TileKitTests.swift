import Foundation
import Geometry
import Testing
@testable import TileKit

/// The pipeline's parts that need no workspace: geometry through GEOS, the
/// road document's format, the projections, how tiles are cut into ranges.
@Suite struct TileKitTests {
    @Test func geosDoesTheOverlaysShapelyDid() {
        let a = Geometry.box(0, 0, 10, 10), b = Geometry.box(5, 5, 15, 15)
        #expect(a.union(b).area == 175)
        #expect(a.difference(b).area == 75)
        #expect(a.intersection(b).area == 25)
        #expect(abs(a.buffer(1, join: .mitre).area - 144) < 1e-9)
        #expect(Geometry.lineString([P2(0, 0), P2(10, 0)]).offsetCurve(1).coords == [P2(0, 1), P2(10, 1)])
        #expect(a.constrainedDelaunay().count == 2)
    }

    @Test func anSTRtreeFindsTheNearest() {
        let tree = STRtree([.box(0, 0, 1, 1), .box(10, 10, 11, 11)])
        #expect(tree.nearest(.point(9, 9)) == 1)
        #expect(tree.query(.point(0.5, 0.5)) == [0])
    }

    @Test func aRangeOfTilesIsCutIntoRectangles() {
        let ranges = Pipeline.rectangles([[1, 1], [2, 1], [3, 1], [1, 2], [2, 2], [5, 5]])
        #expect(ranges.map { [$0.0, $0.1, $0.2, $0.3] } == [[1, 1, 3, 1], [1, 2, 2, 2], [5, 5, 5, 5]])
    }

    @Test func aRegionProjectsBackAndForth() {
        let region = Region(z: 15, x0: 19808, y0: 10242, x1: 19809, y1: 10243)
        let p = region.metres(lat: 55.7539, lon: 37.6208)
        let (lon, lat) = region.lonLat(p)
        #expect(abs(lon - 37.6208) < 1e-10 && abs(lat - 55.7539) < 1e-10)
        // A tile of the range is about 690 m across at Moscow.
        let (a, b) = region.tileRect(x: 19808, y: 10243)
        #expect(abs((b.x - a.x) - 688.2) < 0.1)
    }

    @Test func theRoadDocumentReadsBackWhatItWrote() throws {
        var doc = RoadDocument(z: 15, x0: 1, y0: 2, x1: 1, y1: 2, seededDate: "2026-10-24T00:00:00+00:00",
                               seededRevision: "fc119c4")
        doc.areas = [.init(id: "a1", op: "add", outer: [P2(37.1, 55.1), P2(37.2, 55.1), P2(37.2, 55.2)], holes: [])]
        var zebra = Mark(kind: "zebra")
        zebra.id = "z1"
        zebra.centre = P2(37.15, 55.15)
        zebra.heading = 31.5
        zebra.span = 14.25
        doc.markings = [zebra]
        doc.shelters = [.init(id: "s1", position: P2(37.11, 55.11), heading: 75)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("road-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try doc.write(url)
        #expect(try RoadDocument.read(url).text() == doc.text())
        #expect(doc.text().contains("\"heading\": 31.5, \"span\": 14.25, \"bar\": 0.5, \"length\": 4}"))
    }

    @Test func workspacePathsFollowTheLayout() {
        let paths = WorkspacePaths(root: URL(fileURLWithPath: "/w"))
        #expect(paths.tile(z: 15, x: 19808, y: 10243).path == "/w/tiles/15/19808/10243")
        #expect(paths.tileData(z: 15, x: 19808, y: 10243).path == "/w/tiles/15/19808/10243/osm")
        #expect(paths.roadDocument(z: 15, x: 19808, y: 10243).path == "/w/tiles/15/19808/10243/roads/roads.json")
        #expect(paths.tileOut(z: 15, x: 19808, y: 10243).path == "/w/tiles/15/19808/10243/build")
    }

    @Test func aBakeSceneReadsBackWhatItWrote() throws {
        var mesh = Triangles()
        mesh.append([V3(0.1, -0.0, 1e-300), V3(.pi, 2, 3), V3(-689.5, 345.25, 12)], [P2(0.03125, 0.96875), P2(0.5, 0.5), P2(1, 0)],
                    .whole, (0, 21.5))
        mesh.append([V3(1, 1, 0.03), V3(2, 1, 0.03), V3(1, 2, 0.03)], [P2(0.1, 0.2), P2(0.3, 0.4), P2(0.5, 0.6)], .foreign, (3, 3))
        let scene = BakeScene(tile: [15, 19808, 10243], models: ["gum", "tsum"], stats: ["overhang_m": 16.4, "triangles_by_kind": ["walls": 7]],
                              region: (-345.1, -345.1, 345.1, 345.1), lit: (-401.5, -401.5, 401.5, 401.5), reach: 401.5, mesh: mesh)
        let back = try BakeScene(scene.encoded())
        #expect(back.tile == scene.tile && back.models == scene.models)
        #expect(back.mesh.pos.map(\.bitPattern) == mesh.pos.map(\.bitPattern))
        #expect(back.mesh.uv == mesh.uv && back.mesh.wall == mesh.wall && back.mesh.owner == mesh.owner)
        #expect(back.region == scene.region && back.lit == scene.lit && back.reach == scene.reach)
        #expect(back.stats["overhang_m"] as? Double == 16.4 && (back.stats["triangles_by_kind"] as? [String: Int]) == ["walls": 7])
        #expect(throws: PipelineError.self) { try BakeScene(Data("not a scene".utf8)) }
    }

    @Test func lightSettingsReadBackWhatTheyWrote() {
        var settings = Lighting.Settings()
        settings.size = 2048
        settings.bounces = 1
        settings.shade = [0.3, 0.3, 0.5]
        settings.gamma = 1.2
        let json = settings.json(lightMapPixels: 2544)
        #expect(Lighting.Settings(json: json) == settings)
        #expect(Lighting.Settings(json: [:]) == Lighting.Settings())
    }
}
