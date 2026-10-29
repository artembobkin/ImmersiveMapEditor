// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import Foundation

/// The model tile, version 4: every model whose origin lies in one zoom 14
/// map tile, merged into one mesh and ready for the GPU. One vertex buffer,
/// one index buffer and one texture array serve the whole tile, every
/// vertex is in the tile's own space, and the models that take no state of
/// their own come first in the indices, so the map draws them all in one
/// call under one matrix, the tile's.
///
/// Tile space is the space the map's own buildings are in: X east and Y
/// north from the tile's south-west corner, `tileExtent` units to a tile
/// edge, Z up from the ground in the same units. It is the Web Mercator
/// plane, so a model lies on the map exactly as the map's geometry does. A
/// model is placed rigidly at its origin: its meters are scaled by the
/// Mercator scale of the origin's latitude, on all three axes, and added to
/// the origin's place in the tile. A model reaching over the tile's edge
/// has coordinates outside 0...`tileExtent`. It is not cut.
///
/// All integers and floats are little-endian. The blocks follow the header
/// in the order below. The vertex, index and texture blocks each start on a
/// multiple of `blockAlignment`, and the tile ends on one, so a tile mapped
/// from the disk cache hands each block to Metal without a copy.
///
/// Header, `headerByteCount` bytes:
///
///     0   4 bytes  magic "IMMT"
///     4   u32      version, 4
///     8   u32 x 3  tile zoom, x, y
///     20  u32      model count
///     24  u32      vertex count
///     28  u32      index count
///     32  u32      vertex stride, 20
///     36  u32      texture layer count
///     40  u32 x 2  texture width, height of mip level 0
///     48  u32      texture mip level count
///     52  u32      ASTC block edge: 8 means 8x8
///     56  u32 x 2  model table offset, byte count
///     64  u32 x 2  string block offset, byte count
///     72  u32 x 2  vertex block offset, byte count
///     80  u32 x 2  index block offset, byte count
///     88  u32 x 2  texture block offset, byte count
///     96  u32 x 2  replaced building block offset, byte count
///     104 u32      merged index count: the indices from the first that
///                  draw in one call
///     108 u32      reserved, 0
///     112 f32 x 3  minimum of the tile's bounding box, tile space
///     124 f32 x 3  maximum of the tile's bounding box, tile space
///
/// Model table, `modelRecordByteCount` bytes per model. The models whose
/// indices are merged come first, then the ones that cut into the ground,
/// which the map draws one by one:
///
///     0   f64 x 2  latitude, longitude of the model's origin, degrees
///     16  f32      altitude of the origin above the map surface, meters,
///                  already in the vertices
///     20  u32      flags: bit 0, the model cuts into the ground
///     24  u32 x 2  the buildings the model replaces, in the replaced
///                  building block: first entry, entry count
///     32  u32      reserved, 0
///     36  u32 x 2  the model's id in the string block: offset, byte count
///     44  u32 x 2  first index, index count
///     52  u32 x 2  first vertex, vertex count
///     60  f32 x 3  minimum of the model's bounding box, tile space
///     72  f32 x 3  maximum of the model's bounding box, tile space
///     84  u32      reserved, 0
///
/// String block: the ids, UTF-8, one after another.
///
/// Replaced building block, `replacedBuildingEntryByteCount` bytes per
/// entry: a feature of the map's own tiles a model stands in for, in the
/// map tiles of one zoom.
///
///     0   u64      the element: its kind in the top four bits (1 node,
///                  2 way, 3 relation) and its OSM id in the rest
///     8   u32      the zoom of the map tiles the entry is for
///     12  u32      reserved, 0
///
/// An id names a building only within a zoom. The deepest map tiles carry
/// one feature per OSM element. The tiles above them merge buildings into
/// groups, and a group goes by the id of one of its members: there the
/// same id is a group of buildings, most of them elsewhere. So a model
/// lists what it replaces zoom by zoom, and the map hides in a tile only
/// the entries of that tile's zoom. A model lists every feature the map
/// would draw in its place: the map hides exactly the ids it is given.
///
/// Vertex, `vertexStride` bytes:
///
///     0   f32 x 3  position, tile space
///     12  i8 x 3   normal, signed normalized, tile space
///     15  u8       texture layer
///     16  u16 x 2  texture coordinate, unsigned normalized, V down
///
/// Index block: `u32` triangle list, counter-clockwise front faces seen
/// from outside. An index counts from the start of the tile's vertex block.
///
/// Texture block: ASTC LDR blocks with no file header, raw channel values
/// (no sRGB decode). Mip level 0 first: all layers of a level, layer 0
/// first, then the next level. A level of `w` by `h` pixels takes
/// `ceil(w / edge) * ceil(h / edge) * 16` bytes per layer.
enum ModelTileFormat {
    static let magic: [UInt8] = Array("IMMT".utf8)
    static let version: UInt32 = 4
    static let replacedBuildingEntryByteCount = 16
    static let headerByteCount = 136
    /// The units of tile space along a tile's edge, the map's own extent.
    static let tileExtent: Double = 4096
    /// The length of the Web Mercator world, the equator, in meters: what
    /// the map's projection takes it to be.
    static let earthCircumferenceMeters: Double = 40_075_016.686
    /// The bits of a replaced building entry the element's kind sits above.
    static let replacedBuildingKindShift: UInt64 = 60
    static let modelRecordByteCount = 88
    static let vertexStride = 20
    static let blockAlignment = 16_384
}

