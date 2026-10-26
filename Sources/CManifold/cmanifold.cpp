#include "cmanifold.h"

#include <cstdlib>
#include <cstring>
#include <vector>

#include "manifold/manifold.h"

using namespace manifold;

extern "C" int cm_union(const cm_mesh_in *inputs, uint32_t count, int *statuses, cm_mesh_out *out) {
    std::vector<Manifold> parts;
    parts.reserve(count);
    for (uint32_t i = 0; i < count; i++) {
        const cm_mesh_in &in = inputs[i];
        MeshGL m;
        m.numProp = 3;
        m.vertProperties.assign(in.verts, in.verts + 3 * (size_t)in.nverts);
        m.triVerts.assign(in.tris, in.tris + 3 * (size_t)in.ntris);
        if (in.faceIDs) m.faceID.assign(in.faceIDs, in.faceIDs + in.ntris);
        Manifold man(m);
        statuses[i] = (int)man.Status();
        if (man.Status() == Manifold::Error::NoError) parts.push_back(man);
    }
    out->verts = nullptr; out->nverts = 0; out->tris = nullptr; out->ntris = 0; out->faceIDs = nullptr;
    if (parts.empty()) return (int)Manifold::Error::InvalidConstruction;
    // United, then simplified: the triangles of one planar face (one face
    // id) merged again, their edges to other faces kept.
    Manifold result = Manifold::BatchBoolean(parts, OpType::Add).Simplify(0.002);
    int status = (int)result.Status();
    if (status != 0) return status;
    MeshGL g = result.GetMeshGL();
    size_t nv = g.NumVert(), nt = g.NumTri();
    out->nverts = (uint32_t)nv;
    out->ntris = (uint32_t)nt;
    out->verts = (float *)malloc(sizeof(float) * 3 * nv);
    for (size_t v = 0; v < nv; v++)
        for (int k = 0; k < 3; k++) out->verts[3 * v + k] = g.vertProperties[v * g.numProp + k];
    out->tris = (uint32_t *)malloc(sizeof(uint32_t) * 3 * nt);
    memcpy(out->tris, g.triVerts.data(), sizeof(uint32_t) * 3 * nt);
    out->faceIDs = (uint32_t *)malloc(sizeof(uint32_t) * nt);
    for (size_t t = 0; t < nt; t++) out->faceIDs[t] = t < g.faceID.size() ? g.faceID[t] : 0xFFFFFFFFu;
    return 0;
}

extern "C" void cm_free(cm_mesh_out *out) {
    free(out->verts); free(out->tris); free(out->faceIDs);
    out->verts = nullptr; out->tris = nullptr; out->faceIDs = nullptr;
    out->nverts = 0; out->ntris = 0;
}
