import Topology

/// A geometry prepared for many tests against it (GEOS's prepared geometry:
/// the port's `PreparedGeometry`, of the kind GEOS chooses).
public final class Prepared {
    let geometry: Geometry
    let prepared: PreparedGeometry
    /// Its id in the recording (`Recorder`).
    var recordID: UInt32 = 0

    public init(_ g: Geometry) {
        geometry = g
        prepared = PreparedGeometryFactory.prepare(g.geometry)
        if let r = Recorder.shared {
            recordID = r.object()
            r.call("Prepared.init", [g], [Double(recordID)])
        }
    }

    public func contains(_ o: Geometry) -> Bool {
        Recorder.shared?.call("Prepared.contains", [o], [Double(recordID)])
        return Failure.attempt(false) { try prepared.contains(o.geometry) }
    }

    public func contains(_ p: P2) -> Bool { contains(.point(p)) }

    public func intersects(_ o: Geometry) -> Bool {
        Recorder.shared?.call("Prepared.intersects", [o], [Double(recordID)])
        return Failure.attempt(false) { try prepared.intersects(o.geometry) }
    }
}
