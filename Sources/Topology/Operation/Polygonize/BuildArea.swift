/// Builds the area enclosed by fully noded linework, as GEOS 3.13's
/// `BuildArea` does (the algorithm of PostGIS's `ST_BuildArea`; JTS has no
/// such class): the linework is polygonized, each face that is a hole of
/// another (its shell equal to that face's hole ring, either way round)
/// gets that face as its parent, the faces with an even number of
/// ancestors are kept, and their union dissolves the edges they share.
///
/// Written for this port from the algorithm, on the port's polygonizer and
/// cascaded union, with GEOS's orders: the faces sorted by envelope area,
/// largest first, with libc++'s `std::sort`.
public enum BuildArea {
    final class Face {
        let poly: Polygon
        let envarea: Double
        @exclusivity(unchecked) var parent: Face?

        init(_ poly: Polygon) {
            self.poly = poly
            envarea = poly.getEnvelope().getArea()
        }

        func countParents() -> Int {
            var pcount = 0
            var f = parent
            while let p = f {
                pcount += 1
                f = p.parent
            }
            return pcount
        }
    }

    public static func build(_ geom: Geometry) throws -> Geometry {
        let polygonizer = Polygonizer()
        polygonizer.add(geom)
        let polys = try polygonizer.getPolygons()
        if polys.isEmpty { return GeometryFactory.default.createGeometryCollection() }
        if polys.count == 1 { return polys[0] }
        // Each face with holes has other faces for its holes: keeping the
        // faces of an even number of ancestors keeps as many rings visible
        // as possible.
        var faces = polys.map(Face.init)
        findFaceHoles(&faces)
        let tmp = GeometryFactory.default.createMultiPolygon(faces.filter { $0.countParents() % 2 == 0 }.map { $0.poly.copy() as! Polygon })
        // One overlay dissolves the edges the faces share.
        guard let shp = try CascadedPolygonUnion.union(tmp.geometries.map { $0 as! Polygon }) else {
            throw IllegalStateException("BuildArea: no faces to union")
        }
        return shp
    }

    /// Sorts the faces by envelope area, largest first (holes come after
    /// their shells), and gives each face whose shell is a hole of an
    /// earlier face that face as its parent.
    private static func findFaceHoles(_ faces: inout [Face]) {
        CxxAlgorithms.sort(&faces) { $0.envarea > $1.envarea }
        for i in 0..<faces.count {
            let f = faces[i]
            for hole in f.poly.holes {
                for j in (i + 1)..<max(i + 1, faces.count) {
                    let f2 = faces[j]
                    if f2.parent != nil { continue } // hole already assigned
                    if ringsEqualAnyDirection(f2.poly.shell, hole) {
                        f2.parent = f
                        break
                    }
                }
            }
        }
    }

    /// Whether two rings have the same points in the same cyclic order,
    /// either way round.
    static func ringsEqualAnyDirection(_ r1: LinearRing, _ r2: LinearRing) -> Bool {
        let cs1 = r1.points, cs2 = r2.points
        var npoints = cs1.count
        if npoints != cs2.count { return false }
        if npoints == 0 { return true }
        if r1.getEnvelopeInternal() != r2.getEnvelopeInternal() { return false }
        // The last point repeats the first.
        npoints -= 1
        guard let offset = cs2.firstIndex(of: cs1[0]) else { return false }
        var equal = true
        // forward, the first point checked already
        for i in 1..<max(1, npoints) {
            let j = (i + offset) % npoints
            if !cs1[i].equals2D(cs2[j]) {
                equal = false
                break
            }
        }
        if equal { return true }
        // backward
        equal = true
        for i in 1..<max(1, npoints) {
            let j = i <= offset ? offset - i : npoints - (i - offset)
            if !cs1[i].equals2D(cs2[j]) {
                equal = false
                break
            }
        }
        return equal
    }
}
