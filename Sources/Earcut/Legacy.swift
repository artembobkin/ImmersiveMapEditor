/// The helpers of earcutr's `legacy` module that the crate re-exports: `flatten`, which turns
/// nested rings into the flat form `earcut` takes, and `deviation`, which checks a result.

extension Earcut {
    /// Turns a polygon given as nested arrays (rings of points of coordinates, as in GeoJSON) into
    /// the flat form `earcut` takes (`earcutr::flatten`).
    ///
    /// Like the Rust, it traps on an empty polygon or an empty first ring.
    ///
    /// - Returns: The flat coordinates, the vertex index where each hole starts, and the number of
    ///   coordinates of the first point.
    public static func flatten(
        _ data: [[[Double]]]
    ) -> (vertices: [Double], holeIndices: [Int], dimensions: Int) {
        var vertices: [Double] = []
        for ring in data {
            for point in ring {
                vertices.append(contentsOf: point)
            }
        }
        var holeIndices: [Int] = []
        var holeIndex = 0
        for ring in data.prefix(data.count - 1) {
            holeIndex += ring.count
            holeIndices.append(holeIndex)
        }
        return (vertices, holeIndices, data[0][0].count)
    }

    /// The relative difference between the polygon's area and the total area of its triangles,
    /// used to verify a triangulation (`earcutr::deviation`).
    ///
    /// Returns NaN for any number of dimensions but 2, and zero when both areas are zero.
    public static func deviation(
        _ vertices: [Double],
        holeIndices: [Int],
        dimensions: Int,
        triangles: [Int]
    ) -> Double {
        if dim != dimensions {
            return Double.nan
        }
        let vertices = Vertices(vertices)
        var indices = holeIndices
        indices.append(vertices.count / dim)
        let bodyArea = abs(vertices.signedArea(0, indices[0] * dim))
        var polygonArea = bodyArea
        var k = 0
        while k + 1 < indices.count {
            polygonArea = polygonArea - abs(vertices.signedArea(indices[k] * dim, indices[k + 1] * dim))
            k += 1
        }

        var trianglesArea = 0.0
        var t = 0
        while t + 2 < triangles.count {
            let a = triangles[t] * dim
            let b = triangles[t + 1] * dim
            let c = triangles[t + 2] * dim
            trianglesArea = trianglesArea
                + abs(
                    (vertices[a] - vertices[c]) * (vertices[b + 1] - vertices[a + 1])
                        - (vertices[a] - vertices[b]) * (vertices[c + 1] - vertices[a + 1])
                )
            t += 3
        }

        if polygonArea == 0 && trianglesArea == 0 {
            return 0
        }
        return abs((trianglesArea - polygonArea) / polygonArea)
    }
}
