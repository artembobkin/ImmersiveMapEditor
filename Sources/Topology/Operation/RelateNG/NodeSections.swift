/// The sections of the edges of both geometries at one node, turned into a
/// node of edges: JTS's `NodeSections`. The sections are sorted with
/// libc++'s sort, as GEOS sorts them (JTS: a stable sort).
final class NodeSections {
    let nodePt: Coordinate
    @exclusivity(unchecked) private var sections: [NodeSection] = []

    init(_ pt: Coordinate) { nodePt = pt }

    func addNodeSection(_ e: NodeSection) { sections.append(e) }

    func hasInteractionAB() -> Bool {
        var isA = false, isB = false
        for ns in sections {
            if ns.isA { isA = true } else { isB = true }
            if isA && isB { return true }
        }
        return false
    }

    /// The polygonal of the first section of a geometry that has one.
    func getPolygonal(_ isA: Bool) -> Geometry? {
        for ns in sections where ns.isA == isA {
            if let poly = ns.poly { return poly }
        }
        return nil
    }

    func createNode() -> RelateNode {
        CxxAlgorithms.sort(&sections) { $0.compareTo($1) < 0 }
        let node = RelateNode(nodePt)
        var i = 0
        while i < sections.count {
            let ns = sections[i]
            if ns.isArea && NodeSections.hasMultiplePolygonSections(sections, i) {
                let polySections = NodeSections.collectPolygonSections(sections, i)
                node.addEdges(PolygonNodeConverter.convert(polySections))
                i += polySections.count
            } else {
                node.addEdges(ns)
                i += 1
            }
        }
        return node
    }

    private static func hasMultiplePolygonSections(_ sections: [NodeSection], _ i: Int) -> Bool {
        if i >= sections.count - 1 { return false }
        return sections[i].isSamePolygon(sections[i + 1])
    }

    private static func collectPolygonSections(_ sections: [NodeSection], _ start: Int) -> [NodeSection] {
        var polySections: [NodeSection] = []
        let polySection = sections[start]
        var i = start
        while i < sections.count && polySection.isSamePolygon(sections[i]) {
            polySections.append(sections[i])
            i += 1
        }
        return polySections
    }
}
