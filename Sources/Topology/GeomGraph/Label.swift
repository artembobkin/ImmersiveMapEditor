/// The locations of a graph component relative to the two input
/// geometries: JTS's `geomgraph.TopologyLocation` and `geomgraph.Label`.
///
/// The `geomgraph` package is JTS's older planar graph. Only the buffer
/// still uses it (in GEOS 3.13 as in JTS 1.20), so the port has the part of
/// it the buffer needs, under the namespace `GeomGraph` (its names, `Edge`,
/// `Node`, clash with OverlayNG's).
public enum GeomGraph {}

extension GeomGraph {
    /// The location on a component and, for an area edge, on its left and
    /// right: one location for a line, three for an area.
    struct TopologyLocation {
        var location: [Int]

        init(_ on: Int, _ left: Int, _ right: Int) { location = [on, left, right] }
        init(_ on: Int) { location = [on] }

        func get(_ posIndex: Int) -> Int { posIndex < location.count ? location[posIndex] : Location.none }
        var isNull: Bool { location.allSatisfy { $0 == Location.none } }
        var isAnyNull: Bool { location.contains(Location.none) }
        var isArea: Bool { location.count > 1 }
        var isLine: Bool { location.count == 1 }

        mutating func flip() {
            if location.count <= 1 { return }
            location.swapAt(Position.left, Position.right)
        }

        mutating func setAllLocations(_ locValue: Int) {
            for i in location.indices { location[i] = locValue }
        }

        mutating func setAllLocationsIfNull(_ locValue: Int) {
            for i in location.indices where location[i] == Location.none { location[i] = locValue }
        }

        mutating func setLocation(_ locIndex: Int, _ locValue: Int) { location[locIndex] = locValue }

        func allPositionsEqual(_ loc: Int) -> Bool { location.allSatisfy { $0 == loc } }

        /// Fills the locations this one lacks from another, growing to an
        /// area's three when the other is one.
        mutating func merge(_ gl: TopologyLocation) {
            if gl.location.count > location.count {
                location = [location[Position.on], Location.none, Location.none]
            }
            for i in location.indices where location[i] == Location.none && i < gl.location.count {
                location[i] = gl.location[i]
            }
        }
    }

    /// The topological relationship of a component to the two geometries
    /// (index 0 and 1). A class, as in JTS: an edge's label is changed in
    /// place when an equal edge merges into it.
    final class Label {
        @exclusivity(unchecked) var elt: [TopologyLocation]

        init(_ onLoc: Int) { elt = [TopologyLocation(onLoc), TopologyLocation(onLoc)] }

        init(_ geomIndex: Int, _ onLoc: Int, _ leftLoc: Int, _ rightLoc: Int) {
            elt = [TopologyLocation(Location.none, Location.none, Location.none),
                   TopologyLocation(Location.none, Location.none, Location.none)]
            elt[geomIndex].location = [onLoc, leftLoc, rightLoc]
        }

        init(_ lbl: Label) { elt = lbl.elt }

        func flip() {
            elt[0].flip()
            elt[1].flip()
        }

        func getLocation(_ geomIndex: Int, _ posIndex: Int) -> Int { elt[geomIndex].get(posIndex) }
        func getLocation(_ geomIndex: Int) -> Int { elt[geomIndex].get(Position.on) }
        func setLocation(_ geomIndex: Int, _ posIndex: Int, _ location: Int) { elt[geomIndex].setLocation(posIndex, location) }
        func setLocation(_ geomIndex: Int, _ location: Int) { elt[geomIndex].setLocation(Position.on, location) }

        func merge(_ lbl: Label) {
            for i in 0..<2 { elt[i].merge(lbl.elt[i]) }
        }

        func getGeometryCount() -> Int { (elt[0].isNull ? 0 : 1) + (elt[1].isNull ? 0 : 1) }
        func isArea() -> Bool { elt[0].isArea || elt[1].isArea }
        func isArea(_ geomIndex: Int) -> Bool { elt[geomIndex].isArea }
        func isLine(_ geomIndex: Int) -> Bool { elt[geomIndex].isLine }
        func allPositionsEqual(_ geomIndex: Int, _ loc: Int) -> Bool { elt[geomIndex].allPositionsEqual(loc) }
    }
}
