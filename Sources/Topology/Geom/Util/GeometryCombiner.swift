/// Combines geometries into one, the members of a collection taken one by
/// one, as the most specific geometry: JTS's `GeometryCombiner`.
public enum GeometryCombiner {
    public static func combine(_ geoms: [Geometry]) -> Geometry {
        var elems: [Geometry] = []
        for g in geoms {
            for i in 0..<g.getNumGeometries() { elems.append(g.getGeometryN(i).copy()) }
        }
        let factory = geoms.first?.factory ?? .default
        return factory.buildGeometry(elems)
    }

    public static func combine(_ g0: Geometry, _ g1: Geometry) -> Geometry { combine([g0, g1]) }
}
