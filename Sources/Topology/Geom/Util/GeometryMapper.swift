/// Maps the elements of a geometry through a function: JTS's
/// `GeometryMapper.flatMap`, as GEOS 3.13 has it. Collections are entered,
/// the results flattened, empty results dropped; no result is the empty
/// geometry of a given dimension, one result is itself.
public enum GeometryMapper {
    public static func flatMap(_ geom: Geometry, _ emptyDim: Int, _ op: (Geometry) throws -> Geometry?) rethrows -> Geometry {
        var mapped: [Geometry] = []
        try flatMap(geom, op, &mapped)
        if mapped.isEmpty { return geom.factory.createEmpty(emptyDim) }
        if mapped.count == 1 { return mapped[0] }
        return geom.factory.buildGeometry(mapped)
    }

    private static func flatMap(_ geom: Geometry, _ op: (Geometry) throws -> Geometry?, _ mapped: inout [Geometry]) rethrows {
        for i in 0..<geom.getNumGeometries() {
            let g = geom.getGeometryN(i)
            if g is GeometryCollection {
                try flatMap(g, op, &mapped)
            } else if let res = try op(g), !res.isEmpty() {
                addFlat(res, &mapped)
            }
        }
    }

    private static func addFlat(_ geom: Geometry, _ geomList: inout [Geometry]) {
        if geom.isEmpty() { return }
        if geom is GeometryCollection {
            for i in 0..<geom.getNumGeometries() { addFlat(geom.getGeometryN(i), &geomList) }
        } else {
            geomList.append(geom)
        }
    }
}
