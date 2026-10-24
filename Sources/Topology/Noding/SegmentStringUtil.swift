/// The lines of a geometry, rings included, as segment strings: JTS's
/// `SegmentStringUtil`.
public enum SegmentStringUtil {
    public static func extractSegmentStrings(_ geom: Geometry) -> [SegmentString] {
        LinearComponentExtracter.getLines(geom).map { NodedSegmentString($0.points, geom) }
    }
}
