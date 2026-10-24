/// A rectangle from a base side and the points on the other sides: JTS's
/// `Rectangle`.
enum Rectangle {
    static func createFromSidePts(_ baseRightPt: Coordinate, _ baseLeftPt: Coordinate, _ oppositePt: Coordinate,
                                  _ leftSidePt: Coordinate, _ rightSidePt: Coordinate, _ factory: GeometryFactory) -> Polygon {
        let dx = baseLeftPt.x - baseRightPt.x
        let dy = baseLeftPt.y - baseRightPt.y
        let baseC = computeLineEquationC(dx, dy, baseRightPt)
        let oppC = computeLineEquationC(dx, dy, oppositePt)
        let leftC = computeLineEquationC(-dy, dx, leftSidePt)
        let rightC = computeLineEquationC(-dy, dx, rightSidePt)
        let baseLine = createLineForStandardEquation(-dy, dx, baseC)
        let oppLine = createLineForStandardEquation(-dy, dx, oppC)
        let leftLine = createLineForStandardEquation(-dx, -dy, leftC)
        let rightLine = createLineForStandardEquation(-dx, -dy, rightC)
        let p0 = rightSidePt.equals2D(baseRightPt) ? baseRightPt : baseLine.lineIntersection(rightLine)!
        let p1 = leftSidePt.equals2D(baseLeftPt) ? baseLeftPt : baseLine.lineIntersection(leftLine)!
        let p2 = leftSidePt.equals2D(oppositePt) ? oppositePt : oppLine.lineIntersection(leftLine)!
        let p3 = rightSidePt.equals2D(oppositePt) ? oppositePt : oppLine.lineIntersection(rightLine)!
        return factory.createPolygon(factory.createLinearRing([p0, p1, p2, p3, p0]))
    }

    static func computeLineEquationC(_ a: Double, _ b: Double, _ p: Coordinate) -> Double {
        fusedSub(a, p.y, b * p.x)
    }

    static func createLineForStandardEquation(_ a: Double, _ b: Double, _ c: Double) -> LineSegment {
        if abs(b) > abs(a) {
            return LineSegment(Coordinate(0.0, c / b), Coordinate(1.0, c / b - a / b))
        }
        return LineSegment(Coordinate(c / a, 0.0), Coordinate(c / a - b / a, 1.0))
    }
}
