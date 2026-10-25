/// The named predicates of RelateNG: JTS's `RelatePredicate` (anonymous
/// classes there, named classes here).
public enum RelatePredicate {
    public static func intersects() -> TopologyPredicate { IntersectsPredicate() }
    public static func disjoint() -> TopologyPredicate { DisjointPredicate() }
    public static func contains() -> TopologyPredicate { ContainsPredicate() }
    public static func within() -> TopologyPredicate { WithinPredicate() }
    public static func covers() -> TopologyPredicate { CoversPredicate() }
    public static func coveredBy() -> TopologyPredicate { CoveredByPredicate() }
    public static func crosses() -> TopologyPredicate { CrossesPredicate() }
    public static func equalsTopo() -> TopologyPredicate { EqualsTopoPredicate() }
    public static func overlaps() -> TopologyPredicate { OverlapsPredicate() }
    public static func touches() -> TopologyPredicate { TouchesPredicate() }
    public static func matches(_ imPattern: String) -> TopologyPredicate { IMPatternMatcher(imPattern) }
}

final class IntersectsPredicate: TopologyPredicate {
    override func requireSelfNoding() -> Bool { false }
    override func requireExteriorCheck(_ isSourceA: Bool) -> Bool { false }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) { require(envA.intersects(envB)) }
    override func updateDimension(_ locA: Int, _ locB: Int, _ dimension: Int) {
        setValueIf(true, TopologyPredicate.isIntersection(locA, locB))
    }
    override func finish() { setValue(false) }
}

final class DisjointPredicate: TopologyPredicate {
    override func requireSelfNoding() -> Bool { false }
    override func requireInteraction() -> Bool { false }
    override func requireExteriorCheck(_ isSourceA: Bool) -> Bool { false }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) { setValueIf(true, envA.disjoint(envB)) }
    override func updateDimension(_ locA: Int, _ locB: Int, _ dimension: Int) {
        setValueIf(false, TopologyPredicate.isIntersection(locA, locB))
    }
    override func finish() { setValue(true) }
}

final class ContainsPredicate: IMPredicate {
    override func requireCovers(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomA }
    override func requireExteriorCheck(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomB }
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        require(IMPredicate.isDimsCompatibleWithCovers(dimA, dimB))
    }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) { requireCovers(envA, envB) }
    override func isDetermined() -> Bool { intersectsExteriorOf(RelateGeometry.geomA) }
    override func valueIM() -> Bool { intMatrix.isContains() }
}

final class WithinPredicate: IMPredicate {
    override func requireCovers(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomB }
    override func requireExteriorCheck(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomA }
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        require(IMPredicate.isDimsCompatibleWithCovers(dimB, dimA))
    }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) { requireCovers(envB, envA) }
    override func isDetermined() -> Bool { intersectsExteriorOf(RelateGeometry.geomB) }
    override func valueIM() -> Bool { intMatrix.isWithin() }
}

final class CoversPredicate: IMPredicate {
    override func requireCovers(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomA }
    override func requireExteriorCheck(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomB }
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        require(IMPredicate.isDimsCompatibleWithCovers(dimA, dimB))
    }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) { requireCovers(envA, envB) }
    override func isDetermined() -> Bool { intersectsExteriorOf(RelateGeometry.geomA) }
    override func valueIM() -> Bool { intMatrix.isCovers() }
}

final class CoveredByPredicate: IMPredicate {
    override func requireCovers(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomB }
    override func requireExteriorCheck(_ isSourceA: Bool) -> Bool { isSourceA == RelateGeometry.geomA }
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        require(IMPredicate.isDimsCompatibleWithCovers(dimB, dimA))
    }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) { requireCovers(envB, envA) }
    override func isDetermined() -> Bool { intersectsExteriorOf(RelateGeometry.geomB) }
    override func valueIM() -> Bool { intMatrix.isCoveredBy() }
}

