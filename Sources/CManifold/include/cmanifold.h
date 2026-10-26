// A C face of Manifold (github.com/elalish/manifold, Apache 2.0) for Swift:
// the union of closed triangle meshes into one, each output triangle
// carrying the face id of the input triangle it came from.
#ifndef CMANIFOLD_H
#define CMANIFOLD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A mesh: vertices as x, y, z floats, triangles as three vertex indices
/// each, counter-clockwise seen from outside, and a face id a triangle.
typedef struct {
    const float *verts;
    uint32_t nverts;
    const uint32_t *tris;
    uint32_t ntris;
    const uint32_t *faceIDs;
} cm_mesh_in;

/// The union: its vertices, triangles and the face ids they came from,
/// owned by the caller once filled (cm_free).
typedef struct {
    float *verts;
    uint32_t nverts;
    uint32_t *tris;
    uint32_t ntris;
    uint32_t *faceIDs;
} cm_mesh_out;

/// Unites the meshes. `statuses` (one an input) says whether each was
/// taken (0) or why not (Manifold's Error: 2 is NotManifold); a mesh not
/// taken is left out of the union. Returns the result's status, 0 when
/// good.
int cm_union(const cm_mesh_in *inputs, uint32_t count, int *statuses, cm_mesh_out *out);

void cm_free(cm_mesh_out *out);

#ifdef __cplusplus
}
#endif

#endif
