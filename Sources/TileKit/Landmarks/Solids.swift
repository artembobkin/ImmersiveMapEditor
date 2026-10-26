import CManifold
import Foundation

/// Closed solids united into one mesh by Manifold (CManifold): what makes
/// a landmark's model one shell out of its masses, bands, columns and
/// shapes, with nothing inside and no two faces on one plane.
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
        var out = cm_mesh_out()
        var result: Int32 = -1
        // Every input array pinned for the call.
        func pinned(_ k: Int, _ inputs: inout [cm_mesh_in], _ done: (inout [cm_mesh_in]) -> Void) {
            if k == meshes.count { done(&inputs); return }
            meshes[k].verts.withUnsafeBufferPointer { v in
                meshes[k].tris.withUnsafeBufferPointer { t in
                    meshes[k].faceIDs.withUnsafeBufferPointer { f in
                        inputs.append(cm_mesh_in(verts: v.baseAddress, nverts: UInt32(meshes[k].verts.count / 3),
                                                 tris: t.baseAddress, ntris: UInt32(meshes[k].tris.count / 3), faceIDs: f.baseAddress))
                        pinned(k + 1, &inputs, done)
                    }
                }
            }
        }
        var inputs: [cm_mesh_in] = []
        pinned(0, &inputs) { inputs in
            statuses.withUnsafeMutableBufferPointer { s in
                result = cm_union(inputs, UInt32(inputs.count), s.baseAddress, &out)
            }
        }
        guard result == 0, out.ntris > 0 else { return nil }
        defer { cm_free(&out) }
        return Mesh(verts: Array(UnsafeBufferPointer(start: out.verts, count: Int(out.nverts) * 3)),
                    tris: Array(UnsafeBufferPointer(start: out.tris, count: Int(out.ntris) * 3)),
                    faceIDs: Array(UnsafeBufferPointer(start: out.faceIDs, count: Int(out.ntris))))
    }
}
