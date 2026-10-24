/// The boundary points of lines by a boundary node rule: their ends, by how
/// many ends meet at each: JTS's `LinearBoundary`.
struct LinearBoundary {
    private var vertexDegree: [Coordinate: Int] = [:]
    let hasBoundary: Bool
    private let boundaryNodeRule: BoundaryNodeRule

    init(_ lines: [LineString], _ bnRule: BoundaryNodeRule) {
        boundaryNodeRule = bnRule
        for line in lines where !line.isEmpty() {
            vertexDegree[line.points[0], default: 0] += 1
            vertexDegree[line.points[line.points.count - 1], default: 0] += 1
        }
        hasBoundary = vertexDegree.values.contains { bnRule.isInBoundary($0) }
    }

    func isBoundary(_ pt: Coordinate) -> Bool {
        guard let degree = vertexDegree[pt] else { return false }
        return boundaryNodeRule.isInBoundary(degree)
    }
}
