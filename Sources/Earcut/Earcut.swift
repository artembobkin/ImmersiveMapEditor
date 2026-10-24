/// The public face of the Swift port of earcutr 0.4.3, the Rust port of Mapbox's earcut polygon
/// triangulation: the `earcut` entry point and its error type.

/// The error earcutr reports (`earcutr::Error`).
public enum EarcutError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Invalid input, or a coordinate that cannot be hashed.
    case unknown

    public var description: String {
        switch self {
        case .unknown:
            return "Unknown error"
        }
    }
}

/// Polygon triangulation by ear slicing, ported from earcutr 0.4.3.
public enum Earcut {
    /// Triangulates a polygon with holes (`earcutr::earcut`).
    ///
    /// - Parameters:
    ///   - vertices: The flat coordinates of the outer ring followed by those of each hole.
    ///   - holeIndices: The vertex index (not the coordinate offset) where each hole starts.
    ///   - dimensions: The number of coordinates per vertex. Only 2 is triangulated: any other
    ///     value that passes the input checks returns no triangles, as in earcutr.
    /// - Returns: The vertex indices of the triangles, three per triangle.
    /// - Throws: `EarcutError.unknown` for an odd number of coordinates, more dimensions than
    ///   coordinates, a hole index out of range (or negative, which Rust cannot express), and a
    ///   coordinate whose z-order cannot be computed.
    public static func earcut(
        _ vertices: [Double],
        holeIndices: [Int],
        dimensions: Int
    ) throws -> [Int] {
        if vertices.isEmpty && holeIndices.isEmpty {
            return []
        }

        if vertices.count % 2 == 1 || dimensions > vertices.count {
            throw EarcutError.unknown
        }

        let outerLen: Int
        if let firstHoleIndex = holeIndices.first {
            let (product, overflow) = firstHoleIndex.multipliedReportingOverflow(by: dim)
            if firstHoleIndex < 0 || overflow {
                throw EarcutError.unknown
            }
            if product > vertices.count || product == 0 {
                throw EarcutError.unknown
            }
            if product % 2 == 1 {
                throw EarcutError.unknown
            }
            outerLen = product
        } else {
            outerLen = vertices.count
        }

        let vertices = Vertices(vertices)
        let (ll, firstOuterNode) = try linkedList(vertices, 0, outerLen, true)
        var triangles: [Int] = []
        triangles.reserveCapacity(vertices.count / dim)
        if ll.nodes.count == 1 || dim != dimensions {
            return triangles
        }

        let outerNode = try eliminateHoles(ll, vertices, holeIndices, firstOuterNode)

        if ll.usehash {
            ll.invsize = calcInvsize(ll.min, ll.max)

            // Translate all the points so that the minimum is at 0, 0. This keeps subtraction out
            // of the z-order. The inverse size does not depend on the translation on an evenly
            // spaced grid of points. Floating point space is not evenly spaced, but it is close
            // enough for this hash.
            let mx = ll.min.x
            let my = ll.min.y
            for i in ll.nodes.indices {
                ll.nodes[i].coord.x = ll.nodes[i].coord.x - mx
                ll.nodes[i].coord.y = ll.nodes[i].coord.y - my
            }
            try earcutLinked(ll, outerNode, &triangles, pass: 0, hashed: true)
        } else {
            try earcutLinked(ll, outerNode, &triangles, pass: 0, hashed: false)
        }

        return triangles
    }
}
