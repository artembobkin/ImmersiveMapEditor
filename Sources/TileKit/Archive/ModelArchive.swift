import Foundation
import GLTF
import ModelTileFormat
import PMTiles
import simd

/// The model archive the engine reads: a PMTiles file with one tile of
/// models per map tile, each in the engine's own form (the engine's
/// `ModelTileFormat` module, which reads and writes it, so the layout is
/// written down once for both: the user, 2026-11-16. One mesh, one texture
/// array, one set of UVs, ready for the GPU). Every
/// built tile of the data folder goes in, its GLB placed at its
/// placement.json's origin and scaled by the Mercator scale there, as the
/// engine's baker in Modeling did for its landmark models (its code,
/// brought in here so the editor is one program; the user, 2026-10-29).
///
/// What a tile carries: the palette on TEXCOORD_0, with everything the bake
/// put into it (the face shade, the Lambert lights, the side tones). The
/// light map on TEXCOORD_1 waits for a later version of the format in the
/// engine and here together. A tile is kept small, since the engine reads
/// none past 64 MB: a vertex that comes twice is written once, and a
/// position is two bytes an axis across the tile's bounding box (the user,
/// 2026-11-16: Red Square's tile was 73 MB and never shown).
public enum ModelArchive {
    public struct Summary {
        public var tiles = 0
        public var models = 0
        public var bytes = 0
        public var lines: [String] = []
    }

    /// The zoom of the archive's tiles, the engine's own constant: it asks
    /// for model tiles of this zoom alone, whatever zoom the map is at, so
    /// a built tile of a deeper zoom goes into the archive tile over it,
    /// the four of one zoom 15 tile baked as one (the user, 2026-11-02: an
    /// archive of zoom 15 tiles showed nothing on the map).
    public static let archiveZoom = ModelTileContents.tileZoom

    /// The length of the Web Mercator world, the equator, in meters: what
    /// the map's projection takes it to be.
    static let earthCircumferenceMeters: Double = 40_075_016.686
    /// The units of tile space along a tile's edge, the map's own extent.
    static let tileExtent = Double(ModelTileContents.tileExtent)

