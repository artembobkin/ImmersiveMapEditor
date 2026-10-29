// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import Foundation
import zlib

/// Writes a PMTiles v3 archive of model tiles: a clustered archive with one
/// root directory, gzip for the directory, the metadata and the tiles. The
/// tile type is 0, "other": the payload is the engine's model tile, which
/// the PMTiles specification has no name for.
struct PMTilesWriter {
    struct Tile {
        var zoom: Int
        var x: Int
        var y: Int
        var data: Data
    }

    static let headerByteCount = 127
    /// A reader fetches the header and the root directory in one request of
    /// this many bytes, so both must fit in it.
    static let initialFetchByteCount = 16_384

    var tiles: [Tile] = []
    var metadata: [String: Any] = [:]

    func serialized() throws -> Data {
        guard tiles.isEmpty == false else {
            throw BakeError("no tiles to write")
        }
        let sorted = tiles
            .map { (id: Self.tileID(zoom: $0.zoom, x: $0.x, y: $0.y), tile: $0) }
            .sorted { $0.id < $1.id }

        var tileData = Data()
        var directory = Data()
        Self.appendVarint(&directory, UInt64(sorted.count))
        var lastID: UInt64 = 0
        for entry in sorted {
            Self.appendVarint(&directory, entry.id - lastID)
            lastID = entry.id
        }
        for _ in sorted {
            Self.appendVarint(&directory, 1)
        }
        var compressedTiles: [Data] = []
        for entry in sorted {
            let compressed = try Self.gzip(entry.tile.data)
            compressedTiles.append(compressed)
            Self.appendVarint(&directory, UInt64(compressed.count))
        }
        for (index, compressed) in compressedTiles.enumerated() {
            // Zero says the tile follows the one before it. Otherwise the
            // offset is stored plus one.
            Self.appendVarint(&directory, index == 0 ? UInt64(tileData.count) + 1 : 0)
            tileData.append(compressed)
        }

        let root = try Self.gzip(directory)
        guard Self.headerByteCount + root.count <= Self.initialFetchByteCount else {
            throw BakeError("the root directory does not fit in the first \(Self.initialFetchByteCount) bytes, and leaf directories are not written yet")
        }
        let metadataData = try Self.gzip(try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]))

        let zooms = tiles.map(\.zoom)
        var west = 180.0
        var south = 90.0
        var east = -180.0
        var north = -90.0
        for tile in tiles {
            let bounds = tileBounds(zoom: tile.zoom, x: tile.x, y: tile.y)
            west = min(west, bounds.west)
            south = min(south, bounds.south)
            east = max(east, bounds.east)
            north = max(north, bounds.north)
        }

        let rootOffset = UInt64(Self.headerByteCount)
        let metadataOffset = rootOffset + UInt64(root.count)
        let leafOffset = metadataOffset + UInt64(metadataData.count)
        let tileDataOffset = leafOffset

        var header = ByteWriter()
        header.append(Array("PMTiles".utf8))
        header.append(UInt8(3))
        header.append(rootOffset)
        header.append(UInt64(root.count))
        header.append(metadataOffset)
        header.append(UInt64(metadataData.count))
        header.append(leafOffset)
        header.append(UInt64(0))
        header.append(tileDataOffset)
        header.append(UInt64(tileData.count))
        // Addressed tiles, tile entries, tile contents: one each per tile.
        header.append(UInt64(sorted.count))
        header.append(UInt64(sorted.count))
        header.append(UInt64(sorted.count))
        header.append(UInt8(1))
        header.append(UInt8(2))
        header.append(UInt8(2))
        header.append(UInt8(0))
        header.append(UInt8(zooms.min() ?? 0))
        header.append(UInt8(zooms.max() ?? 0))
        header.append(Self.fixedPoint(west))
        header.append(Self.fixedPoint(south))
        header.append(Self.fixedPoint(east))
        header.append(Self.fixedPoint(north))
        header.append(UInt8(zooms.max() ?? 0))
        header.append(Self.fixedPoint((west + east) / 2))
        header.append(Self.fixedPoint((south + north) / 2))
        precondition(header.count == Self.headerByteCount)

        var archive = header.data
        archive.append(root)
        archive.append(metadataData)
        archive.append(tileData)
        return archive
    }

    /// Degrees as the header stores them: an integer of 1e-7 degrees.
    private static func fixedPoint(_ degrees: Double) -> Int32 {
        Int32((degrees * 10_000_000).rounded())
    }

    static func appendVarint(_ data: inout Data, _ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }

    /// The id of a tile: every tile of the zooms below, then the position
    /// of the tile on the Hilbert curve of its zoom.
    static func tileID(zoom: Int, x: Int, y: Int) -> UInt64 {
        var id: UInt64 = 0
        for lower in 0..<zoom {
            id += UInt64(1) << UInt64(2 * lower)
        }
        let side = UInt64(1) << UInt64(zoom)
        var tx = UInt64(x)
        var ty = UInt64(y)
        var distance: UInt64 = 0
        var step = side / 2
        while step > 0 {
            let rx: UInt64 = (tx & step) > 0 ? 1 : 0
            let ry: UInt64 = (ty & step) > 0 ? 1 : 0
            distance += step * step * ((3 * rx) ^ ry)
            if ry == 0 {
                if rx == 1 {
                    tx = side - 1 - tx
                    ty = side - 1 - ty
                }
                swap(&tx, &ty)
            }
            step /= 2
        }
        return id + distance
    }

    static func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, 15 + 16, 9, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw BakeError("zlib could not start a gzip stream")
        }
        defer { deflateEnd(&stream) }

        var input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, UInt(input.count))) + 64)
        var produced = 0
        var finished = false
        input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                stream.next_in = inputBuffer.baseAddress
                stream.avail_in = UInt32(inputBuffer.count)
                stream.next_out = outputBuffer.baseAddress
                stream.avail_out = UInt32(outputBuffer.count)
                finished = deflate(&stream, Z_FINISH) == Z_STREAM_END
                produced = outputBuffer.count - Int(stream.avail_out)
            }
        }
        guard finished else {
            throw BakeError("zlib could not finish a gzip stream")
        }
        return Data(output[0..<produced])
    }
}
