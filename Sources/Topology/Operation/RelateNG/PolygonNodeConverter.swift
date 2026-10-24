/// Turns the sections of one polygon at a node where it touches itself
/// (rings meeting at a vertex) into sections each bounding one piece of its
/// interior, so the node's topology reads as for simple sections: JTS's
/// `PolygonNodeConverter`.
enum PolygonNodeConverter {
    static func convert(_ input: [NodeSection]) -> [NodeSection] {
        var polySections = input
        // GEOS sorts with libc++'s sort (JTS: a stable sort).
        CxxAlgorithms.sort(&polySections) { NodeSection.compareEdgeAngle($0, $1) < 0 }
        let sections = extractUnique(polySections)
        if sections.count == 1 { return sections }
        let shellIndex = findShell(sections)
        if shellIndex < 0 { return convertHoles(sections) }
        var convertedSections: [NodeSection] = []
        var nextShellIndex = shellIndex
        repeat {
            nextShellIndex = convertShellAndHoles(sections, nextShellIndex, &convertedSections)
        } while nextShellIndex != shellIndex
        return convertedSections
    }

    private static func convertShellAndHoles(_ sections: [NodeSection], _ shellIndex: Int,
                                             _ convertedSections: inout [NodeSection]) -> Int {
        let shellSection = sections[shellIndex]
        var inVertex = shellSection.getVertex(0)
        var i = next(sections, shellIndex)
        while !sections[i].isShell {
            let holeSection = sections[i]
            convertedSections.append(createSection(shellSection, inVertex, holeSection.getVertex(1)))
            inVertex = holeSection.getVertex(0)
            i = next(sections, i)
        }
        convertedSections.append(createSection(shellSection, inVertex, shellSection.getVertex(1)))
        return i
    }

    private static func convertHoles(_ sections: [NodeSection]) -> [NodeSection] {
        var convertedSections: [NodeSection] = []
        let copySection = sections[0]
        for i in 0..<sections.count {
            let inext = next(sections, i)
            convertedSections.append(createSection(copySection, sections[i].getVertex(0), sections[inext].getVertex(1)))
        }
        return convertedSections
    }

    private static func createSection(_ ns: NodeSection, _ v0: Coordinate?, _ v1: Coordinate?) -> NodeSection {
        NodeSection(ns.isA, Dimension.a, ns.id, 0, ns.poly, ns.isNodeAtVertex, v0, ns.nodePt, v1)
    }

    private static func extractUnique(_ sections: [NodeSection]) -> [NodeSection] {
        var uniqueSections: [NodeSection] = []
        var lastUnique = sections[0]
        uniqueSections.append(lastUnique)
        for ns in sections where lastUnique.compareTo(ns) != 0 {
            uniqueSections.append(ns)
            lastUnique = ns
        }
        return uniqueSections
    }

    private static func next(_ ns: [NodeSection], _ i: Int) -> Int { i + 1 >= ns.count ? 0 : i + 1 }

    private static func findShell(_ polySections: [NodeSection]) -> Int {
        polySections.firstIndex { $0.isShell } ?? -1
    }
}
