/// The one or two inputs of an overlay, with their point locators made
/// when first needed and whether their edges collapsed away in noding:
/// JTS's `InputGeometry`.
final class InputGeometry {
    private let geom: [Geometry?]
    @exclusivity(unchecked) private var ptLocatorA: PointOnGeometryLocator?
    @exclusivity(unchecked) private var ptLocatorB: PointOnGeometryLocator?
    @exclusivity(unchecked) private var isCollapsed = [false, false]

    init(_ geomA: Geometry, _ geomB: Geometry?) { geom = [geomA, geomB] }

    var isSingle: Bool { geom[1] == nil }

    func getDimension(_ index: Int) -> Int { geom[index]?.getDimension() ?? -1 }
    func getGeometry(_ geomIndex: Int) -> Geometry? { geom[geomIndex] }
    func getEnvelope(_ geomIndex: Int) -> Envelope { geom[geomIndex]!.getEnvelopeInternal() }
    func isEmpty(_ geomIndex: Int) -> Bool { geom[geomIndex]!.isEmpty() }
    func isArea(_ geomIndex: Int) -> Bool { geom[geomIndex] != nil && geom[geomIndex]!.getDimension() == 2 }

    /// The index of an areal input, -1 if none.
    func getAreaIndex() -> Int {
        if getDimension(0) == 2 { return 0 }
        if getDimension(1) == 2 { return 1 }
        return -1
    }

    func isLine(_ geomIndex: Int) -> Bool { getDimension(geomIndex) == 1 }
    var isAllPoints: Bool { getDimension(0) == 0 && geom[1] != nil && getDimension(1) == 0 }
    var hasPoints: Bool { getDimension(0) == 0 || getDimension(1) == 0 }

    /// Whether the input has edges, being linear or areal.
    func hasEdges(_ geomIndex: Int) -> Bool { geom[geomIndex] != nil && geom[geomIndex]!.getDimension() > 0 }

    /// The location of a point in an areal input: exterior if it collapsed.
    func locatePointInArea(_ geomIndex: Int, _ pt: Coordinate) -> Int {
        if isCollapsed[geomIndex] { return Location.exterior }
        // The indexed locator cannot take an empty polygon.
        if getGeometry(geomIndex)!.isEmpty() || isCollapsed[geomIndex] { return Location.exterior }
        return getLocator(geomIndex).locate(pt)
    }

    private func getLocator(_ geomIndex: Int) -> PointOnGeometryLocator {
        if geomIndex == 0 {
            if ptLocatorA == nil { ptLocatorA = IndexedPointInAreaLocator(getGeometry(geomIndex)!) }
            return ptLocatorA!
        }
        if ptLocatorB == nil { ptLocatorB = IndexedPointInAreaLocator(getGeometry(geomIndex)!) }
        return ptLocatorB!
    }

    func setCollapsed(_ geomIndex: Int, _ isGeomCollapsed: Bool) { isCollapsed[geomIndex] = isGeomCollapsed }
}
