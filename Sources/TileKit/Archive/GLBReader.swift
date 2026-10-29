// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import Foundation
import simd

/// One primitive of a GLB file with its node transform applied: positions
/// and normals in the file's root space, and the PNG of its base color.
struct GLBPrimitive {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var textureCoordinates: [SIMD2<Float>]
    var indices: [UInt32]
    var image: Data
}

/// Reads the part of glTF 2.0 binary the model exports use: triangle lists
/// with float positions, normals and one set of texture coordinates, and a
/// base color texture embedded in the file. Anything else is an error, not
/// a guess, so a model that would bake wrong does not bake at all.
enum GLBReader {
    static func read(_ url: URL) throws -> [GLBPrimitive] {
        let file = try Data(contentsOf: url)
        let name = url.lastPathComponent
        guard file.count >= 28,
              file.littleEndianUInt32(at: 0) == 0x4654_6C67,
              file.littleEndianUInt32(at: 4) == 2 else {
            throw BakeError("\(name): not a glTF 2.0 binary file")
        }
        let jsonByteCount = Int(file.littleEndianUInt32(at: 12))
        guard file.littleEndianUInt32(at: 16) == 0x4E4F_534A,
              file.count >= 20 + jsonByteCount + 8 else {
            throw BakeError("\(name): the JSON chunk is missing")
        }
        let binaryHeader = 20 + jsonByteCount
        let binaryByteCount = Int(file.littleEndianUInt32(at: binaryHeader))
        guard file.littleEndianUInt32(at: binaryHeader + 4) == 0x004E_4942,
              file.count >= binaryHeader + 8 + binaryByteCount else {
            throw BakeError("\(name): the binary chunk is missing")
        }
        let json = file.subdata(in: 20..<(20 + jsonByteCount))
        let binary = file.subdata(in: (binaryHeader + 8)..<(binaryHeader + 8 + binaryByteCount))
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw BakeError("\(name): the JSON chunk is not an object")
        }
        return try Document(name: name, root: root, binary: binary).primitives()
    }

    private struct Document {
        let name: String
        let root: [String: Any]
        let binary: Data

        func array(_ key: String) -> [[String: Any]] {
            root[key] as? [[String: Any]] ?? []
        }

        func primitives() throws -> [GLBPrimitive] {
            let scenes = array("scenes")
            let sceneIndex = (root["scene"] as? NSNumber)?.intValue ?? 0
            guard sceneIndex < scenes.count else {
                throw BakeError("\(name): no scene")
            }
            var result: [GLBPrimitive] = []
            for node in integers(scenes[sceneIndex]["nodes"]) {
                try visit(node: node, parent: matrix_identity_float4x4, into: &result)
            }
            guard result.isEmpty == false else {
                throw BakeError("\(name): no mesh in the scene")
            }
            return result
        }

        private func visit(node index: Int, parent: simd_float4x4, into result: inout [GLBPrimitive]) throws {
            let nodes = array("nodes")
            guard index < nodes.count else {
                throw BakeError("\(name): node \(index) does not exist")
            }
            let node = nodes[index]
            let transform = parent * localTransform(of: node)
            if let meshIndex = (node["mesh"] as? NSNumber)?.intValue {
                let meshes = array("meshes")
                guard meshIndex < meshes.count else {
                    throw BakeError("\(name): mesh \(meshIndex) does not exist")
                }
                for primitive in meshes[meshIndex]["primitives"] as? [[String: Any]] ?? [] {
                    result.append(try read(primitive: primitive, transform: transform))
                }
            }
            for child in integers(node["children"]) {
                try visit(node: child, parent: transform, into: &result)
            }
        }

        private func localTransform(of node: [String: Any]) -> simd_float4x4 {
            let matrix = floats(node["matrix"])
            if matrix.count == 16 {
                return simd_float4x4(columns: (SIMD4(matrix[0], matrix[1], matrix[2], matrix[3]),
                                               SIMD4(matrix[4], matrix[5], matrix[6], matrix[7]),
                                               SIMD4(matrix[8], matrix[9], matrix[10], matrix[11]),
                                               SIMD4(matrix[12], matrix[13], matrix[14], matrix[15])))
            }
            var transform = matrix_identity_float4x4
            let translation = floats(node["translation"])
            if translation.count == 3 {
                transform.columns.3 = SIMD4(translation[0], translation[1], translation[2], 1)
            }
            let rotation = floats(node["rotation"])
            if rotation.count == 4 {
                let quaternion = simd_quatf(ix: rotation[0], iy: rotation[1], iz: rotation[2], r: rotation[3])
                transform = transform * simd_float4x4(quaternion)
            }
            let scale = floats(node["scale"])
            if scale.count == 3 {
                transform = transform * simd_float4x4(diagonal: SIMD4(scale[0], scale[1], scale[2], 1))
            }
            return transform
        }

        private func read(primitive: [String: Any], transform: simd_float4x4) throws -> GLBPrimitive {
            let mode = (primitive["mode"] as? NSNumber)?.intValue ?? 4
            guard mode == 4 else {
                throw BakeError("\(name): a primitive is not a triangle list")
            }
            let attributes = primitive["attributes"] as? [String: Any] ?? [:]
            guard let positionAccessor = (attributes["POSITION"] as? NSNumber)?.intValue,
                  let normalAccessor = (attributes["NORMAL"] as? NSNumber)?.intValue,
                  let coordinateAccessor = (attributes["TEXCOORD_0"] as? NSNumber)?.intValue else {
                throw BakeError("\(name): a primitive lacks POSITION, NORMAL or TEXCOORD_0")
            }
            let positionValues = try floatAccessor(positionAccessor, components: 3)
            let normalValues = try floatAccessor(normalAccessor, components: 3)
            let coordinateValues = try floatAccessor(coordinateAccessor, components: 2)
            let vertexCount = positionValues.count / 3
            guard normalValues.count == vertexCount * 3, coordinateValues.count == vertexCount * 2 else {
                throw BakeError("\(name): the attributes of a primitive differ in length")
            }

            let linear = simd_float3x3(columns: (SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                                 SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                                 SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
            let determinant = simd_determinant(linear)
            guard abs(determinant) > 1e-12 else {
                throw BakeError("\(name): a node transform is singular")
            }
            let normalMatrix = linear.inverse.transpose

            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var coordinates: [SIMD2<Float>] = []
            positions.reserveCapacity(vertexCount)
            normals.reserveCapacity(vertexCount)
            coordinates.reserveCapacity(vertexCount)
            for vertex in 0..<vertexCount {
                let position = SIMD4(positionValues[vertex * 3], positionValues[vertex * 3 + 1],
                                     positionValues[vertex * 3 + 2], 1)
                let transformed = transform * position
                positions.append(SIMD3(transformed.x, transformed.y, transformed.z))
                let normal = normalMatrix * SIMD3(normalValues[vertex * 3], normalValues[vertex * 3 + 1],
                                                  normalValues[vertex * 3 + 2])
                let length = simd_length(normal)
                normals.append(length > 0 ? normal / length : SIMD3(0, 1, 0))
                coordinates.append(SIMD2(coordinateValues[vertex * 2], coordinateValues[vertex * 2 + 1]))
            }

            var indices: [UInt32]
            if let indexAccessor = (primitive["indices"] as? NSNumber)?.intValue {
                indices = try indexAccessorValues(indexAccessor)
            } else {
                indices = (0..<UInt32(vertexCount)).map { $0 }
            }
            guard indices.count % 3 == 0, indices.allSatisfy({ Int($0) < vertexCount }) else {
                throw BakeError("\(name): the indices of a primitive are not valid triangles")
            }
            // A mirroring transform turns every triangle inside out.
            if determinant < 0 {
                for triangle in stride(from: 0, to: indices.count, by: 3) {
                    indices.swapAt(triangle + 1, triangle + 2)
                }
            }

            return GLBPrimitive(positions: positions,
                                normals: normals,
                                textureCoordinates: coordinates,
                                indices: indices,
                                image: try baseColorImage(of: primitive))
        }

        private func baseColorImage(of primitive: [String: Any]) throws -> Data {
            let materials = array("materials")
            guard let materialIndex = (primitive["material"] as? NSNumber)?.intValue,
                  materialIndex < materials.count,
                  let pbr = materials[materialIndex]["pbrMetallicRoughness"] as? [String: Any],
                  let reference = pbr["baseColorTexture"] as? [String: Any],
                  let textureIndex = (reference["index"] as? NSNumber)?.intValue else {
                throw BakeError("\(name): a primitive has no base color texture")
            }
            guard ((reference["texCoord"] as? NSNumber)?.intValue ?? 0) == 0 else {
                throw BakeError("\(name): the base color texture does not use TEXCOORD_0")
            }
            let factor = floats(pbr["baseColorFactor"])
            guard factor.isEmpty || factor == [1, 1, 1, 1] else {
                throw BakeError("\(name): a base color factor other than white is not baked")
            }
            let textures = array("textures")
            let images = array("images")
            guard textureIndex < textures.count,
                  let imageIndex = (textures[textureIndex]["source"] as? NSNumber)?.intValue,
                  imageIndex < images.count,
                  let viewIndex = (images[imageIndex]["bufferView"] as? NSNumber)?.intValue else {
                throw BakeError("\(name): the base color image is not embedded in the file")
            }
            let view = try bufferView(viewIndex)
            return binary.subdata(in: view.offset..<(view.offset + view.byteCount))
        }

        // MARK: - Accessors

        private func bufferView(_ index: Int) throws -> (offset: Int, byteCount: Int, stride: Int?) {
            let views = array("bufferViews")
            guard index < views.count else {
                throw BakeError("\(name): buffer view \(index) does not exist")
            }
            let view = views[index]
            let offset = (view["byteOffset"] as? NSNumber)?.intValue ?? 0
            let byteCount = (view["byteLength"] as? NSNumber)?.intValue ?? 0
            guard ((view["buffer"] as? NSNumber)?.intValue ?? 0) == 0,
                  offset >= 0, byteCount >= 0, offset + byteCount <= binary.count else {
                throw BakeError("\(name): buffer view \(index) lies outside the binary chunk")
            }
            return (offset, byteCount, (view["byteStride"] as? NSNumber)?.intValue)
        }

        /// The element offsets of an accessor, each checked against its view.
        private func elementOffsets(_ index: Int, componentType: [Int], components: Int,
                                    componentByteCount: (Int) -> Int) throws -> (offsets: [Int], componentType: Int) {
            let accessors = array("accessors")
            guard index < accessors.count else {
                throw BakeError("\(name): accessor \(index) does not exist")
            }
            let accessor = accessors[index]
            let type = (accessor["componentType"] as? NSNumber)?.intValue ?? 0
            let typeNames = [1: "SCALAR", 2: "VEC2", 3: "VEC3"]
            guard componentType.contains(type),
                  accessor["type"] as? String == typeNames[components],
                  accessor["sparse"] == nil,
                  let viewIndex = (accessor["bufferView"] as? NSNumber)?.intValue else {
                throw BakeError("\(name): accessor \(index) has a layout the baker does not read")
            }
            let view = try bufferView(viewIndex)
            let count = (accessor["count"] as? NSNumber)?.intValue ?? 0
            let elementByteCount = componentByteCount(type) * components
            let stride = view.stride ?? elementByteCount
            let start = (accessor["byteOffset"] as? NSNumber)?.intValue ?? 0
            guard count >= 0, start >= 0,
                  count == 0 || start + (count - 1) * stride + elementByteCount <= view.byteCount else {
                throw BakeError("\(name): accessor \(index) reads past its buffer view")
            }
            return ((0..<count).map { view.offset + start + $0 * stride }, type)
        }

        private func floatAccessor(_ index: Int, components: Int) throws -> [Float] {
            let (offsets, _) = try elementOffsets(index, componentType: [5126], components: components) { _ in 4 }
            var values: [Float] = []
            values.reserveCapacity(offsets.count * components)
            binary.withUnsafeBytes { bytes in
                for offset in offsets {
                    for component in 0..<components {
                        let bits = bytes.loadUnaligned(fromByteOffset: offset + component * 4, as: UInt32.self)
                        values.append(Float(bitPattern: UInt32(littleEndian: bits)))
                    }
                }
            }
            return values
        }

        private func indexAccessorValues(_ index: Int) throws -> [UInt32] {
            let byteCounts = [5121: 1, 5123: 2, 5125: 4]
            let (offsets, type) = try elementOffsets(index, componentType: [5121, 5123, 5125],
                                                     components: 1) { byteCounts[$0] ?? 1 }
            return binary.withUnsafeBytes { bytes in
                offsets.map { offset in
                    switch type {
                    case 5121:
                        return UInt32(bytes[offset])
                    case 5123:
                        return UInt32(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                    default:
                        return UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                    }
                }
            }
        }

        private func integers(_ value: Any?) -> [Int] {
            (value as? [NSNumber])?.map(\.intValue) ?? []
        }

        private func floats(_ value: Any?) -> [Float] {
            (value as? [NSNumber])?.map(\.floatValue) ?? []
        }
    }
}
