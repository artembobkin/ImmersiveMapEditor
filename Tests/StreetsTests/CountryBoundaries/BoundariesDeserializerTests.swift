/// Tests of reading a boundaries file, ported from the inline tests of `deserializer.rs` of
/// country-boundaries 1.2.0.

import Foundation
import Testing
@testable import CountryBoundaries

/// Returns whether the read throws on the given bytes.
private func fails<T>(_ bytes: [UInt8], _ read: (inout ByteReader) throws -> T) -> Bool {
    var reader = ByteReader(bytes)
    return (try? read(&reader)) == nil
}

/// Returns the result of the read on the given bytes.
private func value<T>(_ bytes: [UInt8], _ read: (inout ByteReader) throws -> T) throws -> T {
    var reader = ByteReader(bytes)
    return try read(&reader)
}

/// Returns whether the read throws on every proper prefix of the bytes but the last one, as
/// the crate's `for i in 0..len - 1` loops check.
private func failsOnPrefixes<T>(_ bytes: [UInt8], _ read: (inout ByteReader) throws -> T) -> Bool {
    (0..<bytes.count - 1).allSatisfy { fails(Array(bytes[0..<$0]), read) }
}

@Suite struct BoundariesDeserializerTests {
    @Test func readString() throws {
        #expect(fails([0x00]) { try $0.readString() })
        #expect(fails([0x00, 0x01]) { try $0.readString() })
        #expect(fails([0x00, 0x02, 0x41]) { try $0.readString() })

        #expect(try value([0x00, 0x00]) { try $0.readString() }.isEmpty)
        #expect(try value([0x00, 0x01, 0x41]) { try $0.readString() } == "A")
        #expect(try value([0x00, 0x02, 0x41, 0x42]) { try $0.readString() } == "AB")
    }

    @Test func readFloat() throws {
        #expect(fails([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { try $0.readF64() })
        #expect(try value([0x40, 0x29, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { try $0.readF64() } == 12.5)
    }

    @Test func readU8() throws {
        #expect(fails([]) { try $0.readU8() })
        #expect(try value([0x11]) { try $0.readU8() } == 17)
        #expect(try value([0x00]) { try $0.readU8() } == UInt8.min)
        #expect(try value([0xff]) { try $0.readU8() } == UInt8.max)
    }

    @Test func readU16() throws {
        #expect(fails([0x00]) { try $0.readU16() })
        #expect(try value([0x00, 0x11]) { try $0.readU16() } == 17)
        #expect(try value([0x00, 0x00]) { try $0.readU16() } == UInt16.min)
        #expect(try value([0xff, 0xff]) { try $0.readU16() } == UInt16.max)
    }

    @Test func readU32() throws {
        #expect(fails([0x00, 0x00, 0x00]) { try $0.readU32() })
        #expect(try value([0x00, 0x00, 0x00, 0x11]) { try $0.readU32() } == 17)
        #expect(try value([0x00, 0x00, 0x00, 0x00]) { try $0.readU32() } == UInt32.min)
        #expect(try value([0xff, 0xff, 0xff, 0xff]) { try $0.readU32() } == UInt32.max)
    }

    @Test func readUsize32() throws {
        #expect(fails([0x00, 0x00, 0x00]) { try $0.readUsize32() })
        #expect(try value([0x00, 0x00, 0x00, 0x11]) { try $0.readUsize32() } == 17)
        #expect(try value([0x00, 0x00, 0x00, 0x00]) { try $0.readUsize32() } == 0)
        #expect(try value([0x00, 0x00, 0xff, 0xff]) { try $0.readUsize32() } == 0xffff)
    }

    @Test func readPoint() throws {
        #expect(try value([0x00, 0x01, 0x00, 0x02]) { try $0.readPoint() } == Point(x: 1, y: 2))
    }

    @Test func readRing() throws {
        let empty: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        #expect(failsOnPrefixes(empty) { try $0.readRing() })
        #expect(try value(empty) { try $0.readRing() }.isEmpty)

        let twoPoints: [UInt8] = [
            0x00, 0x00, 0x00, 0x02, // length
            0x00, 0x01, // p1.x
            0x00, 0x02, // p1.y
            0x00, 0x03, // p2.x
            0x00, 0x04, // p2.y
        ]
        #expect(failsOnPrefixes(twoPoints) { try $0.readRing() })
        #expect(try value(twoPoints) { try $0.readRing() } == [Point(x: 1, y: 2), Point(x: 3, y: 4)])
    }

