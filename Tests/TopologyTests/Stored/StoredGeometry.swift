import Topology

/// A shape as the tapes keep it: its kind, then the count and the bits of
/// its coordinates (a point, line or ring) or the count and the encodings
/// of its parts. The value form makes every zero `+0.0` and every NaN one
/// NaN, so two shapes have the same value form exactly when they are equal
/// but for the sign of zeros (`Shape.equalsIgnoringZeroSign`, which also
/// takes NaNs of other bits apart: the value form of a NaN is used only
/// where the old tests compared NaN with NaN as equal).
extension Shape {
    func encoded(zeroCanonical: Bool = false, nanCanonical: Bool = false) -> [UInt8] {
        var s = ByteSink()
        encode(&s, zeroCanonical, nanCanonical)
        return s.bytes
    }

    private func encode(_ s: inout ByteSink, _ zero: Bool, _ nan: Bool) {
        s.u8(UInt8(kind.rawValue))
        switch kind {
        case .point, .lineString, .linearRing:
            s.varint(coordinates.count / 2)
            for c in coordinates {
                if zero && c == 0 { s.f64(0) } else if nan && c.isNaN { s.f64(.nan) } else { s.f64(c) }
            }
        default:
            s.varint(parts.count)
            for p in parts { p.encode(&s, zero, nan) }
        }
    }

    init(decoding bytes: [UInt8]) throws {
        var s = ByteSource(bytes)
        self = try Shape.decode(&s)
    }

    private static func decode(_ s: inout ByteSource) throws -> Shape {
        guard let kind = Kind(rawValue: Int(try s.u8())) else { throw TapeError("shape kind") }
        switch kind {
        case .point, .lineString, .linearRing:
            let n = try s.count()
            return Shape(kind: kind, coordinates: try (0..<(2 * n)).map { _ in try s.f64() })
        default:
            let n = try s.count()
            return Shape(kind: kind, parts: try (0..<n).map { _ in try decode(&s) })
        }
    }

    /// Whether the port can build this shape as it is: every ring empty, or
    /// closed (by `==`, as `LinearRing` checks) with at least four points.
    var isPortConstructible: Bool {
        switch kind {
        case .linearRing:
            let n = coordinates.count
            return n == 0 || (n >= 8 && coordinates[0] == coordinates[n - 2] && coordinates[1] == coordinates[n - 1])
        case .point: return coordinates.count <= 2
        case .lineString: return coordinates.count != 2
        case .polygon: return parts.allSatisfy { $0.kind == .linearRing && $0.isPortConstructible }
        case .multiPoint: return parts.allSatisfy { $0.kind == .point && $0.isPortConstructible }
        case .multiLineString: return parts.allSatisfy { $0.kind == .lineString && $0.isPortConstructible }
        case .multiPolygon: return parts.allSatisfy { $0.kind == .polygon && $0.isPortConstructible }
        case .geometryCollection: return parts.allSatisfy(\.isPortConstructible)
        }
    }

    /// The port's normal form of the shape.
    var portNormalized: Shape { Shape(topology().norm()) }

    /// Whether a coordinate is zero (either sign), where a value form differs.
    var hasZero: Bool { coordinates.contains { $0 == 0 } || parts.contains(where: \.hasZero) }
}

/// GEOS's answer of a geometry operation, as a tape stores it.
enum GeometryAnswer {
    /// GEOS failed (its C API returned NULL), with its message when kept.
    case failure(String?)
    case result(StoredGeometry)

    var result: StoredGeometry? {
        if case .result(let g) = self { return g }
        return nil
    }
}

/// How a result of the port compares with GEOS's, in GEOS's normal form.
enum NormalMatch {
    case equal, zeroSign, different
}

/// A geometry GEOS gave, as stored: its kind and number of parts, its shape
/// as it came (whole or as a digest), and its normal form (GEOS's
/// `normalize`). The normal form is not stored when it is the port's normal
/// form of the shape as it came, which the live mode checks before it
/// leaves it out. As digests: the shape as it came, the normal form unless
/// it is the same bytes (`normalIsRaw`), and the normal form's value form
/// where it has a zero (else no other shape is equal to it by value).
/// `varies`: GEOS gave another normal form in ten more runs (its snap
/// rounding shuffles at random), checked where a test asked and the result
/// has a zero.
struct StoredGeometry {
    var kind: Shape.Kind
    var numGeometries: Int
    var varies: Bool
    var raw: StoredBytes
    /// GEOS's normal form, when it is not the port's normal form of `raw`
    /// (kept whole) or not `raw` itself (a digest).
    var normal: StoredBytes?
    /// The digest of the normal form's value bytes, where they differ.
    var normalValue: UInt64?
    /// The normal form is the shape as it came (a digest of both).
    var normalIsRaw = false

    /// The shape as it came, when kept whole.
    var rawShape: Shape? { raw.whole.flatMap { try? Shape(decoding: $0) } }