/// The OSM element of a building the map draws on its own.
struct OSMElement: Equatable {
    enum Kind: UInt8 {
        case node = 1
        case way = 2
        case relation = 3
    }

    let kind: Kind
    let id: UInt64
}

/// A feature of the map's tiles a model stands in for, in the map tiles of
/// one zoom.
struct ReplacedBuilding: Equatable {
    let element: OSMElement
    let mapTileZoom: Int
}

struct ModelTileModel {
    var id: String
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Float
    var cutsIntoGround: Bool
    /// The features of the map's own tiles the model stands in for, each in
    /// the map tiles of one zoom.
    var replacedBuildings: [ReplacedBuilding]
    var firstIndex: UInt32
    var indexCount: UInt32
    var firstVertex: UInt32
    var vertexCount: UInt32
    var boundsMinimum: SIMD3<Float>
    var boundsMaximum: SIMD3<Float>
}

/// The texture array of a tile: `levels[level][layer]` is the ASTC blocks
/// of one layer at one mip level.
struct ModelTileTexture {
    var width: Int
    var height: Int
    var blockEdge: Int
    var layerCount: Int
    var levels: [[Data]]
}

struct ModelTile {
    var zoom: Int
    var x: Int
    var y: Int
    /// The models whose indices are merged first, then the ones that cut
    /// into the ground.
    var models: [ModelTileModel]
    /// The indices from the first that the map draws in one call.
    var mergedIndexCount: Int
    var boundsMinimum: SIMD3<Float>
    var boundsMaximum: SIMD3<Float>
    /// `vertexCount` vertices of `ModelTileFormat.vertexStride` bytes.
    var vertices: Data
    var indices: [UInt32]
    var texture: ModelTileTexture

    var vertexCount: Int {
        vertices.count / ModelTileFormat.vertexStride
    }

