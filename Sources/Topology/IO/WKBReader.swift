/// Reads Well-Known Binary (ISO and extended, either byte order; Z and M
/// read and dropped, an SRID skipped): JTS's `WKBReader`, for the recorded
/// calls of `Geometry`, whose geometries are WKB.
public struct WKBReader {
    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    let factory: GeometryFactory

    public init(_ factory: GeometryFactory = .default) { self.factory = factory }

    public func read(_ bytes: [UInt8]) throws -> Geometry {
        var r = Cursor(bytes: bytes)
        return try readGeometry(&r)
    }

    struct Cursor {
        let bytes: [UInt8]
        var at = 0
        var littleEndian = true

        mutating func byte() throws -> UInt8 {
            guard at < bytes.count else { throw ParseError(description: "WKB truncated") }
            defer { at += 1 }
            return bytes[at]
        }

        mutating func u32() throws -> UInt32 {
            guard at + 4 <= bytes.count else { throw ParseError(description: "WKB truncated") }
            var v: UInt32 = 0
            for i in 0..<4 { v |= UInt32(bytes[at + i]) << (8 * i) }
            at += 4
            return littleEndian ? v : v.byteSwapped
        }

        mutating func f64() throws -> Double {
            guard at + 8 <= bytes.count else { throw ParseError(description: "WKB truncated") }
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(bytes[at + i]) << (8 * i) }
            at += 8
            return Double(bitPattern: littleEndian ? v : v.byteSwapped)
        }
    }

    func readGeometry(_ r: inout Cursor) throws -> Geometry {
        r.littleEndian = try r.byte() == 1
        let typeInt = try r.u32()
        var hasZ = (typeInt & 0x8000_0000) != 0
        var hasM = (typeInt & 0x4000_0000) != 0
        let hasSRID = (typeInt & 0x2000_0000) != 0
        var type = Int(typeInt & 0xFFFF)
        // ISO: 1000s for Z, 2000s for M, 3000s for both.
        if type >= 1000 {
            let iso = type / 1000
            if iso == 1 || iso == 3 { hasZ = true }
            if iso == 2 || iso == 3 { hasM = true }
            type %= 1000
        }
        if hasSRID { _ = try r.u32() }
        let dims = 2 + (hasZ ? 1 : 0) + (hasM ? 1 : 0)
        func coordinate() throws -> Coordinate {
            let x = factory.precisionModel.makePrecise(try r.f64())
            let y = factory.precisionModel.makePrecise(try r.f64())
            for _ in 2..<dims { _ = try r.f64() }
            return Coordinate(x, y)
        }
        func sequence() throws -> [Coordinate] {
            let n = Int(try r.u32())
            return try (0..<n).map { _ in try coordinate() }
        }
        func ring() throws -> LinearRing { factory.createLinearRing(try sequence()) }
        func parts<T>(_ as: T.Type) throws -> [T] {
            let n = Int(try r.u32())
            let littleEndian = r.littleEndian
            defer { r.littleEndian = littleEndian }
            return try (0..<n).map { _ in
                guard let g = try readGeometry(&r) as? T else { throw ParseError(description: "WKB member of the wrong type") }
                return g
            }
        }
        switch type {
        case 1:
            let c = try coordinate()
            return c.x.isNaN && c.y.isNaN ? factory.createPoint() : factory.createPoint(c)
        case 2: return factory.createLineString(try sequence())
        case 3:
            let n = Int(try r.u32())
            guard n > 0 else { return factory.createPolygon() }
            let shell = try ring()
            let holes = try (1..<n).map { _ in try ring() }
            return factory.createPolygon(shell, holes)
        case 4: return factory.createMultiPoint(try parts(Point.self))
        case 5: return factory.createMultiLineString(try parts(LineString.self))
        case 6: return factory.createMultiPolygon(try parts(Polygon.self))
        case 7: return factory.createGeometryCollection(try parts(Geometry.self))
        default: throw ParseError(description: "Unknown WKB type \(type)")
        }
    }
}
