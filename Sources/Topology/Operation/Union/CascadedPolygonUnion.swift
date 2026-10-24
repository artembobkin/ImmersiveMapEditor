/// The union of many polygons by unioning neighbours in pairs, then the
/// pairs, and so on: JTS's `CascadedPolygonUnion`, in the form GEOS 3.13
/// gives its results. GEOS packs the polygons in an STR tree of node
/// capacity 10 and unions the tree's items in their packed order by halving
/// the list (JTS: a tree of capacity 4, unioned node by node), and each
/// union's result is restricted to its polygons.
public final class CascadedPolygonUnion {
    private static let strTreeNodeCapacity = 10

    private let inputPolys: [Polygon]
    private let unionFunction: UnionStrategy

    public static func union(_ polys: [Polygon], _ unionFun: UnionStrategy = .classic) throws -> Geometry? {
        try CascadedPolygonUnion(polys, unionFun).union()
    }

    public init(_ polys: [Polygon], _ unionFun: UnionStrategy = .classic) {
        inputPolys = polys
        unionFunction = unionFun
    }

    /// The union, nil for no polygons (or only empty ones, which the tree
    /// does not index).
    public func union() throws -> Geometry? {
        if inputPolys.isEmpty { return nil }
        let index = STRtree<Polygon>(nodeCapacity: CascadedPolygonUnion.strTreeNodeCapacity)
        for p in inputPolys { index.insert(p.getEnvelopeInternal(), p) }
        let geoms = index.itemsInPackedOrder()
        return try binaryUnion(geoms, 0, geoms.count)
    }

    private func binaryUnion(_ geoms: [Polygon], _ start: Int, _ end: Int) throws -> Geometry? {
        switch end - start {
        case 0: return nil
        case 1: return geoms[start].copy()
        case 2: return try unionActual(geoms[start], geoms[start + 1])
        default:
            let mid = (end + start) / 2
            let g0 = try binaryUnion(geoms, start, mid)
            let g1 = try binaryUnion(geoms, mid, end)
            guard let g0 else { return g1 }
            guard let g1 else { return g0 }
            return try unionActual(g0, g1)
        }
    }

    private func unionActual(_ g0: Geometry, _ g1: Geometry) throws -> Geometry {
        CascadedPolygonUnion.restrictToPolygons(try unionFunction.union(g0, g1))
    }

    /// The polygonal part of a result: itself if polygonal, the polygons of
    /// a collection as a multipolygon, else an empty polygon.
    static func restrictToPolygons(_ g: Geometry) -> Geometry {
        if g is Polygon || g is MultiPolygon { return g }
        if let gc = g as? GeometryCollection {
            return g.factory.createMultiPolygon(gc.geometries.compactMap { $0 as? Polygon ?? nil })
        }
        return g.factory.createPolygon()
    }
}
