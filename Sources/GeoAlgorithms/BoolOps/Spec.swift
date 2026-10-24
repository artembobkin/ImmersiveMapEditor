/// geo's boolean operation specs (`bool_ops/spec.rs`): which side of an edge belongs to which
/// input (`Region`), and which edges the output keeps, for the polygon operations (`BoolOp`) and
/// for clipping line strings (`ClipOp`).

/// The four boolean operations, in geo's order.
public enum GeoOpType: Int, Sendable, Comparable {
    case intersection
    case union
    case difference
    case xor

    public static func < (lhs: GeoOpType, rhs: GeoOpType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Whether a region of the plane is inside the first and the second input.
struct SpecRegion: CustomStringConvertible {
    var isFirst: Bool
    var isSecond: Bool

    var description: String { "[\(isFirst ? "A" : "")\(isSecond ? "B" : "")]" }

    /// `Region::cross`: crossing an edge of an input toggles that input.
    mutating func cross(_ first: Bool) {
        if first {
            isFirst.toggle()
        } else {
            isSecond.toggle()
        }
    }

    /// `Region::is_ty`: whether the region belongs to the result of `ty`.
    func isTy(_ ty: GeoOpType) -> Bool {
        switch ty {
        case .intersection, .difference: return isFirst && isSecond
        case .union: return isFirst || isSecond
        case .xor: return isFirst != isSecond
        }
    }
}

/// geo's `Spec`.
protocol SweepSpec {
    associatedtype Output
    func infinity() -> SpecRegion
    func cross(_ prevRegion: SpecRegion, _ idx: Int) -> SpecRegion
    mutating func output(_ regions: (SpecRegion, SpecRegion), _ geom: LineOrPoint, _ idx: Int)
    func finish() throws(GeoPanic) -> Output
}

/// The spec of the polygon operations.
struct BoolOpSpec: SweepSpec {
    let ty: GeoOpType
    var assembly = RegionAssembly()

    init(_ ty: GeoOpType) {
        self.ty = ty
    }

    func infinity() -> SpecRegion {
        // For a difference the second input is inverted, so its outside counts as inside.
        SpecRegion(isFirst: false, isSecond: ty == .difference)
    }

    func cross(_ prevRegion: SpecRegion, _ idx: Int) -> SpecRegion {
        var region = prevRegion
        region.cross(idx == 0)
        return region
    }

    mutating func output(_ regions: (SpecRegion, SpecRegion), _ geom: LineOrPoint, _ idx: Int) {
        if regions.0.isTy(ty) != regions.1.isTy(ty) {
            assembly.addEdge(geom)
        }
    }

    func finish() throws(GeoPanic) -> GeoMultiPolygon {
        try assembly.finish()
    }
}

/// The spec of clipping line strings by polygons.
struct ClipOpSpec: SweepSpec {
    let invert: Bool
    var assembly = LineAssembly()

    init(invert: Bool) {
        self.invert = invert
    }

    func infinity() -> SpecRegion {
        SpecRegion(isFirst: false, isSecond: false)
    }

    func cross(_ prevRegion: SpecRegion, _ idx: Int) -> SpecRegion {
        var region = prevRegion
        if idx == 0 {
            region.cross(true)
        }
        return region
    }

    mutating func output(_ regions: (SpecRegion, SpecRegion), _ geom: LineOrPoint, _ idx: Int) {
        if idx > 0 && (regions.0.isFirst && regions.1.isFirst) != invert {
            assembly.addEdge(geom, idx)
        }
    }

    func finish() throws(GeoPanic) -> GeoMultiLineString {
        GeoMultiLineString(assembly.finish())
    }
}
