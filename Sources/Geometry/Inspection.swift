import Topology

/// What the replay tests read of a geometry besides the public API
/// (`Tests/TopologyTests/Recording/WrapperReplayTests`): recorded WKB in and
/// out, and the grid of the precision model it carries, which decides how
/// later operations node it (as GEOS's did).
extension Geometry {
    static func read(wkb: [UInt8]) throws -> Geometry { Geometry(try WKBReader().read(wkb)) }

    /// Its WKB: two dimensions, little-endian, as the recording keeps it.
    var wkb: [UInt8] { WKBWriter().write(geometry) }

    /// The grid size of its precision model (0 when floating, as
    /// `GEOSGeom_getPrecision` gives it), and of each member's in turn,
    /// depth first.
    var grids: [Double] {
        func walk(_ g: Topology.Geometry, _ out: inout [Double]) {
            out.append(g.precisionModel.isFloating ? 0 : 1.0 / g.precisionModel.scale)
            guard g is GeometryCollection else { return }
            for i in 0..<g.getNumGeometries() { walk(g.getGeometryN(i), &out) }
        }
        var out: [Double] = []
        walk(geometry, &out)
        return out
    }
}