    /// Bakes every built tile of zoom `z` into `out`, by the archive's
    /// tiles of `archiveZoom`. ASTC blocks of `blockEdge` (8, or 4 for a
    /// finer texture at four times the size).
    public static func run(_ paths: WorkspacePaths, z: Int, out: URL, blockEdge: Int = 8,
                           progress: (String) -> Void = { _ in }) throws -> Summary {
        guard z >= archiveZoom else { throw BakeError("the archive holds tiles of zoom \(archiveZoom): built tiles of zoom \(z) are coarser") }
        let encoder = try TextureEncoder(blockEdge: blockEdge)
        var archive = PMTilesWriter()
        var summary = Summary()
        let zoomFolder = paths.tiles.appendingPathComponent("\(z)")
        let shift = z - archiveZoom
        // The built tiles' placements by the archive tile over them.
        var byTile: [[Int]: [URL]] = [:]
        for column in numberedFolders(in: zoomFolder) {
            for row in numberedFolders(in: column.url) {
                let placement = row.url.appendingPathComponent("build").appendingPathComponent("placement.json")
                guard FileManager.default.fileExists(atPath: placement.path) else { continue }
                byTile[[column.number >> shift, row.number >> shift], default: []].append(placement)
            }
        }
        for key in byTile.keys.sorted(by: { ($0[0], $0[1]) < ($1[0], $1[1]) }) {
            let (x, y, files) = (key[0], key[1], byTile[key]!)
            // The built tiles of zoom z into the engine's tile of zoom 14 over
            // them, named both ways (the user, 2026-11-06: "Archiving
            // 14/..." read as if the build were of zoom 14).
            let built = files.map { $0.deletingLastPathComponent().deletingLastPathComponent() }
                .map { "\(z)/\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }.sorted()
            progress("\(built.joined(separator: ", ")) to \(archiveZoom)/\(x)/\(y)")
            // A tile that cannot be read is left out and named, the rest
            // archived (the user, 2026-11-04: one unreadable GLB, a build
            // of parts a tile had none of, failed the whole archive).
            let baked: ModelTile?
            do {
                baked = try bakeTile(zoom: archiveZoom, x: x, y: y, placements: files, blockEdge: blockEdge, encoder: encoder)
            } catch {
                let note = "\(archiveZoom)/\(x)/\(y) left out, its builds could not be read (rebuild the tile): \(error)"
                print("[archive] \(note)")
                summary.lines.append(note)
                continue
            }
            guard let tile = baked else { continue }
            let data = tile.serialized()
            // A tile past what the engine reads is left out and named, as
            // one that cannot be read is: the engine takes a larger one for
            // a corrupt file and shows none of its models, saying so only
            // in its log (the user, 2026-11-16: Red Square's tile, 73 MB,
            // was archived and never shown, and nothing said why).
            guard data.count <= PMTilesWriter.maximumTileByteCount else {
                let note = "\(archiveZoom)/\(x)/\(y) left out, it is \(megabytes(data.count)) and the engine reads a tile up to "
                    + "\(megabytes(PMTilesWriter.maximumTileByteCount)): its landmarks need fewer triangles (\(tile.indices.count / 3) now)"
                print("[archive] \(note)")
                summary.lines.append(note)
                continue
            }
            archive.tiles.append(PMTilesWriter.Tile(zoom: archiveZoom, x: x, y: y, data: data))
            summary.tiles += 1
            summary.models += tile.models.count
            let textureBytes = tile.texture.levels.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
            summary.lines.append("\(archiveZoom)/\(x)/\(y) (\(files.count) built of zoom \(z)): \(tile.indices.count / 3) triangles, \(tile.vertexCount) vertices, "
                                 + "\(tile.texture.layerCount) texture layers (\(megabytes(textureBytes))), tile \(megabytes(data.count))")
        }
        guard !archive.tiles.isEmpty else { throw BakeError("no built tile of zoom \(z) under \(paths.tiles.path)") }
        archive.metadata = [
            "name": "ImmersiveMap models",
            "format": "immersivemap-model-tile",
            "version": Int(ModelTileContents.version),
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

        // Every model is merged: the map draws the tile in one call (no
        // model cuts into the ground, the user, 2026-11-05).

        var layerDigests: [String] = []
        var layers: [EncodedTexture] = []
        var tileMinimum = SIMD3<Float>(repeating: .infinity)
        var tileMaximum = SIMD3<Float>(repeating: -.infinity)

        let tilesAcross = Double(1 << zoom)
        // The size every layer of the tile's array takes: the largest
        // texture of its models, the smaller ones grown to it.
        var layerSize: (width: Int, height: Int)?
        for (placement, file) in placements {
            let modelURL = file.deletingLastPathComponent().appendingPathComponent(placement.model)
            for primitive in try GLTF.indexedPrimitives(modelURL) {
                guard let size = TextureEncoder.pngSize(primitive.image) else { continue }
                if layerSize.map({ size.width > $0.width || size.height > $0.height }) ?? true { layerSize = size }
            }
        }

        // The models as read, in tile space: a vertex's place in the tile
        // is a share of the tile's bounding box, known only once every
        // model is in.
        var sources: [SourceModel] = []
        for (placement, file) in placements {
            let origin = placement.origin
            let tile = tileCoordinate(latitude: origin.latitude, longitude: origin.longitude, zoom: zoom)
            guard tile.x == x, tile.y == y else {
                throw BakeError("\(placement.id): its origin lies in tile \(zoom)/\(tile.x)/\(tile.y), and the model is in the folder of \(zoom)/\(x)/\(y)")
            }
            let modelURL = file.deletingLastPathComponent().appendingPathComponent(placement.model)
            let primitives = try GLTF.indexedPrimitives(modelURL)

            // The origin in tile space, and the tile units a meter at its
            // latitude takes: the Mercator scale there, the same on every axis.
            let latitude = origin.latitude * .pi / 180
            let originX = ((origin.longitude + 180) / 360 * tilesAcross - Double(x)) * tileExtent
            let originRow = ((1 - asinh(tan(latitude)) / .pi) / 2 * tilesAcross - Double(y)) * tileExtent
            let originY = tileExtent - originRow
            let unitsPerMeter = tilesAcross * tileExtent
                / (earthCircumferenceMeters * cos(latitude))
            let altitude = placement.altitudeMeters ?? 0

            var source = SourceModel(id: placement.id, latitude: origin.latitude, longitude: origin.longitude,
                                     altitudeMeters: Float(altitude), replacedBuildings: try placement.replacedBuildings())
            for primitive in primitives {
                let digest = TextureEncoder.digest(of: primitive.image).map { String(format: "%02x", $0) }.joined()
                    + (layerSize.map { "-\($0.width)x\($0.height)" } ?? "")
                let layer: Int
                if let existing = layerDigests.firstIndex(of: digest) {
                    layer = existing
                } else {
                    layer = layers.count
                    layerDigests.append(digest)
                    layers.append(try textureEncoder.encode(png: primitive.image, name: placement.id, size: layerSize))
                }
                guard layer <= Int(UInt8.max) else {
                    throw BakeError("tile \(zoom)/\(x)/\(y): more than 256 different textures")
                }

                let baseVertex = UInt32(source.positions.count)
                for vertex in 0..<primitive.positions.count {
                    let position = primitive.positions[vertex]
                    let normal = primitive.normals[vertex]
                    let coordinate = primitive.textureCoordinates[vertex]
                    // The array texture has no repeat: a coordinate outside the
                    // unit square would sample the edge, not the next copy.
                    guard coordinate.x >= -1e-4, coordinate.x <= 1 + 1e-4,
                          coordinate.y >= -1e-4, coordinate.y <= 1 + 1e-4 else {
                        throw BakeError("\(placement.id): a texture coordinate lies outside 0...1")
                    }
                    guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
                        throw BakeError("\(placement.id): a position is not finite")
                    }
                    // The model's X east, Y up, -Z north into the tile's X
                    // east, Y north, Z up: a rotation, so the winding holds.
                    source.positions.append(SIMD3<Float>(Float(originX + Double(position.x) * unitsPerMeter),
                                                         Float(originY - Double(position.z) * unitsPerMeter),
                                                         Float((Double(position.y) + altitude) * unitsPerMeter)))
                    source.surfaces.append(ModelTileVertex(normal: SIMD3<Float>(normal.x, -normal.z, normal.y),
                                                           layer: UInt8(layer), coordinate: coordinate))
                }
                source.indices.append(contentsOf: primitive.indices.map { $0 + baseVertex })
            }
            for position in source.positions {
                source.minimum = simd_min(source.minimum, position)
                source.maximum = simd_max(source.maximum, position)
            }
            tileMinimum = simd_min(tileMinimum, source.minimum)
            tileMaximum = simd_max(tileMaximum, source.maximum)
            sources.append(source)
        }

        var models: [ModelTile.Model] = []
        var vertices = Data()
        var indices: [UInt32] = []
        for source in sources {
            let firstVertex = vertices.count / ModelTileContents.vertexStride
            let firstIndex = indices.count
            // The model's vertices already written, by their bytes: one that
            // comes again is written once and named again by its index. The
            // build splits a corner wherever its light map coordinates
            // differ, and the archive carries none, so two fifths of a
            // tile's vertices were copies (the user, 2026-11-16: Red
            // Square's tile, 73 MB, was past the 64 MB the engine reads).
            var written: [ModelTileVertex: UInt32] = [:]
            // Where each of the model's vertices went in the tile.
            var placed = [UInt32](repeating: 0, count: source.positions.count)
            for vertex in 0..<source.positions.count {
                var record = source.surfaces[vertex]
                record.place(source.positions[vertex], minimum: tileMinimum, maximum: tileMaximum)
                if let index = written[record] {
                    placed[vertex] = index
                    continue
                }
                let index = UInt32(vertices.count / ModelTileContents.vertexStride)
                written[record] = index
                placed[vertex] = index
                record.append(to: &vertices)
            }
            indices.append(contentsOf: source.indices.map { placed[Int($0)] })
            models.append(ModelTile.Model(id: source.id,
                                         latitude: source.latitude,
                                         longitude: source.longitude,
                                         altitudeMeters: source.altitudeMeters,
                                         replacedBuildings: source.replacedBuildings,
                                         firstIndex: UInt32(firstIndex),
                                         indexCount: UInt32(indices.count - firstIndex),
                                         firstVertex: UInt32(firstVertex),
                                         vertexCount: UInt32(vertices.count / ModelTileContents.vertexStride - firstVertex),
                                         boundsMinimum: source.minimum,
                                         boundsMaximum: source.maximum))
        }

        let first = layers[0]
        guard layers.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw BakeError("tile \(zoom)/\(x)/\(y): the textures differ in size, and the layers of an array share one")
        }
        let levels = (0..<first.levels.count).map { level in
            layers.map { $0.levels[level] }
        }
        return ModelTile(zoom: zoom, x: x, y: y, models: models,
                         boundsMinimum: tileMinimum,
                         boundsMaximum: tileMaximum,
                         vertices: vertices, indices: indices,
                         texture: ModelTile.Texture(width: first.width, height: first.height,
                                                   blockEdge: blockEdge, layerCount: layers.count,
                                                   levels: levels))
    }

    /// A model as its build gave it, placed in tile space, before its
    /// vertices are written: a position and a surface a vertex, the
    /// triangles by indices into them.
    struct SourceModel {
        var id: String
        var latitude: Double
        var longitude: Double
        var altitudeMeters: Float
        var replacedBuildings: [ModelTileContents.ReplacedBuilding]
        var positions: [SIMD3<Float>] = []
        /// Each vertex's surface, its place set once the tile's bounding
        /// box is known.
        var surfaces: [ModelTileVertex] = []
        var indices: [UInt32] = []
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)
    }
}
