import Foundation
import simd

/// A model's primitives as indexed meshes, for what puts a model on the GPU
/// as it is: the model archive bakes a built tile's GLB from them. The
/// positions and normals are in the file's root space, with each node's
/// transform applied and the axes as glTF has them (+Y up), and the texture
/// coordinates and the image as the file holds them (V down).
///
/// Read strictly: a triangle list with float positions, normals and one set
/// of texture coordinates, and a base colour texture embedded in the file.
/// Anything else is an error, not a guess, so a model that would bake wrong
/// does not bake at all. It stands on the same reading of the file, its
/// nodes and its accessors as `read` and `primitives`.
extension GLTF {
    /// One primitive with its node's transform applied.
    public struct IndexedPrimitive {
        public var positions: [SIMD3<Float>]
        public var normals: [SIMD3<Float>]
        public var textureCoordinates: [SIMD2<Float>]
        public var indices: [UInt32]
        /// The encoded image of the base colour, as the file embeds it.
        public var image: Data
    }

    /// Every primitive of the default scene, indexed.
    public static func indexedPrimitives(_ url: URL) throws -> [IndexedPrimitive] {
        let doc = try load(url)
        let name = url.lastPathComponent
        let scenes = doc.array("scenes")
        let sceneIndex = doc.json["scene"] as? Int ?? 0
        guard sceneIndex < scenes.count else {
            throw Failure.format("\(name): no scene")
        }
        let nodes = doc.array("nodes")
        let meshes = doc.array("meshes")
        var result: [IndexedPrimitive] = []
        func walk(_ index: Int, _ parent: simd_double4x4) throws {
            guard index < nodes.count else {
                throw Failure.format("\(name): node \(index) does not exist")
            }
            let node = nodes[index]
            let transform = parent * local(node)
            if let meshIndex = node["mesh"] as? Int {
                guard meshIndex < meshes.count else {
                    throw Failure.format("\(name): mesh \(meshIndex) does not exist")
                }
                for primitive in meshes[meshIndex]["primitives"] as? [[String: Any]] ?? [] {
                    result.append(try indexed(doc, name, primitive, transform))
                }
            }
            for child in node["children"] as? [Int] ?? [] {
                try walk(child, transform)
            }
        }
        for root in scenes[sceneIndex]["nodes"] as? [Int] ?? [] {
            try walk(root, matrix_identity_double4x4)
        }
        guard result.isEmpty == false else {
            throw Failure.format("\(name): no mesh in the scene")
        }
        return result
    }

