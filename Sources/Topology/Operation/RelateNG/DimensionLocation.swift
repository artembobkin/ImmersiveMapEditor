/// A location in a geometry together with the dimension of the element it
/// is in (a point's interior, a line's interior or boundary, an area's
/// interior or boundary), as one code: JTS's `DimensionLocation`.
enum DimensionLocation {
    static let exterior = Location.exterior
    static let pointInterior = 103
    static let lineInterior = 110
    static let lineBoundary = 111
    static let areaInterior = 120
    static let areaBoundary = 121

    static func locationArea(_ loc: Int) -> Int {
        switch loc {
        case Location.interior: return areaInterior
        case Location.boundary: return areaBoundary
        default: return exterior
        }
    }

    static func locationLine(_ loc: Int) -> Int {
        switch loc {
        case Location.interior: return lineInterior
        case Location.boundary: return lineBoundary
        default: return exterior
        }
    }

    static func locationPoint(_ loc: Int) -> Int { loc == Location.interior ? pointInterior : exterior }

    static func location(_ dimLoc: Int) -> Int {
        switch dimLoc {
        case pointInterior, lineInterior, areaInterior: return Location.interior
        case lineBoundary, areaBoundary: return Location.boundary
        default: return Location.exterior
        }
    }

    static func dimension(_ dimLoc: Int) -> Int {
        switch dimLoc {
        case pointInterior: return Dimension.p
        case lineInterior, lineBoundary: return Dimension.l
        case areaInterior, areaBoundary: return Dimension.a
        default: return Dimension.false
        }
    }

    /// The dimension, `exteriorDim` for the exterior.
    static func dimension(_ dimLoc: Int, _ exteriorDim: Int) -> Int {
        if dimLoc == exterior { return exteriorDim }
        return dimension(dimLoc)
    }
}
