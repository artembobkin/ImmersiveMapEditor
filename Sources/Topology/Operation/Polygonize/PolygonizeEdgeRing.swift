extension Polygonize {
    /// A ring of the polygonizer's graph, a shell or a hole: JTS's
    /// `polygonize.EdgeRing`.
    ///
    /// The shell containing a hole is found as GEOS 3.13 finds it: a shell
    /// of the same envelope is skipped, the shell's envelope must contain
    /// the hole's (JTS: contain it properly), and the hole's first point not
    /// on the shell must not be outside it (JTS: the first point in or out
    /// decides).
    final class EdgeRing {
        static func findDirEdgesInRing(_ startDE: PolygonizeDirectedEdge) throws -> [PolygonizeDirectedEdge] {
            var de = startDE
            var edges: [PolygonizeDirectedEdge] = []
            repeat {
                edges.append(de)
                guard let n = de.next else { throw AssertionFailedException("found null DE in ring") }
                de = n
            } while de !== startDE
            return edges
        }

        let factory: GeometryFactory
        @exclusivity(unchecked) private(set) var deList: [PolygonizeDirectedEdge] = []
        @exclusivity(unchecked) private var ring: LinearRing?
        @exclusivity(unchecked) private var locator: IndexedPointInAreaLocator?
        @exclusivity(unchecked) private var ringPts: [Coordinate]?
        @exclusivity(unchecked) var holes: [LinearRing]?
        @exclusivity(unchecked) unowned(unsafe) var shell: EdgeRing?
        @exclusivity(unchecked) private(set) var isHole = false
        @exclusivity(unchecked) private(set) var isValid = false
        @exclusivity(unchecked) var isProcessed = false
        @exclusivity(unchecked) private(set) var isIncludedSet = false
        @exclusivity(unchecked) private(set) var isIncluded = false
        @exclusivity(unchecked) var visitedByUpdateIncludedRecursive = false

        init(_ factory: GeometryFactory) { self.factory = factory }

        func build(_ startDE: PolygonizeDirectedEdge) throws {
            var de = startDE
            repeat {
                deList.append(de)
                de.edgeRing = self
                guard let n = de.next else { throw AssertionFailedException("found null DE in ring") }
                de = n
            } while de !== startDE
        }

        func computeHole() {
            isHole = Orientation.isCCW(getRing().points)
        }

        func addHole(_ holeER: EdgeRing) {
            holeER.shell = self
            if holes == nil { holes = [] }
            holes!.append(holeER.getRing())
        }

        func getPolygon() -> Polygon { factory.createPolygon(getRing(), holes ?? []) }

        func computeValid() throws {
            let pts = getCoordinates()
            if pts.count <= 3 {
                isValid = false
                return
            }
            isValid = try getRing().isValid()
        }

        func setIncluded(_ included: Bool) {
            isIncluded = included
            isIncludedSet = true
        }

        private func getLocator() -> IndexedPointInAreaLocator {
            if let locator { return locator }
            let l = IndexedPointInAreaLocator(getRing())
            locator = l
            return l
        }

        func isInRing(_ pt: Coordinate) -> Bool { getLocator().locate(pt) != Location.exterior }

        /// The innermost of the shells containing this hole, if any.
        func findEdgeRingContaining(_ erList: [EdgeRing]) -> EdgeRing? {
            let testRing = getRing()
            let testEnv = testRing.getEnvelopeInternal()
            var minRing: EdgeRing?
            var minRingEnv: Envelope?
            for tryEdgeRing in erList {
                let tryRing = tryEdgeRing.getRing()
                let tryShellEnv = tryRing.getEnvelopeInternal()
                if tryShellEnv == testEnv { continue }
                if !tryShellEnv.contains(testEnv) { continue }
                let testPt = EdgeRing.ptNotInList(testRing.points, tryRing.points)
                if tryEdgeRing.isInRing(testPt) {
                    if minRing == nil || minRingEnv!.contains(tryShellEnv) {
                        minRing = tryEdgeRing
                        minRingEnv = tryShellEnv
                    }
                }
            }
            return minRing
        }

        /// The first of the points not in the list, else GEOS's null coordinate.
        static func ptNotInList(_ testPts: [Coordinate], _ pts: [Coordinate]) -> Coordinate {
            for testPt in testPts where !pts.contains(testPt) { return testPt }
            return .null
        }

        func getCoordinates() -> [Coordinate] {
            if let ringPts { return ringPts }
            var coordList = CoordinateList()
            for de in deList { coordList.add(de.line.points, false, de.getEdgeDirection()) }
            ringPts = coordList.points
            return coordList.points
        }

        func getLineString() -> LineString { factory.createLineString(getCoordinates()) }

        /// The ring of the coordinates (closed, as the graph's rings are).
        func getRing() -> LinearRing {
            if let ring { return ring }
            let r = factory.createLinearRing(getCoordinates())
            ring = r
            return r
        }

        func getShell() -> EdgeRing? { isHole ? shell : self }
        func isOuterHole() -> Bool { isHole && shell == nil }

        func getOuterHole() -> EdgeRing? {
            if isHole { return nil }
            for de in deList {
                let adjRing = de.pSym.edgeRing!
                if adjRing.isOuterHole() { return adjRing }
            }
            return nil
        }

        /// GEOS's recursive update of the shells to include.
        func updateIncludedRecursive() {
            visitedByUpdateIncludedRecursive = true
            if isHole { return }
            for de in deList {
                if let adjShell = de.pSym.edgeRing?.getShell(), !adjShell.isIncludedSet && !adjShell.visitedByUpdateIncludedRecursive {
                    adjShell.updateIncludedRecursive()
                }
            }
            for de in deList {
                if let adjShell = de.pSym.edgeRing?.getShell(), adjShell.isIncludedSet {
                    setIncluded(!adjShell.isIncluded)
                    return
                }
            }
        }
    }
}
