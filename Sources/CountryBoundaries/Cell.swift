/// One cell of the boundaries raster: the regions covering it whole and those covering it in part.
///
/// Ported from `cell.rs` of the Rust crate country-boundaries 1.2.0 (Apache-2.0).

/// A region that covers only part of a cell, with its polygons in the cell's local coordinates.
struct IntersectingArea: Equatable, Sendable {
    var id: String
    var multipolygon: Multipolygon
}

/// One cell in the country boundaries grid.
struct Cell: Equatable, Sendable {
    /// The regions that completely cover this cell.
    var containingIds: [String] = []
    /// The regions that only partly cover this cell.
    var intersectingAreas: [IntersectingArea] = []

    /// Returns whether the point is in the region with the given id.
    func isIn(_ point: Point, _ id: String) -> Bool {
        containingIds.contains { $0 == id }
            || intersectingAreas.contains { $0.id == id && $0.multipolygon.covers(point) }
    }

    /// Returns whether the point is in any of the regions with the given ids.
    func isInAny(_ point: Point, _ ids: Set<String>) -> Bool {
        containingIds.contains { ids.contains($0) }
            || intersectingAreas.contains { ids.contains($0.id) && $0.multipolygon.covers(point) }
    }

    /// Returns the ids of the regions that cover the point: first the partly covering ones that
    /// contain it, in the order of the cell, then the ones covering the whole cell.
    func getIds(_ point: Point) -> [String] {
        intersectingAreas.filter { $0.multipolygon.covers(point) }.map(\.id) + containingIds
    }

    /// Returns the ids of the regions that cover this cell completely or in part, the complete
    /// ones first.
    func getAllIds() -> [String] {
        containingIds + intersectingAreas.map(\.id)
    }
}
