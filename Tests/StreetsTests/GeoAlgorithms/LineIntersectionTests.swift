/// The tests of geo 0.27's `line_intersection.rs` (JTS's robust line intersector cases) and of
/// its documentation examples.

import GeoAlgorithms
import Testing

private func line(_ a: (Double, Double), _ b: (Double, Double)) -> GeoLine {
    GeoLine(geoC(a.0, a.1), geoC(b.0, b.1))
}

@Suite struct LineIntersectionTests {
    @Test func docExamples() {
        #expect(lineIntersection(line((0, 0), (5, 5)), line((0, 5), (5, 0)))
            == .singlePoint(intersection: geoC(2.5, 2.5), isProper: true))
        #expect(lineIntersection(line((0, 0), (5, 5)), line((0, 1), (5, 6))) == nil)
        #expect(lineIntersection(line((0, 0), (5, 5)), line((5, 5), (5, 0)))
            == .singlePoint(intersection: geoC(5, 5), isProper: false))
        #expect(lineIntersection(line((0, 0), (5, 5)), line((3, 3), (6, 6)))
            == .collinear(intersection: line((3, 3), (5, 5))))
    }

    @Test func centralEndpointHeuristicFailure1() {
        let actual = lineIntersection(
            line((163.81867067, -211.31840378), (165.9174252, -214.1665075)),
            line((2.84139601, -57.95412726), (469.59990601, -502.63851732)))
        #expect(actual == .singlePoint(intersection: geoC(163.81867067, -211.31840378), isProper: true))
    }

    @Test func centralEndpointHeuristicFailure2() {
        let actual = lineIntersection(
            line((-58.00593335955, -1.43739086465), (-513.86101637525, -457.29247388035)),
            line((-215.22279674875, -158.65425425385), (-218.1208801283, -160.68343590235)))
        #expect(actual == .singlePoint(intersection: geoC(-215.22279674875, -158.65425425385), isProper: true))
    }

    @Test func tomasFa1() {
        #expect(lineIntersection(line((-42.0, 163.2), (21.2, 265.2)), line((-26.2, 188.7), (37.0, 290.7))) == nil)
    }

    @Test func tomasFa2() {
        #expect(lineIntersection(line((-5.9, 163.1), (76.1, 250.7)), line((14.6, 185.0), (96.6, 272.6))) == nil)
    }

    @Test func leduc1() {
        let actual = lineIntersection(
            line((305690.0434123494, 254176.46578338774), (305601.9999843455, 254243.19999846347)),
            line((305689.6153764265, 254177.33102743194), (305692.4999844298, 254171.4999983967)))
        #expect(actual == .singlePoint(intersection: geoC(305690.0434123494, 254176.46578338774), isProper: true))
    }

    @Test func geos1() {
        let actual = lineIntersection(
            line((588750.7429703881, 4518950.493668233), (588748.2060409798, 4518933.9452804085)),
            line((588745.824857241, 4518940.742239175), (588748.2060437313, 4518933.9452791475)))
        #expect(actual == .singlePoint(intersection: geoC(588748.2060416829, 4518933.945284994), isProper: true))
    }

    @Test func geos2() {
        let actual = lineIntersection(
            line((588743.626135934, 4518924.610969561), (588732.2822865889, 4518925.4314047815)),
            line((588739.1191384895, 4518927.235700594), (588731.7854614238, 4518924.578370095)))
        #expect(actual == .singlePoint(intersection: geoC(588733.8306132929, 4518925.319423238), isProper: true))
    }

    @Test func daveSkeaCase() {
        let actual = lineIntersection(
            line((2089426.5233462777, 1180182.387733969), (2085646.6891757075, 1195618.7333999649)),
            line((1889281.8148903656, 1997547.0560044837), (2259977.3672236, 483675.17050843034)))
        #expect(actual == .singlePoint(intersection: geoC(2087536.6062609926, 1187900.560566967), isProper: true))
    }

    @Test func cmp5CaskWkt() {
        let actual = lineIntersection(
            line((4348433.262114629, 5552595.478385733), (4348440.849387404, 5552599.272022122)),
            line((4348433.26211463, 5552595.47838573), (4348440.8493874, 5552599.27202212)))
        #expect(actual == .singlePoint(intersection: geoC(4348440.8493874, 5552599.27202212), isProper: true))
    }
}
