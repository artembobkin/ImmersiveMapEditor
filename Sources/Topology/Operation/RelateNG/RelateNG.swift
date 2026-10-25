/// The topological relationship of two geometries, evaluated for one
/// predicate with no more work than it needs: the points and line ends and
/// area vertices of each geometry located in the other, then the edges'
/// intersections and the nodes they make: JTS's `RelateNG`, which GEOS 3.13
/// uses for its predicates (intersects, contains, within and the rest). A
/// prepared one keeps its first geometry's indexes for many evaluations.
///
/// As GEOS runs it: two empty inputs are evaluated as any others (JTS
/// returns the predicate's final value at once).
public final class RelateNG {
    private let boundaryNodeRule: BoundaryNodeRule
    private let geomA: RelateGeometry
    @exclusivity(unchecked) private var edgeMutualInt: MCIndexSegmentSetMutualIntersector?

    public static func relate(_ a: Geometry, _ b: Geometry, _ pred: TopologyPredicate) throws -> Bool {
        try RelateNG(a, false).evaluate(b, pred)
    }

    public static func relate(_ a: Geometry, _ b: Geometry, _ imPattern: String) throws -> Bool {
        try RelateNG(a, false).evaluate(b, imPattern)
    }

    public static func relate(_ a: Geometry, _ b: Geometry) throws -> IntersectionMatrix { try RelateNG(a, false).evaluate(b) }

    public static func prepare(_ a: Geometry) -> RelateNG { RelateNG(a, true) }

