import Foundation
import Geometry
import GLTF

/// A landmark's model in the colours a tile build gives it, alone: each
/// face in its material's palette colour, plain. What the editor's Preview
/// shows for a landmark without building the tile, under its own light.
public enum LandmarkTones {
    public struct Result {
        /// Corners (X east, Y north, Z up), three a triangle.
        public var positions: [Double]
        /// The sRGB bytes of each triangle's colour, three a triangle.
        public var colours: [UInt8]
        public var triangles: Int { colours.count / 3 }
    }

    /// Reads the model with each face's colour.
    public static func read(_ glb: URL) throws -> Result {
        var positions: [Double] = []
        var colours: [UInt8] = []
        for part in try GLTF.primitives(glb) {
            let colour = colour(part.material.name, part.material.factor)
            for t in stride(from: 0, to: part.tris.count - 2, by: 3) {
                let p = [part.tris[t], part.tris[t + 1], part.tris[t + 2]].map { V3($0.x, $0.y, $0.z) }
                guard (p[1] - p[0]).cross(p[2] - p[0]).length > 1e-12 else { continue }
                for q in p { positions += [q.x, q.y, q.z] }
                colours += colour
            }
        }
        guard !colours.isEmpty else { throw Failure("no triangles in \(glb.lastPathComponent)") }
        return Result(positions: positions, colours: colours)
    }

    /// A face's colour: its material's palette colour when the palette has
    /// it, the material's own factor otherwise (a model not made from a
    /// recipe).
    static func colour(_ name: String, _ factor: [Double]) -> [UInt8] {
        if let hex = name.isEmpty ? nil : Palette.hexAny(name) ?? Palette.hex(name) {
            let (r, g, b) = Palette.rgb(hex)
            return [UInt8(r), UInt8(g), UInt8(b)]
        }
        return (0..<3).map { UInt8(min(max(factor.count > $0 ? factor[$0] : 1, 0), 1) * 255 + 0.5) }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ s: String) { description = s }
    }
}