    /// GEOS's normal form, when it can be had whole.
    var normalShape: Shape? {
        if let normal { return normal.whole.flatMap { try? Shape(decoding: $0) } }
        return rawShape?.portNormalized
    }

    /// The result as it came is GEOS's, bit for bit.
    func rawEquals(_ s: Shape) -> Bool { raw.matches(s.encoded()) }

    /// The port's result against GEOS's in GEOS's normal form, as the GEOS
    /// tests compared them (GEOS's `normalize` of both): a result that is
    /// GEOS's bit for bit as it came is GEOS's in normal form as well;
    /// another is compared in the port's normal form (`portNormal`), the same
    /// as GEOS's but for the order of NaN coordinates, which no result of the
    /// port that differs from GEOS's as it comes has.
    func compare(raw portRaw: Shape, normal portNormal: @autoclosure () -> Shape) -> NormalMatch {
        rawEquals(portRaw) ? .equal : compareNormal(portNormal())
    }

    /// The port's result in its normal form against GEOS's.
    func compareNormal(_ portNormal: Shape) -> NormalMatch {
        if let expected = normalShape {
            if portNormal == expected { return .equal }
            return portNormal.equalsIgnoringZeroSign(expected) ? .zeroSign : .different
        }
        guard let stored = normal ?? (normalIsRaw ? raw : nil) else { return .different }
        if stored.matches(portNormal.encoded()) { return .equal }
        guard let normalValue else { return .different }
        return normalValue == Digest.of(portNormal.encoded(zeroCanonical: true)) ? .zeroSign : .different
    }

    var description: String {
        if let s = rawShape { return "\(s)" }
        return "\(kind) of \(numGeometries) parts (stored as a digest)"
    }

    var normalDescription: String {
        if let s = normalShape { return "\(s)" }
        return "\(kind) of \(numGeometries) parts (stored as a digest)"
    }

    func write(_ s: inout ByteSink) {
        var flags: UInt8 = varies ? 1 : 0
        if normal != nil { flags |= 2 }
        if normalValue != nil { flags |= 4 }
        if normalIsRaw { flags |= 8 }
        s.u8(flags)
        s.u8(UInt8(kind.rawValue))
        s.varint(numGeometries)
        raw.write(&s)
        normal?.write(&s)
        if let normalValue { s.u64(normalValue) }
    }

    static func read(_ s: inout ByteSource) throws -> StoredGeometry {
        let flags = try s.u8()
        guard let kind = Shape.Kind(rawValue: Int(try s.u8())) else { throw TapeError("geometry kind") }
        let n = try s.count()
        let raw = try StoredBytes.read(&s)
        let normal = flags & 2 != 0 ? try StoredBytes.read(&s) : nil
        let value = flags & 4 != 0 ? try s.u64() : nil
        return StoredGeometry(kind: kind, numGeometries: n, varies: flags & 1 != 0, raw: raw, normal: normal, normalValue: value,
                              normalIsRaw: flags & 8 != 0)
    }
}

extension TapeWriter {
    /// What the tape keeps of a shape made as an input: its digest.
    static func made(_ s: Shape) -> StoredBytes { .digest(Digest.of(s.encoded())) }

    /// A shape made as an input, or nil where making it failed.
    func made(_ s: Shape?) {
        guard let s else { return tag(.none) }
        tag(.ints)
        raw { TapeWriter.made(s).write(&$0) }
    }

    /// A geometry answer: GEOS's result as it came and in its normal form.
    /// Returns whether its normal form had to be stored apart (the port's
    /// normal form of it differs from GEOS's).
    @discardableResult
    func geometry(_ answer: (raw: Shape, normal: Shape, numGeometries: Int, varies: Bool)?, message: String? = nil) -> Bool {
        guard let a = answer else {
            failure(message)
            return false
        }
        let rawBytes = a.raw.encoded()
        var g = StoredGeometry(kind: a.raw.kind, numGeometries: a.numGeometries, varies: a.varies,
                               raw: StoredBytes(rawBytes, limit: limit))
        var apart = false
        if case .whole = g.raw {
            if !(a.raw.isPortConstructible && a.raw.portNormalized == a.normal) {
                g.normal = .whole(a.normal.encoded())
                apart = true
            }
        } else {
            let normalBytes = a.normal.encoded()
            if normalBytes == rawBytes { g.normalIsRaw = true } else { g.normal = .digest(Digest.of(normalBytes)) }
            if a.normal.hasZero { g.normalValue = Digest.of(a.normal.encoded(zeroCanonical: true)) }
        }
        tag(.geometry)
        raw { g.write(&$0) }
        return apart
    }
}

extension TapeReader {
    func geometry() throws -> GeometryAnswer {
        switch try tag() {
        case .failure: return .failure(try failureMessage())
        case .geometry: return .result(try raw { try StoredGeometry.read(&$0) })
        case let t: throw TapeError("expected a geometry, found \(t)")
        }
    }
}
