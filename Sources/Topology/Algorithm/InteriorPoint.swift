/// A point inside a geometry: JTS's `InteriorPoint` and its three cases by
/// dimension.
///
/// The dimension is the geometry's own (`getDimension`), as GEOS 3.13 takes
/// it: JTS 1.20 takes the highest dimension of the non-empty elements, so a
/// collection of an empty polygon and a line gives JTS the line's point and
/// GEOS an empty one (`TestInteriorPoint` 22 and 23 of the JTS suites).
public enum InteriorPoint {
    public static func getInteriorPoint(_ geom: Geometry) -> Coordinate? {
        if geom.isEmpty() { return nil }
        let dim = geom.getDimension()
        if dim < 0 { return nil }
        if dim == 0 { return InteriorPointPoint(geom).interiorPoint }
        if dim == 1 { return InteriorPointLine(geom).interiorPoint }
        return InteriorPointArea(geom).interiorPoint
    }
}
