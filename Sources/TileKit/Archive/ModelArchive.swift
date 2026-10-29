import Foundation
import simd

/// The model archive the engine reads: a PMTiles file with one tile of
/// models per map tile, each in the engine's own form (ModelTileFormat,
/// version 4: one mesh, one texture array, one set of UVs, ready for the
/// GPU). Every built tile of the data folder goes in, its GLB placed at
/// its placement.json's origin and scaled by the Mercator scale there, as
/// the engine's baker in Modeling did for its landmark models (its code,
/// brought in here so the editor is one program; the user, 2026-10-29).
///
/// What version 4 carries: the palette on TEXCOORD_0, with everything the
/// bake put into it (the face shade, the Lambert lights, the side tones).
/// The light map on TEXCOORD_1 waits for the format's next version in the
/// engine and here together.
public enum ModelArchive {
    public struct Summary {
        public var tiles = 0
        public var models = 0
        public var bytes = 0
        public var lines: [String] = []
    }

    /// Bakes every built tile of zoom `z` into `out`. ASTC blocks of
    /// `blockEdge` (8, or 4 for a finer texture at four times the size).
    public static func run(_ paths: WorkspacePaths, z: Int, out: URL, blockEdge: Int = 8,
                           progress: (String) -> Void = { _ in }) throws -> Summary {
        let encoder = try TextureEncoder(blockEdge: blockEdge)
        var archive = PMTilesWriter()
        var summary = Summary()
        let zoomFolder = paths.tiles.appendingPathComponent("\(z)")
        for column in numberedFolders(in: zoomFolder) {
            for row in numberedFolders(in: column.url) {
                let build = row.url.appendingPathComponent("build")
                let placement = build.appendingPathComponent("placement.json")
                guard FileManager.default.fileExists(atPath: placement.path) else { continue }
                progress("\(z)/\(column.number)/\(row.number)")
                guard let tile = try bakeTile(zoom: z, x: column.number, y: row.number, placements: [placement],
                                              blockEdge: blockEdge, encoder: encoder) else { continue }
                let data = tile.serialized()
                archive.tiles.append(PMTilesWriter.Tile(zoom: z, x: column.number, y: row.number, data: data))
                summary.tiles += 1
                summary.models += tile.models.count
                let textureBytes = tile.texture.levels.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
                summary.lines.append("\(z)/\(column.number)/\(row.number): \(tile.indices.count / 3) triangles, \(tile.vertexCount) vertices, "
                                     + "\(tile.texture.layerCount) texture layers (\(megabytes(textureBytes))), tile \(megabytes(data.count))")
            }
        }
        guard !archive.tiles.isEmpty else { throw BakeError("no built tile of zoom \(z) under \(paths.tiles.path)") }
        archive.metadata = [
            "name": "ImmersiveMap models",
            "format": "immersivemap-model-tile",
            "version": Int(ModelTileFormat.version),
            "astc_block": "\(blockEdge)x\(blockEdge)",
        ]
        let data = try archive.serialized()
        try data.write(to: out, options: .atomic)
        summary.bytes = data.count
        return summary
    }