    @Test func readPolygons() throws {
        #expect(try value([0x00]) { try $0.readPolygons() }.isEmpty)

        let twoRings: [UInt8] = [
            0x02, // polygons length
            0x00, 0x00, 0x00, 0x01, // ring length
            0x00, 0x01, // p1.x
            0x00, 0x02, // p1.y
            0x00, 0x00, 0x00, 0x01, // ring length
            0x00, 0x03, // p2.x
            0x00, 0x04, // p2.y
        ]
        #expect(failsOnPrefixes(twoRings) { try $0.readPolygons() })
        #expect(try value(twoRings) { try $0.readPolygons() } == [[Point(x: 1, y: 2)], [Point(x: 3, y: 4)]])
    }

    @Test func readCell() throws {
        #expect(try value([0x00, 0x00]) { try $0.readCell() } == Cell(containingIds: [], intersectingAreas: []))

        let cell: [UInt8] = [
            0x01, // containing ids length
            0x00, 0x01, 0x41, // "A"
            0x01, // intersecting areas length
            0x00, 0x01, 0x42, // "B"
            0x00, 0x00, // empty multipolygon
        ]
        // The crate's test reads the prefixes as polygons here, not as a cell. Both are kept.
        #expect(failsOnPrefixes(cell) { try $0.readPolygons() })
        #expect(failsOnPrefixes(cell) { try $0.readCell() })
        let expected = Cell(
            containingIds: ["A"],
            intersectingAreas: [IntersectingArea(id: "B", multipolygon: Multipolygon(outer: [], inner: []))]
        )
        #expect(try value(cell) { try $0.readCell() } == expected)
    }

    @Test func readWrongVersion() {
        let minimum: [UInt8] = [
            0x00, 0x03, // version number
            0x00, 0x00, 0x00, 0x00, // geometry sizes map length
            0x00, 0x00, 0x00, 0x00, // raster width
            0x00, 0x00, 0x00, 0x00, // raster size
        ]
        #expect(throws: ReadError.wrongVersionNumber(expected: 2, actual: 3)) {
            try CountryBoundaries(data: Data(minimum))
        }
    }

    @Test func readMinimum() throws {
        let minimum: [UInt8] = [
            0x00, 0x02, // version number
            0x00, 0x00, 0x00, 0x00, // geometry sizes map length
            0x00, 0x00, 0x00, 0x00, // raster width
            0x00, 0x00, 0x00, 0x00, // raster size
        ]
        #expect(failsOnPrefixes(minimum) { try $0.readBoundaries() })
        let expected = CountryBoundaries(raster: [], rasterWidth: 0, geometrySizes: [:])
        #expect(try CountryBoundaries.fromReader(Data(minimum)) == expected)
    }

    @Test func readBasic() throws {
        let basic: [UInt8] = [
            0x00, 0x02, // version number
            0x00, 0x00, 0x00, 0x01, // geometry sizes map length
            0x00, 0x01, 0x41, // "A"
            0x40, 0x29, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 12.5
            0x00, 0x00, 0x00, 0x01, // raster width
            0x00, 0x00, 0x00, 0x01, // raster size
            0x01, // cell containing ids length
            0x00, 0x01, 0x41, // "A"
            0x00, // intersecting areas length
        ]
        #expect(failsOnPrefixes(basic) { try $0.readBoundaries() })
        let expected = CountryBoundaries(
            raster: [Cell(containingIds: ["A"], intersectingAreas: [])],
            rasterWidth: 1,
            geometrySizes: ["A": 12.5]
        )
        #expect(try CountryBoundaries(data: Data(basic)) == expected)
    }

    @Test func invalidUtf8IsAnError() {
        #expect(throws: ReadError.unableToDecodeUtf8) {
            var reader = ByteReader([0x00, 0x01, 0xff])
            _ = try reader.readString()
        }
    }
}
