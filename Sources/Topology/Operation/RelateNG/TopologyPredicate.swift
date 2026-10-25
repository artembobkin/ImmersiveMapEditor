/// A predicate RelateNG evaluates: what it needs of the inputs, and its
/// value as the topology is learned, known as soon as possible: JTS's
/// `TopologyPredicate`, `BasicPredicate` and `IMPredicate` (a class tree,
/// as JTS's).
public class TopologyPredicate {
    static let unknown = -1
    static let falseValue = 0
    static let trueValue = 1

    @exclusivity(unchecked) private var valueCode = TopologyPredicate.unknown

    /// Whether the edges of each input must be noded against themselves.
    func requireSelfNoding() -> Bool { true }
    /// Whether the value is false unless the inputs interact.
    func requireInteraction() -> Bool { true }
    /// Whether the value is false unless an input's envelope covers the other's.
    func requireCovers(_ isSourceA: Bool) -> Bool { false }
    /// Whether points of an input outside the other must be looked for.
    func requireExteriorCheck(_ isSourceA: Bool) -> Bool { true }
    func initDimensions(_ dimA: Int, _ dimB: Int) {}
    func initEnvelopes(_ envA: Envelope, _ envB: Envelope) {}
    func updateDimension(_ locA: Int, _ locB: Int, _ dimension: Int) { preconditionFailure("abstract") }
    func finish() { preconditionFailure("abstract") }

    func isKnown() -> Bool { valueCode > TopologyPredicate.unknown }
    func value() -> Bool { valueCode == TopologyPredicate.trueValue }

    static func isIntersection(_ locA: Int, _ locB: Int) -> Bool {
        locA != Location.exterior && locB != Location.exterior
    }

    func setValue(_ val: Bool) {
        if isKnown() { return }
        valueCode = val ? TopologyPredicate.trueValue : TopologyPredicate.falseValue
    }

    func setValueIf(_ value: Bool, _ cond: Bool) {
        if cond { setValue(value) }
    }

    func require(_ cond: Bool) {
        if !cond { setValue(false) }
    }

    func requireCovers(_ a: Envelope, _ b: Envelope) { require(a.covers(b)) }
}

/// A predicate decided on the intersection matrix as it is built: JTS's
/// `IMPredicate`.
public class IMPredicate: TopologyPredicate {
    static func isDimsCompatibleWithCovers(_ dim0: Int, _ dim1: Int) -> Bool {
        // A point covers a zero-length line.
        if dim0 == Dimension.p && dim1 == Dimension.l { return true }
        return dim0 >= dim1
    }

    static let dimUnknown = Dimension.dontCare

    @exclusivity(unchecked) var dimA = 0
    @exclusivity(unchecked) var dimB = 0
    @exclusivity(unchecked) var intMatrix = IntersectionMatrix()

    override init() {
        super.init()
        // The exteriors always intersect as areas.
        intMatrix.set(Location.exterior, Location.exterior, Dimension.a)
    }

    override func initDimensions(_ dimA: Int, _ dimB: Int) {
        self.dimA = dimA
        self.dimB = dimB
    }

    override func updateDimension(_ locA: Int, _ locB: Int, _ dimension: Int) {
        if dimension > intMatrix.get(locA, locB) {
            intMatrix.set(locA, locB, dimension)
            if isDetermined() { setValue(valueIM()) }
        }
    }

    func isDetermined() -> Bool { preconditionFailure("abstract") }
    func valueIM() -> Bool { preconditionFailure("abstract") }

    func intersectsExteriorOf(_ isA: Bool) -> Bool {
        if isA {
            return isIntersects(Location.exterior, Location.interior) || isIntersects(Location.exterior, Location.boundary)
        }
        return isIntersects(Location.interior, Location.exterior) || isIntersects(Location.boundary, Location.exterior)
    }

    func isIntersects(_ locA: Int, _ locB: Int) -> Bool { intMatrix.get(locA, locB) >= Dimension.p }
    func isDimension(_ locA: Int, _ locB: Int, _ dimension: Int) -> Bool { intMatrix.get(locA, locB) == dimension }
    func getDimension(_ locA: Int, _ locB: Int) -> Int { intMatrix.get(locA, locB) }

    override func finish() { setValue(valueIM()) }
}