    public static func intersects(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.intersects()) }
    public static func contains(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.contains()) }
    public static func within(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.within()) }
    public static func covers(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.covers()) }
    public static func coveredBy(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.coveredBy()) }
    public static func crosses(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.crosses()) }
    public static func disjoint(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.disjoint()) }
    public static func equalsTopo(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.equalsTopo()) }
    public static func overlaps(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.overlaps()) }
    public static func touches(_ a: Geometry, _ b: Geometry) throws -> Bool { try relate(a, b, RelatePredicate.touches()) }

    private init(_ inputA: Geometry, _ isPrepared: Bool, _ bnRule: BoundaryNodeRule = .ogcSFS) {
        boundaryNodeRule = bnRule
        geomA = RelateGeometry(inputA, isPrepared, bnRule)
    }

    public func evaluate(_ b: Geometry) throws -> IntersectionMatrix {
        let rel = RelateMatrixPredicate()
        _ = try evaluate(b, rel)
        return rel.im
    }

    public func evaluate(_ b: Geometry, _ imPattern: String) throws -> Bool { try evaluate(b, RelatePredicate.matches(imPattern)) }

    public func intersects(_ b: Geometry) throws -> Bool { try evaluate(b, RelatePredicate.intersects()) }
    public func contains(_ b: Geometry) throws -> Bool { try evaluate(b, RelatePredicate.contains()) }
    public func within(_ b: Geometry) throws -> Bool { try evaluate(b, RelatePredicate.within()) }
    public func covers(_ b: Geometry) throws -> Bool { try evaluate(b, RelatePredicate.covers()) }
    public func coveredBy(_ b: Geometry) throws -> Bool { try evaluate(b, RelatePredicate.coveredBy()) }

    public func evaluate(_ b: Geometry, _ predicate: TopologyPredicate) throws -> Bool {
        if !hasRequiredEnvelopeInteraction(b, predicate) { return false }
        let geomB = RelateGeometry(b, false, boundaryNodeRule)
        let dimA = geomA.dimensionReal, dimB = geomB.dimensionReal
        predicate.initDimensions(dimA, dimB)
        if predicate.isKnown() { return finishValue(predicate) }
        predicate.initEnvelopes(geomA.envelope, geomB.envelope)
        if predicate.isKnown() { return finishValue(predicate) }
        let topoComputer = TopologyComputer(predicate, geomA, geomB)
        if dimA == Dimension.p && dimB == Dimension.p {
            computePP(geomB, topoComputer)
            topoComputer.finish()
            return topoComputer.getResult()
        }
        try computeAtPoints(geomB, RelateGeometry.geomB, geomA, topoComputer)
        if topoComputer.isResultKnown() { return topoComputer.getResult() }
        try computeAtPoints(geomA, RelateGeometry.geomA, geomB, topoComputer)
        if topoComputer.isResultKnown() { return topoComputer.getResult() }
        if geomA.hasEdges && geomB.hasEdges { computeAtEdges(geomB, topoComputer) }
        topoComputer.finish()
        return topoComputer.getResult()
    }

    private func hasRequiredEnvelopeInteraction(_ b: Geometry, _ predicate: TopologyPredicate) -> Bool {
        let envB = b.getEnvelopeInternal()
        var isInteracts = false
        if predicate.requireCovers(RelateGeometry.geomA) {
            if !geomA.envelope.covers(envB) { return false }
            isInteracts = true
        } else if predicate.requireCovers(RelateGeometry.geomB) {
            if !envB.covers(geomA.envelope) { return false }
            isInteracts = true
        }
        if !isInteracts && predicate.requireInteraction() && !geomA.envelope.intersects(envB) { return false }
        return true
    }

    private func finishValue(_ predicate: TopologyPredicate) -> Bool {
        predicate.finish()
        return predicate.value()
    }

    private func computePP(_ geomB: RelateGeometry, _ topoComputer: TopologyComputer) {
        let ptsA = geomA.getUniquePoints()
        let ptsB = geomB.getUniquePoints()
        var numBinA = 0
        for ptB in ptsB {
            if ptsA.contains(ptB) {
                numBinA += 1
                topoComputer.addPointOnPointInterior(ptB)
            } else {
                topoComputer.addPointOnPointExterior(RelateGeometry.geomB, ptB)
            }
            if topoComputer.isResultKnown() { return }
        }
        // Points of A not in B.
        if numBinA < ptsA.count { topoComputer.addPointOnPointExterior(RelateGeometry.geomA, nil) }
    }

    private func computeAtPoints(_ geom: RelateGeometry, _ isA: Bool, _ geomTarget: RelateGeometry, _ topoComputer: TopologyComputer) throws {
        if try computePoints(geom, isA, geomTarget, topoComputer) { return }
        // Disjoint points matter for areas, and for predicates that look at exteriors.
        let checkDisjointPoints = geomTarget.hasDimension(Dimension.a) || topoComputer.isExteriorCheckRequired(isA)
        if !checkDisjointPoints { return }
        if try computeLineEnds(geom, isA, geomTarget, topoComputer) { return }
        _ = try computeAreaVertex(geom, isA, geomTarget, topoComputer)
    }

    private func computePoints(_ geom: RelateGeometry, _ isA: Bool, _ geomTarget: RelateGeometry, _ topoComputer: TopologyComputer) throws -> Bool {
        if !geom.hasDimension(Dimension.p) { return false }
        for point in geom.getEffectivePoints() {
            guard let pt = point.getCoordinate() else { continue }
            try computePoint(isA, pt, geomTarget, topoComputer)
            if topoComputer.isResultKnown() { return true }
        }
        return false
    }

    private func computePoint(_ isA: Bool, _ pt: Coordinate, _ geomTarget: RelateGeometry, _ topoComputer: TopologyComputer) throws {
        let locDimTarget = geomTarget.locateWithDim(pt)
        let locTarget = DimensionLocation.location(locDimTarget)
        let dimTarget = DimensionLocation.dimension(locDimTarget, topoComputer.getDimension(!isA))
        try topoComputer.addPointOnGeometry(isA, locTarget, dimTarget, pt)
    }

    private func computeLineEnds(_ geom: RelateGeometry, _ isA: Bool, _ geomTarget: RelateGeometry, _ topoComputer: TopologyComputer) throws -> Bool {
        if !geom.hasDimension(Dimension.l) { return false }
        var hasExteriorIntersection = false
        for elem in RelateNG.elements(geom.geom) {
            if elem.isEmpty() { continue }
            guard let line = elem as? LineString else { continue }
            // Once a line end is outside, lines away from the target need no more looking at.
            if hasExteriorIntersection && elem.getEnvelopeInternal().disjoint(geomTarget.envelope) { continue }
            hasExteriorIntersection = try computeLineEnd(geom, isA, line.points[0], geomTarget, topoComputer) || hasExteriorIntersection
            if topoComputer.isResultKnown() { return true }
            if !line.isClosed() {
                hasExteriorIntersection = try computeLineEnd(geom, isA, line.points[line.points.count - 1], geomTarget, topoComputer)
                    || hasExteriorIntersection
                if topoComputer.isResultKnown() { return true }
            }
        }
        return false
    }

    /// The geometries in pre-order: JTS's `GeometryCollectionIterator`.
    private static func elements(_ g: Geometry) -> [Geometry] {
        var all: [Geometry] = []
        g.applyGeometries { all.append($0) }
        return all
    }

    /// A line end located in the other geometry; true when it is outside.
    private func computeLineEnd(_ geom: RelateGeometry, _ isA: Bool, _ pt: Coordinate, _ geomTarget: RelateGeometry,
                                _ topoComputer: TopologyComputer) throws -> Bool {
        let locDimLineEnd = geom.locateLineEndWithDim(pt)
        let dimLineEnd = DimensionLocation.dimension(locDimLineEnd, topoComputer.getDimension(isA))
        // A line end inside an area of its own geometry is not one.
        if dimLineEnd != Dimension.l { return false }
        let locLineEnd = DimensionLocation.location(locDimLineEnd)
        let locDimTarget = geomTarget.locateWithDim(pt)
        let locTarget = DimensionLocation.location(locDimTarget)
        let dimTarget = DimensionLocation.dimension(locDimTarget, topoComputer.getDimension(!isA))
        try topoComputer.addLineEndOnGeometry(isA, locLineEnd, locTarget, dimTarget, pt)
        return locTarget == Location.exterior
    }

    private func computeAreaVertex(_ geom: RelateGeometry, _ isA: Bool, _ geomTarget: RelateGeometry, _ topoComputer: TopologyComputer) throws -> Bool {
        if !geom.hasDimension(Dimension.a) { return false }
        // Area vertices tell nothing more about points.
        if geomTarget.dimension < Dimension.l { return false }
        var hasExteriorIntersection = false
        for elem in RelateNG.elements(geom.geom) {
            if elem.isEmpty() { continue }
            guard let poly = elem as? Polygon else { continue }
            if hasExteriorIntersection && elem.getEnvelopeInternal().disjoint(geomTarget.envelope) { continue }
            hasExteriorIntersection = try computeAreaVertex(geom, isA, poly.shell, geomTarget, topoComputer) || hasExteriorIntersection
            if topoComputer.isResultKnown() { return true }
            for hole in poly.holes {
                hasExteriorIntersection = try computeAreaVertex(geom, isA, hole, geomTarget, topoComputer) || hasExteriorIntersection
                if topoComputer.isResultKnown() { return true }
            }
        }
        return false
    }

    private func computeAreaVertex(_ geom: RelateGeometry, _ isA: Bool, _ ring: LinearRing, _ geomTarget: RelateGeometry,
                                   _ topoComputer: TopologyComputer) throws -> Bool {
        let pt = ring.getCoordinate()!
        let locArea = geom.locateAreaVertex(pt)
        let locDimTarget = geomTarget.locateWithDim(pt)
        let locTarget = DimensionLocation.location(locDimTarget)
        let dimTarget = DimensionLocation.dimension(locDimTarget, topoComputer.getDimension(!isA))
        try topoComputer.addAreaVertex(isA, locArea, locTarget, dimTarget, pt)
        return locTarget == Location.exterior
    }

    private func computeAtEdges(_ geomB: RelateGeometry, _ topoComputer: TopologyComputer) {
        let envInt = geomA.envelope.intersection(geomB.envelope)
        if envInt.isNull { return }
        let edgesB = geomB.extractSegmentStrings(RelateGeometry.geomB, envInt)
        let intersector = EdgeSegmentIntersector(topoComputer)
        if topoComputer.isSelfNodingRequired {
            let edgesA = geomA.extractSegmentStrings(RelateGeometry.geomA, envInt)
            EdgeSetIntersector(edgesA, edgesB, envInt).process(intersector)
        } else {
            if edgeMutualInt == nil {
                // A prepared geometry indexes all of its edges, once.
                let envExtract: Envelope? = geomA.isPrepared ? nil : envInt
                edgeMutualInt = MCIndexSegmentSetMutualIntersector(geomA.extractSegmentStrings(RelateGeometry.geomA, envExtract), envExtract)
            }
            edgeMutualInt!.process(edgesB, intersector)
        }
        if topoComputer.isResultKnown() { return }
        topoComputer.evaluateNodes()
    }
}