    private static func indexed(_ doc: Document, _ name: String, _ primitive: [String: Any],
                                _ transform: simd_double4x4) throws -> IndexedPrimitive {
        guard (primitive["mode"] as? Int ?? 4) == 4 else {
            throw Failure.format("\(name): a primitive is not a triangle list")
        }
        let attributes = primitive["attributes"] as? [String: Int] ?? [:]
        guard let positionAccessor = attributes["POSITION"],
              let normalAccessor = attributes["NORMAL"],
              let coordinateAccessor = attributes["TEXCOORD_0"] else {
            throw Failure.format("\(name): a primitive lacks POSITION, NORMAL or TEXCOORD_0")
        }
        let floats = [5126]
        let positionValues = try checked(doc, name, positionAccessor, components: floats, type: "VEC3")
        let normalValues = try checked(doc, name, normalAccessor, components: floats, type: "VEC3")
        let coordinateValues = try checked(doc, name, coordinateAccessor, components: floats, type: "VEC2")
        let vertexCount = positionValues.count / 3
        guard normalValues.count == vertexCount * 3, coordinateValues.count == vertexCount * 2 else {
            throw Failure.format("\(name): the attributes of a primitive differ in length")
        }

        let linear = simd_double3x3(columns: (SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                              SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                              SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
        let determinant = linear.determinant
        guard abs(determinant) > 1e-12 else {
            throw Failure.format("\(name): a node transform is singular")
        }
        let normalMatrix = linear.inverse.transpose

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        coordinates.reserveCapacity(vertexCount)
        for vertex in 0..<vertexCount {
            let position = transform * SIMD4(positionValues[vertex * 3], positionValues[vertex * 3 + 1],
                                             positionValues[vertex * 3 + 2], 1)
            positions.append(SIMD3(Float(position.x), Float(position.y), Float(position.z)))
            let turned = normalMatrix * SIMD3(normalValues[vertex * 3], normalValues[vertex * 3 + 1],
                                              normalValues[vertex * 3 + 2])
            // Its length in single precision, the precision it is kept in.
            let normal = SIMD3(Float(turned.x), Float(turned.y), Float(turned.z))
            let length = simd_length(normal)
            normals.append(length > 0 ? normal / length : SIMD3(0, 1, 0))
            coordinates.append(SIMD2(Float(coordinateValues[vertex * 2]), Float(coordinateValues[vertex * 2 + 1])))
        }

        var indices: [UInt32]
        if let indexAccessor = primitive["indices"] as? Int {
            indices = try checked(doc, name, indexAccessor, components: [5121, 5123, 5125], type: "SCALAR").map { UInt32($0) }
        } else {
            indices = (0..<UInt32(vertexCount)).map { $0 }
        }
        guard indices.count % 3 == 0, indices.allSatisfy({ Int($0) < vertexCount }) else {
            throw Failure.format("\(name): the indices of a primitive are not valid triangles")
        }
        // A mirroring transform turns every triangle inside out.
        if determinant < 0 {
            for triangle in stride(from: 0, to: indices.count, by: 3) {
                indices.swapAt(triangle + 1, triangle + 2)
            }
        }
        return IndexedPrimitive(positions: positions, normals: normals, textureCoordinates: coordinates,
                                indices: indices, image: try baseColourImage(doc, name, primitive))
    }

    /// The embedded image of a primitive's base colour, which must be on
    /// TEXCOORD_0 under a white factor: nothing else is baked.
    private static func baseColourImage(_ doc: Document, _ name: String, _ primitive: [String: Any]) throws -> Data {
        let materials = doc.array("materials")
        guard let materialIndex = primitive["material"] as? Int, materialIndex < materials.count,
              let pbr = materials[materialIndex]["pbrMetallicRoughness"] as? [String: Any],
              let reference = pbr["baseColorTexture"] as? [String: Any],
              let textureIndex = reference["index"] as? Int else {
            throw Failure.format("\(name): a primitive has no base color texture")
        }
        guard (reference["texCoord"] as? Int ?? 0) == 0 else {
            throw Failure.format("\(name): the base color texture does not use TEXCOORD_0")
        }
        let factor = pbr["baseColorFactor"] as? [Double] ?? []
        guard factor.isEmpty || factor == [1, 1, 1, 1] else {
            throw Failure.format("\(name): a base color factor other than white is not baked")
        }
        let textures = doc.array("textures")
        let images = doc.array("images")
        let views = doc.array("bufferViews")
        guard textureIndex < textures.count,
              let imageIndex = textures[textureIndex]["source"] as? Int, imageIndex < images.count,
              let viewIndex = images[imageIndex]["bufferView"] as? Int, viewIndex < views.count else {
            throw Failure.format("\(name): the base color image is not embedded in the file")
        }
        let view = views[viewIndex]
        let buffer = view["buffer"] as? Int ?? 0
        let start = view["byteOffset"] as? Int ?? 0, length = view["byteLength"] as? Int ?? 0
        guard buffer < doc.buffers.count, start >= 0, length >= 0, start + length <= doc.buffers[buffer].count,
              let image = imageData(doc, imageIndex) else {
            throw Failure.format("\(name): buffer view \(viewIndex) lies outside its buffer")
        }
        return image
    }

    /// An accessor's values (`accessor`), after its layout is checked to be
    /// one of `components` of `type` and to lie inside its buffer: the
    /// reading itself checks nothing.
    private static func checked(_ doc: Document, _ name: String, _ index: Int,
                                components: [Int], type: String) throws -> [Double] {
        let accessors = doc.array("accessors")
        guard index >= 0, index < accessors.count else {
            throw Failure.format("\(name): accessor \(index) does not exist")
        }
        let a = accessors[index]
        let kind = a["componentType"] as? Int ?? 0
        let views = doc.array("bufferViews")
        guard components.contains(kind), a["type"] as? String == type, a["sparse"] == nil,
              let viewIndex = a["bufferView"] as? Int, viewIndex >= 0, viewIndex < views.count else {
            throw Failure.format("\(name): accessor \(index) has a layout the baker does not read")
        }
        let view = views[viewIndex]
        let buffer = view["buffer"] as? Int ?? 0
        let viewStart = view["byteOffset"] as? Int ?? 0, viewLength = view["byteLength"] as? Int ?? 0
        guard buffer >= 0, buffer < doc.buffers.count, viewStart >= 0, viewLength >= 0,
              viewStart + viewLength <= doc.buffers[buffer].count else {
            throw Failure.format("\(name): buffer view \(viewIndex) lies outside its buffer")
        }
        let size = [5121: 1, 5123: 2, 5125: 4, 5126: 4][kind] ?? 4
        let element = size * (widths[type] ?? 1)
        let step = (view["byteStride"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? element
        let count = a["count"] as? Int ?? 0
        let start = a["byteOffset"] as? Int ?? 0
        guard count >= 0, start >= 0, count == 0 || start + (count - 1) * step + element <= viewLength else {
            throw Failure.format("\(name): accessor \(index) reads past its buffer view")
        }
        return accessor(doc, index).values
    }
}

extension GLTF.Failure: CustomStringConvertible {
    /// The failure in its own words, as a log prints an error.
    public var description: String {
        errorDescription ?? "not glTF"
    }
}
