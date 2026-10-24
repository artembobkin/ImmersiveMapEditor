/// geo's `BooleanOps` for polygons and multi-polygons: intersection, union, xor and difference
/// of two areas, and clipping of line strings by an area. The operations throw a `GeoPanic`
/// wherever geo 0.27 would panic, so a caller can recover as geom does with `catch_unwind`.

extension GeoPolygon {
    public func booleanOp(_ other: GeoPolygon, _ op: GeoOpType) throws(GeoPanic) -> GeoMultiPolygon {
        var bop = BoolOpProc(spec: BoolOpSpec(op), capacity: coordsCount + other.coordsCount)
        try bop.addPolygon(self, 0)
        try bop.addPolygon(other, 1)
        return try bop.sweep()
    }

    public func intersection(_ other: GeoPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .intersection)
    }

    public func union(_ other: GeoPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .union)
    }

    public func xor(_ other: GeoPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .xor)
    }

    public func difference(_ other: GeoPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .difference)
    }

    /// The part of `ls` inside `self` if `invert` is false, else the part outside.
    public func clip(_ ls: GeoMultiLineString, invert: Bool) throws(GeoPanic) -> GeoMultiLineString {
        var bop = BoolOpProc(spec: ClipOpSpec(invert: invert), capacity: coordsCount + ls.coordsCount)
        try bop.addPolygon(self, 0)
        for (idx, l) in ls.lineStrings.enumerated() {
            try bop.addLineString(l, idx + 1)
        }
        return try bop.sweep()
    }
}

extension GeoMultiPolygon {
    public func booleanOp(_ other: GeoMultiPolygon, _ op: GeoOpType) throws(GeoPanic) -> GeoMultiPolygon {
        var bop = BoolOpProc(spec: BoolOpSpec(op), capacity: coordsCount + other.coordsCount)
        try bop.addMultiPolygon(self, 0)
        try bop.addMultiPolygon(other, 1)
        return try bop.sweep()
    }

    public func intersection(_ other: GeoMultiPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .intersection)
    }

    public func union(_ other: GeoMultiPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .union)
    }

    public func xor(_ other: GeoMultiPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .xor)
    }

    public func difference(_ other: GeoMultiPolygon) throws(GeoPanic) -> GeoMultiPolygon {
        try booleanOp(other, .difference)
    }

    /// The part of `ls` inside `self` if `invert` is false, else the part outside.
    public func clip(_ ls: GeoMultiLineString, invert: Bool) throws(GeoPanic) -> GeoMultiLineString {
        var bop = BoolOpProc(spec: ClipOpSpec(invert: invert), capacity: coordsCount + ls.coordsCount)
        try bop.addMultiPolygon(self, 0)
        for (idx, l) in ls.lineStrings.enumerated() {
            try bop.addLineString(l, idx + 1)
        }
        return try bop.sweep()
    }
}
