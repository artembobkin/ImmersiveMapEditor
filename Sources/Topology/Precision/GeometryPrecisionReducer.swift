/// Reduces the precision of a geometry to a precision model, keeping it
/// valid: JTS's `GeometryPrecisionReducer`, with `PrecisionReducerTransformer`
/// (polygonal parts snap-rounded by OverlayNG, lines and points rounded,
/// repeated points dropped, collapsed parts removed or kept) and
/// `PointwisePrecisionReducerTransformer` (every coordinate rounded alone).
///
/// As GEOS 3.13 reduces (`GEOSGeom_setPrecision`): a collection reduced to
/// a single geometry is made a multi-geometry again, and changing the
/// precision model copies the result without its empty members.
public final class GeometryPrecisionReducer {
    let targetPM: PrecisionModel
    @exclusivity(unchecked) var removeCollapsed = true
    @exclusivity(unchecked) var changePrecisionModel = false
    @exclusivity(unchecked) var isPointwise = false

    public init(_ pm: PrecisionModel) { targetPM = pm }

    public static func reduce(_ g: Geometry, _ precModel: PrecisionModel) throws -> Geometry {
        try GeometryPrecisionReducer(precModel).reduce(g)
    }

    public func setRemoveCollapsedComponents(_ removeCollapsed: Bool) { self.removeCollapsed = removeCollapsed }
    public func setChangePrecisionModel(_ changePrecisionModel: Bool) { self.changePrecisionModel = changePrecisionModel }
    public func setPointwise(_ isPointwise: Bool) { self.isPointwise = isPointwise }

    public func reduce(_ geom: Geometry) throws -> Geometry {
        var reduced: Geometry
        if isPointwise {
            reduced = try PointwisePrecisionReducerTransformer(targetPM).transform(geom)
        } else {
            reduced = try PrecisionReducerTransformer(targetPM, removeCollapsed).transform(geom)
        }
        if geom is GeometryCollection && !(reduced is GeometryCollection) {
            reduced = geom.factory.createMulti(reduced)
        }
        if changePrecisionModel {
            return GeometryEditor.copy(reduced, GeometryFactory(precisionModel: targetPM))
        }
        return reduced
    }
}

/// Rounds coordinates to a precision model, dropping repeats, and reduces
/// polygonal geometry by a snap-rounded union: JTS's `PrecisionReducerTransformer`.
final class PrecisionReducerTransformer: GeometryTransformer {
    let targetPM: PrecisionModel
    let isRemoveCollapsed: Bool

    init(_ targetPM: PrecisionModel, _ isRemoveCollapsed: Bool) {
        self.targetPM = targetPM
        self.isRemoveCollapsed = isRemoveCollapsed
    }

    override func transformCoordinates(_ coords: [Coordinate], _ parent: Geometry) throws -> [Coordinate]? {
        if coords.isEmpty { return nil }
        var list = CoordinateList()
        for c in coords { list.add(targetPM.makePrecise(c), false) }
        var coordsReduce = list.points
        var minLength = 0
        if type(of: parent) == LineString.self { minLength = 2 }
        if parent is LinearRing { minLength = LinearRing.minimumValidRingSize }
        if coordsReduce.count < minLength {
            if isRemoveCollapsed { return nil }
            // GEOS repeats the last point up to the size.
            while coordsReduce.count < minLength { coordsReduce.append(coordsReduce[coordsReduce.count - 1]) }
        }
        return coordsReduce
    }

    override func transformPolygon(_ geom: Polygon, _ parent: Geometry?) throws -> Geometry { try reduceArea(geom) }
    override func transformMultiPolygon(_ geom: MultiPolygon, _ parent: Geometry?) throws -> Geometry { try reduceArea(geom) }

    private func reduceArea(_ geom: Geometry) throws -> Geometry { try PrecisionReducer.reducePrecision(geom, targetPM) }
}

/// Rounds every coordinate alone: JTS's `PointwisePrecisionReducerTransformer`.
final class PointwisePrecisionReducerTransformer: GeometryTransformer {
    let targetPM: PrecisionModel

    init(_ targetPM: PrecisionModel) { self.targetPM = targetPM }

    override func transformCoordinates(_ coords: [Coordinate], _ parent: Geometry) throws -> [Coordinate]? {
        coords.map { targetPM.makePrecise($0) }
    }
}

/// Reduces the precision of a geometry by its union with snap rounding at
/// the model: JTS's `overlayng.PrecisionReducer`, as GEOS 3.13 runs it (a
/// topology failure is not turned into an illegal argument).
public enum PrecisionReducer {
    public static func reducePrecision(_ geom: Geometry, _ pm: PrecisionModel) throws -> Geometry {
        let ov = OverlayNG(geom, nil, pm, OverlayNG.union)
        if geom.getDimension() == 2 { ov.isAreaResultOnly = true }
        return try ov.getResult()
    }
}

extension GeometryFactory {
    /// A single geometry as a multi-geometry of it (GEOS's `createMulti`):
    /// an empty one as an empty multi-geometry of its kind.
    func createMulti(_ g: Geometry) -> Geometry {
        if g is GeometryCollection { return g }
        if g.isEmpty() {
            switch g {
            case is Point: return createMultiPoint()
            case is LineString: return createMultiLineString()
            default: return createMultiPolygon()
            }
        }
        switch g {
        case let p as Point: return createMultiPoint([p])
        case let l as LineString: return createMultiLineString([l])
        case let p as Polygon: return createMultiPolygon([p])
        default: return g
        }
    }
}

extension Geometry {
    /// The geometry on a grid of the size (`GEOSGeom_setPrecision` with
    /// flags 0): snap-rounded, valid, collapsed parts removed. As GEOS's C
    /// API does, a grid of 0, or the grid the geometry already has (its
    /// precision model's `1 / scale`), only copies it into a factory of the
    /// new precision model (floating for 0), without empty members.
    public func setPrecision(_ gridSize: Double) throws -> Geometry {
        let pm = gridSize != 0 ? PrecisionModel(scale: 1.0 / abs(gridSize)) : PrecisionModel()
        let current = precisionModel.isFloating ? 0 : 1.0 / precisionModel.scale
        guard gridSize != 0 && current != gridSize else { return GeometryEditor.copy(self, GeometryFactory(precisionModel: pm)) }
        let reducer = GeometryPrecisionReducer(pm)
        reducer.setChangePrecisionModel(true)
        reducer.setPointwise(false)
        reducer.setRemoveCollapsedComponents(true)
        return try NonFinite.scope { try reducer.reduce(self) }
    }
}
