/// The line strings of a geometry, rings included, in the order of its
/// components: JTS's `LinearComponentExtracter`.
public enum LinearComponentExtracter {
    public static func getLines(_ g: Geometry) -> [LineString] {
        var lines: [LineString] = []
        g.applyComponents { c in
            if let l = c as? LineString { lines.append(l) }
        }
        return lines
    }
}