    func serialized() -> Data {
        var strings = Data()
        var table = ByteWriter()
        var replaced = ByteWriter()
        for model in models {
            let idBytes = Data(model.id.utf8)
            table.append(model.latitude)
            table.append(model.longitude)
            table.append(model.altitudeMeters)
            table.append(UInt32(model.cutsIntoGround ? 1 : 0))
            table.append(UInt32(replaced.count / ModelTileFormat.replacedBuildingEntryByteCount))
            table.append(UInt32(model.replacedBuildings.count))
            for entry in model.replacedBuildings {
                replaced.append(UInt64(entry.element.kind.rawValue) << ModelTileFormat.replacedBuildingKindShift
                                | entry.element.id)
                replaced.append(UInt32(entry.mapTileZoom))
                replaced.append(UInt32(0))
            }
            table.append(UInt32(0))
            table.append(UInt32(strings.count))
            table.append(UInt32(idBytes.count))
            table.append(model.firstIndex)
            table.append(model.indexCount)
            table.append(model.firstVertex)
            table.append(model.vertexCount)
            for value in [model.boundsMinimum.x, model.boundsMinimum.y, model.boundsMinimum.z,
                          model.boundsMaximum.x, model.boundsMaximum.y, model.boundsMaximum.z] {
                table.append(value)
            }
            table.append(UInt32(0))
            strings.append(idBytes)
        }
        precondition(table.count == models.count * ModelTileFormat.modelRecordByteCount)

        var indexBlock = ByteWriter()
        for index in indices {
            indexBlock.append(index)
        }
        var textureBlock = Data()
        for level in texture.levels {
            precondition(level.count == texture.layerCount)
            for layer in level {
                textureBlock.append(layer)
            }
        }

        func aligned(_ offset: Int) -> Int {
            let alignment = ModelTileFormat.blockAlignment
            return (offset + alignment - 1) / alignment * alignment
        }
        let tableOffset = ModelTileFormat.headerByteCount
        let stringsOffset = tableOffset + table.count
        let replacedOffset = stringsOffset + strings.count
        let verticesOffset = aligned(replacedOffset + replaced.count)
        let indicesOffset = aligned(verticesOffset + vertices.count)
        let textureOffset = aligned(indicesOffset + indexBlock.count)

        var writer = ByteWriter()
        writer.append(ModelTileFormat.magic)
        writer.append(ModelTileFormat.version)
        writer.append(UInt32(zoom))
        writer.append(UInt32(x))
        writer.append(UInt32(y))
        writer.append(UInt32(models.count))
        writer.append(UInt32(vertexCount))
        writer.append(UInt32(indices.count))
        writer.append(UInt32(ModelTileFormat.vertexStride))
        writer.append(UInt32(texture.layerCount))
        writer.append(UInt32(texture.width))
        writer.append(UInt32(texture.height))
        writer.append(UInt32(texture.levels.count))
        writer.append(UInt32(texture.blockEdge))
        for (offset, byteCount) in [(tableOffset, table.count),
                                    (stringsOffset, strings.count),
                                    (verticesOffset, vertices.count),
                                    (indicesOffset, indexBlock.count),
                                    (textureOffset, textureBlock.count),
                                    (replacedOffset, replaced.count)] {
            writer.append(UInt32(offset))
            writer.append(UInt32(byteCount))
        }
        writer.append(UInt32(mergedIndexCount))
        writer.append(UInt32(0))
        for value in [boundsMinimum.x, boundsMinimum.y, boundsMinimum.z,
                      boundsMaximum.x, boundsMaximum.y, boundsMaximum.z] {
            writer.append(value)
        }
        precondition(writer.count == ModelTileFormat.headerByteCount)

        writer.append(table.data)
        writer.append(strings)
        writer.append(replaced.data)
        writer.pad(toMultipleOf: ModelTileFormat.blockAlignment)
        precondition(writer.count == verticesOffset)
        writer.append(vertices)
        writer.pad(toMultipleOf: ModelTileFormat.blockAlignment)
        precondition(writer.count == indicesOffset)
        writer.append(indexBlock.data)
        writer.pad(toMultipleOf: ModelTileFormat.blockAlignment)
        precondition(writer.count == textureOffset)
        writer.append(textureBlock)
        writer.pad(toMultipleOf: ModelTileFormat.blockAlignment)
        return writer.data
    }
}