    static func numberedFolders(in folder: URL) -> [(number: Int, url: URL)] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents
            .compactMap { url in Int(url.lastPathComponent).map { (number: $0, url: url) } }
            .sorted { $0.number < $1.number }
    }

    static func megabytes(_ byteCount: Int) -> String {
        String(format: "%.2f MB", Double(byteCount) / 1_048_576)
    }

    /// One tile of the archive from its placement files, each with its GLB
    /// beside it; nil when there are none.
    static func bakeTile(zoom: Int, x: Int, y: Int, placements files: [URL], blockEdge: Int, encoder textureEncoder: TextureEncoder) throws -> ModelTile? {
        var placements: [(placement: Placement, file: URL)] = []
        for file in files {
            do {
                placements.append((try JSONDecoder().decode(Placement.self, from: Data(contentsOf: file)), file))
            } catch {
                throw BakeError("\(file.path): \(error)")
            }
        }
        guard placements.isEmpty == false else { return nil }
        placements.sort { $0.placement.id < $1.placement.id }
        for (index, entry) in placements.enumerated().dropFirst() where entry.placement.id == placements[index - 1].placement.id {
            throw BakeError("tile \(zoom)/\(x)/\(y): two models share the id \"\(entry.placement.id)\"")
        }

        // The models the map draws in one call first, the ones that cut into
        // the ground after them: their indices follow the merged ones.
        let merged = placements.filter { ($0.placement.cutsIntoGround ?? false) == false }
        let separate = placements.filter { $0.placement.cutsIntoGround ?? false }

        var models: [ModelTileModel] = []
        var vertices = ByteWriter()
        var indices: [UInt32] = []
        var layerDigests: [String] = []
        var layers: [EncodedTexture] = []
        var tileMinimum = SIMD3<Float>(repeating: .infinity)
        var tileMaximum = SIMD3<Float>(repeating: -.infinity)
        var mergedIndexCount = 0

        let tilesAcross = Double(1 << zoom)
        for (placement, file) in merged + separate {
            let origin = placement.origin
            let tile = tileCoordinate(latitude: origin.latitude, longitude: origin.longitude, zoom: zoom)
            guard tile.x == x, tile.y == y else {
                throw BakeError("\(placement.id): its origin lies in tile \(zoom)/\(tile.x)/\(tile.y), and the model is in the folder of \(zoom)/\(x)/\(y)")
            }
            let modelURL = file.deletingLastPathComponent().appendingPathComponent(placement.model)
            let primitives = try GLBReader.read(modelURL)

            // The origin in tile space, and the tile units a meter at its
            // latitude takes: the Mercator scale there, the same on every axis.
            let latitude = origin.latitude * .pi / 180
            let originX = ((origin.longitude + 180) / 360 * tilesAcross - Double(x)) * ModelTileFormat.tileExtent
            let originRow = ((1 - asinh(tan(latitude)) / .pi) / 2 * tilesAcross - Double(y)) * ModelTileFormat.tileExtent
            let originY = ModelTileFormat.tileExtent - originRow
            let unitsPerMeter = tilesAcross * ModelTileFormat.tileExtent
                / (ModelTileFormat.earthCircumferenceMeters * cos(latitude))
            let altitude = placement.altitudeMeters ?? 0

            let firstVertex = vertices.count / ModelTileFormat.vertexStride
            let firstIndex = indices.count
            var minimum = SIMD3<Float>(repeating: .infinity)
            var maximum = SIMD3<Float>(repeating: -.infinity)
            for primitive in primitives {
                let digest = TextureEncoder.digest(of: primitive.image).map { String(format: "%02x", $0) }.joined()
                let layer: Int
                if let existing = layerDigests.firstIndex(of: digest) {
                    layer = existing
                } else {
                    layer = layers.count
                    layerDigests.append(digest)
                    layers.append(try textureEncoder.encode(png: primitive.image, name: placement.id))
                }
                guard layer <= Int(UInt8.max) else {
                    throw BakeError("tile \(zoom)/\(x)/\(y): more than 256 different textures")
                }

                let baseVertex = UInt32(vertices.count / ModelTileFormat.vertexStride)
                for vertex in 0..<primitive.positions.count {
                    let source = primitive.positions[vertex]
                    let sourceNormal = primitive.normals[vertex]
                    let coordinate = primitive.textureCoordinates[vertex]
                    // The array texture has no repeat: a coordinate outside the
                    // unit square would sample the edge, not the next copy.
                    guard coordinate.x >= -1e-4, coordinate.x <= 1 + 1e-4,
                          coordinate.y >= -1e-4, coordinate.y <= 1 + 1e-4 else {
                        throw BakeError("\(placement.id): a texture coordinate lies outside 0...1")
                    }
                    guard source.x.isFinite, source.y.isFinite, source.z.isFinite else {
                        throw BakeError("\(placement.id): a position is not finite")
                    }
                    // The model's X east, Y up, -Z north into the tile's X
                    // east, Y north, Z up: a rotation, so the winding holds.
                    let position = SIMD3<Float>(Float(originX + Double(source.x) * unitsPerMeter),
                                                Float(originY - Double(source.z) * unitsPerMeter),
                                                Float((Double(source.y) + altitude) * unitsPerMeter))
                    let normal = SIMD3<Float>(sourceNormal.x, -sourceNormal.z, sourceNormal.y)
                    minimum = simd_min(minimum, position)
                    maximum = simd_max(maximum, position)
                    vertices.append(position.x)
                    vertices.append(position.y)
                    vertices.append(position.z)
                    for component in [normal.x, normal.y, normal.z] {
                        vertices.append(Int8(max(-127, min(127, (component * 127).rounded()))))
                    }
                    vertices.append(UInt8(layer))
                    for component in [coordinate.x, coordinate.y] {
                        vertices.append(UInt16((max(0, min(1, component)) * 65_535).rounded()))
                    }
                }
                indices.append(contentsOf: primitive.indices.map { $0 + baseVertex })
            }

            let cutsIntoGround = placement.cutsIntoGround ?? false
            if cutsIntoGround == false {
                mergedIndexCount = indices.count
            }
            tileMinimum = simd_min(tileMinimum, minimum)
            tileMaximum = simd_max(tileMaximum, maximum)
            models.append(ModelTileModel(id: placement.id,
                                         latitude: origin.latitude,
                                         longitude: origin.longitude,
                                         altitudeMeters: Float(altitude),
                                         cutsIntoGround: cutsIntoGround,
                                         replacedBuildings: try placement.replacedBuildings(),
                                         firstIndex: UInt32(firstIndex),
                                         indexCount: UInt32(indices.count - firstIndex),
                                         firstVertex: UInt32(firstVertex),
                                         vertexCount: UInt32(vertices.count / ModelTileFormat.vertexStride - firstVertex),
                                         boundsMinimum: minimum,
                                         boundsMaximum: maximum))
        }

        let first = layers[0]
        guard layers.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw BakeError("tile \(zoom)/\(x)/\(y): the textures differ in size, and the layers of an array share one")
        }
        let levels = (0..<first.levels.count).map { level in
            layers.map { $0.levels[level] }
        }
        return ModelTile(zoom: zoom, x: x, y: y, models: models,
                         mergedIndexCount: mergedIndexCount,
                         boundsMinimum: tileMinimum,
                         boundsMaximum: tileMaximum,
                         vertices: vertices.data, indices: indices,
                         texture: ModelTileTexture(width: first.width, height: first.height,
                                                   blockEdge: blockEdge, layerCount: layers.count,
                                                   levels: levels))
    }
}
