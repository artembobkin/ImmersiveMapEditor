/// Reads a boundaries file (`.ser`, format version 2) into a `CountryBoundaries`.
///
/// Ported from `deserializer.rs` of the Rust crate country-boundaries 1.2.0 (Apache-2.0).
/// Every number is big endian. A string is a `u16` length followed by UTF-8 bytes. A count is
/// a `u32`, except the counts inside a cell (ids, areas, polygons), which are a `u8`.

import Foundation

/// A cursor over the bytes of a boundaries file.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Reads the whole file: the version, the size of every region, the raster width and the
    /// cells row by row from the north-west corner.
    mutating func readBoundaries() throws -> CountryBoundaries {
        let version = try readU16()
        if version != 2 {
            throw ReadError.wrongVersionNumber(expected: 2, actual: version)
        }

        let geometrySizesCount = try readUsize32()
        var geometrySizes: [String: Double] = Dictionary(minimumCapacity: geometrySizesCount)
        for _ in 0..<geometrySizesCount {
            let id = try readString()
            let size = try readF64()
            geometrySizes[id] = size
        }

        let rasterWidth = try readUsize32()
        let rasterSize = try readUsize32()

        var raster: [Cell] = []
        raster.reserveCapacity(rasterSize)
        for _ in 0..<rasterSize {
            raster.append(try readCell())
        }

        return CountryBoundaries(raster: raster, rasterWidth: rasterWidth, geometrySizes: geometrySizes)
    }

    mutating func readCell() throws -> Cell {
        let containingIdsSize = Int(try readU8())
        var containingIds: [String] = []
        containingIds.reserveCapacity(containingIdsSize)
        for _ in 0..<containingIdsSize {
            containingIds.append(try readString())
        }
        let intersectingAreasSize = Int(try readU8())
        var intersectingAreas: [IntersectingArea] = []
        intersectingAreas.reserveCapacity(intersectingAreasSize)
        for _ in 0..<intersectingAreasSize {
            intersectingAreas.append(try readAreas())
        }
        return Cell(containingIds: containingIds, intersectingAreas: intersectingAreas)
    }

    mutating func readAreas() throws -> IntersectingArea {
        let id = try readString()
        let outer = try readPolygons()
        let inner = try readPolygons()
        return IntersectingArea(id: id, multipolygon: Multipolygon(outer: outer, inner: inner))
    }

    mutating func readPolygons() throws -> [[Point]] {
        let size = Int(try readU8())
        var polygons: [[Point]] = []
        polygons.reserveCapacity(size)
        for _ in 0..<size {
            polygons.append(try readRing())
        }
        return polygons
    }

    mutating func readRing() throws -> [Point] {
        let size = try readUsize32()
        // The capacity is bounded by the bytes left, so a corrupt length cannot reserve gigabytes.
        var ring: [Point] = []
        ring.reserveCapacity(min(size, (bytes.count - offset) / 4))
        for _ in 0..<size {
            ring.append(try readPoint())
        }
        return ring
    }

    mutating func readPoint() throws -> Point {
        let x = try readU16()
        let y = try readU16()
        return Point(x: x, y: y)
    }

    mutating func readU8() throws -> UInt8 {
        try take(1).first!
    }

    mutating func readU16() throws -> UInt16 {
        let b = try take(2)
        return b.reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
    }

    mutating func readU32() throws -> UInt32 {
        let b = try take(4)
        return b.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// Reads a `u32` count. It always fits an `Int` on the 64 bit platforms Swift targets here.
    mutating func readUsize32() throws -> Int {
        Int(try readU32())
    }

    mutating func readF64() throws -> Double {
        let b = try take(8)
        return Double(bitPattern: b.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
    }

    mutating func readString() throws -> String {
        let length = Int(try readU16())
        let b = try take(length)
        guard let string = String(validating: b, as: UTF8.self) else {
            throw ReadError.unableToDecodeUtf8
        }
        return string
    }

    /// Returns the next `count` bytes, or throws if fewer are left.
    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard bytes.count - offset >= count else {
            throw ReadError.unexpectedEndOfData
        }
        let slice = bytes[offset..<offset + count]
        offset += count
        return slice
    }
}
