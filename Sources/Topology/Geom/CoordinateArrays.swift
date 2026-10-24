/// Operations on coordinate arrays: JTS's `CoordinateArrays`.
public enum CoordinateArrays {
    /// Whether two coordinates in a row are equal.
    public static func hasRepeatedPoints(_ c: [Coordinate]) -> Bool {
        if c.count < 2 { return false }
        for i in 1..<c.count where c[i - 1] == c[i] { return true }
        return false
    }

    /// The coordinates without consecutive repeats.
    public static func removeRepeatedPoints(_ c: [Coordinate]) -> [Coordinate] {
        if !hasRepeatedPoints(c) { return c }
        var out: [Coordinate] = []
        out.reserveCapacity(c.count)
        for p in c where out.last != p { out.append(p) }
        return out
    }

    /// The first coordinate of `test` that is not in `list`, if any.
    public static func ptNotInList(_ test: [Coordinate], _ list: [Coordinate]) -> Coordinate? {
        for p in test where indexOf(p, list) < 0 { return p }
        return nil
    }

    public static func indexOf(_ c: Coordinate, _ list: [Coordinate]) -> Int {
        list.firstIndex(of: c) ?? -1
    }

    /// The envelope of the coordinates.
    public static func envelope(_ c: [Coordinate]) -> Envelope {
        var e = Envelope()
        for p in c { e.expandToInclude(p) }
        return e
    }

    /// Whether the two arrays are equal, point for point.
    public static func equals(_ a: [Coordinate], _ b: [Coordinate]) -> Bool { a == b }
}
