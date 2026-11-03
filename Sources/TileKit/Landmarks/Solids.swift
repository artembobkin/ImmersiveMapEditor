import Foundation
import Manifold

/// Closed solids united into one mesh by Manifold (SwiftManifold, the Swift
/// port of github.com/elalish/manifold): what makes a landmark's model one
/// shell out of its masses, bands, columns and shapes, with nothing inside
/// and no two faces on one plane.
public enum SolidUnion {
    public struct Mesh {
        public var verts: [Float]
        public var tris: [UInt32]
        public var faceIDs: [UInt32]
    }

    /// The union of the meshes, each a closed, outward-wound triangle mesh
    /// with a face id a triangle. `statuses` tells, an input each, whether
    /// Manifold took it (0) or why not (2: not manifold). nil when the
    /// union itself failed.
    public static func unite(_ meshes: [Mesh], statuses: inout [Int32]) -> Mesh? {
        statuses = [Int32](repeating: 0, count: meshes.count)
        guard !meshes.isEmpty else { return nil }
        var parts: [Manifold] = []
        parts.reserveCapacity(meshes.count)
        for (k, mesh) in meshes.enumerated() {
            var g = MeshGL()
            g.numProp = 3
            g.vertProperties = mesh.verts
            g.triVerts = mesh.tris
            g.faceID = mesh.faceIDs
            let solid = Manifold(g)
            statuses[k] = Int32(solid.Status().rawValue)
            if solid.Status() == .NoError { parts.append(solid) }
        }
        var result: Int32 = Int32(Manifold.Error.InvalidConstruction.rawValue)
        var united: Mesh?
        if !parts.isEmpty {
            // United, then simplified: the triangles of one planar face (one
            // face id) merged again, their edges to other faces kept.
            let union = Manifold.BatchBoolean(parts, .Add).Simplify(0.002)
            result = Int32(union.Status().rawValue)
            if result == 0 {
                let g = union.GetMeshGL()
                var verts = [Float]()
                verts.reserveCapacity(3 * g.NumVert())
                let stride = Int(g.numProp)
                for v in 0..<g.NumVert() {
                    for k in 0..<3 { verts.append(g.vertProperties[v * stride + k]) }
                }
                let ids = (0..<g.NumTri()).map { $0 < g.faceID.count ? g.faceID[$0] : UInt32.max }
                if g.NumTri() > 0 { united = Mesh(verts: verts, tris: g.triVerts, faceIDs: ids) }
            }
        }
        if let folder = ProcessInfo.processInfo.environment["SOLID_UNION_RECORD"] {
            record(meshes, statuses, result, united, in: folder)
        }
        return united
    }

    /// Writes one call, its inputs, statuses and result, to a file of its own
    /// in the folder (`SOLID_UNION_RECORD`), for the parity tests of
    /// SwiftManifold (its `MANIFOLD_UNION_RECORDINGS`): little-endian counts
    /// as UInt32, then the arrays.
    static func record(_ meshes: [Mesh], _ statuses: [Int32], _ result: Int32, _ united: Mesh?, in folder: String) {
        var data = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func mesh(_ m: Mesh) {
            u32(m.verts.count / 3)
            m.verts.withUnsafeBytes { data.append(contentsOf: $0) }
            u32(m.tris.count / 3)
            m.tris.withUnsafeBytes { data.append(contentsOf: $0) }
            m.faceIDs.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        u32(meshes.count)
        for m in meshes { mesh(m) }
        statuses.withUnsafeBytes { data.append(contentsOf: $0) }
        withUnsafeBytes(of: result.littleEndian) { data.append(contentsOf: $0) }
        u32(united == nil ? 0 : 1)
        if let united { mesh(united) }
        let name = "union-\(ProcessInfo.processInfo.processIdentifier)-\(UInt64(Date().timeIntervalSince1970 * 1e6)).bin"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
}