final class CrossesPredicate: IMPredicate {
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        let isBothPointsOrAreas = (dimA == Dimension.p && dimB == Dimension.p) || (dimA == Dimension.a && dimB == Dimension.a)
        require(!isBothPointsOrAreas)
    }
    override func isDetermined() -> Bool {
        if dimA == Dimension.l && dimB == Dimension.l {
            if getDimension(Location.interior, Location.interior) > Dimension.p { return true }
        } else if dimA < dimB {
            if isIntersects(Location.interior, Location.interior) && isIntersects(Location.interior, Location.exterior) { return true }
        } else if dimA > dimB {
            if isIntersects(Location.interior, Location.interior) && isIntersects(Location.exterior, Location.interior) { return true }
        }
        return false
    }
    override func valueIM() -> Bool { intMatrix.isCrosses(dimA, dimB) }
}

/// As GEOS 3.13 has it: two empty geometries are equal whatever their
/// dimensions (JTS requires equal dimensions and interaction).
final class EqualsTopoPredicate: IMPredicate {
    override func requireInteraction() -> Bool { false }
    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) {
        setValueIf(true, envA.isNull && envB.isNull)
        require(envA == envB)
    }
    override func isDetermined() -> Bool {
        isIntersects(Location.interior, Location.exterior) || isIntersects(Location.boundary, Location.exterior)
            || isIntersects(Location.exterior, Location.interior) || isIntersects(Location.exterior, Location.boundary)
    }
    override func valueIM() -> Bool { intMatrix.isEquals(dimA, dimB) }
}

final class OverlapsPredicate: IMPredicate {
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        require(dimA == dimB)
    }
    override func isDetermined() -> Bool {
        if dimA == Dimension.a || dimA == Dimension.p {
            if isIntersects(Location.interior, Location.interior) && isIntersects(Location.interior, Location.exterior)
                && isIntersects(Location.exterior, Location.interior) { return true }
        }
        if dimA == Dimension.l {
            if isDimension(Location.interior, Location.interior, Dimension.l) && isIntersects(Location.interior, Location.exterior)
                && isIntersects(Location.exterior, Location.interior) { return true }
        }
        return false
    }
    override func valueIM() -> Bool { intMatrix.isOverlaps(dimA, dimB) }
}

final class TouchesPredicate: IMPredicate {
    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        super.initDimensions(dimA, dimB)
        require(!(dimA == 0 && dimB == 0))
    }
    override func isDetermined() -> Bool { isIntersects(Location.interior, Location.interior) }
    override func valueIM() -> Bool { intMatrix.isTouches(dimA, dimB) }
}

/// A predicate of a DE-9IM pattern: JTS's `IMPatternMatcher`.
final class IMPatternMatcher: IMPredicate {
    private let imPattern: String
    private let patternMatrix: IntersectionMatrix

    init(_ imPattern: String) {
        self.imPattern = imPattern
        patternMatrix = IntersectionMatrix(imPattern)
    }

    override func initEnvelopes(_ envA: Envelope, _ envB: Envelope) {
        // JTS calls super.init(dimA, dimB) here, with the dimensions it has.
        super.initDimensions(dimA, dimB)
        setValueIf(false, IMPatternMatcher.requireInteraction(patternMatrix) && envA.disjoint(envB))
    }

    override func requireInteraction() -> Bool { IMPatternMatcher.requireInteraction(patternMatrix) }

    private static func requireInteraction(_ im: IntersectionMatrix) -> Bool {
        isInteraction(im.get(Location.interior, Location.interior)) || isInteraction(im.get(Location.interior, Location.boundary))
            || isInteraction(im.get(Location.boundary, Location.interior)) || isInteraction(im.get(Location.boundary, Location.boundary))
    }

    private static func isInteraction(_ imDim: Int) -> Bool { imDim == Dimension.true || imDim >= Dimension.p }

    override func isDetermined() -> Bool {
        for i in 0..<3 {
            for j in 0..<3 {
                let patternEntry = patternMatrix.get(i, j)
                if patternEntry == Dimension.dontCare { continue }
                let matrixVal = getDimension(i, j)
                if patternEntry == Dimension.true {
                    if matrixVal < 0 { return false }
                } else if matrixVal > patternEntry {
                    return true
                }
            }
        }
        return false
    }

    override func valueIM() -> Bool { intMatrix.matches(imPattern) }
}

/// The predicate that only builds the whole matrix: JTS's `RelateMatrixPredicate`.
final class RelateMatrixPredicate: IMPredicate {
    override func requireInteraction() -> Bool { false }
    override func isDetermined() -> Bool { false }
    override func valueIM() -> Bool { false }
    var im: IntersectionMatrix { intMatrix }
}
