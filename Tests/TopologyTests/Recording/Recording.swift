import Foundation

/// A recording of `Geometry`'s calls (its `GEOMETRY_RECORD` mode, the format
/// in the doc comment of `Sources/Geometry/Recorder.swift`): the geometries
/// as WKB by id, and the calls in the order the build made them.
struct Recording {
    struct Call {
        var name: String
        var geometries: [UInt32]
        var numbers: [Double]
    }

    /// The recording's name: its folder under the recordings (`tiles/19808_10243`).
    var name: String
    var geometries: [UInt32: [UInt8]] = [:]
    var calls: [Call] = []

    struct FormatError: Error, CustomStringConvertible {
        var description: String
    }

    init(url: URL, name: String) throws {
        self.name = name
        let data = try Data(contentsOf: url)
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var at = 0
            func need(_ n: Int) throws {
                if at + n > raw.count { throw FormatError(description: "\(url.lastPathComponent): truncated at \(at)") }
            }
            func u8() throws -> UInt8 { try need(1); defer { at += 1 }; return raw[at] }
            func u32() throws -> UInt32 {
                try need(4)
                defer { at += 4 }
                return UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
            }
            func f64() throws -> Double {
                try need(8)
                defer { at += 8 }
                return Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt64.self)))
            }
            func bytes(_ n: Int) throws -> [UInt8] {
                try need(n)
                defer { at += n }
                return Array(raw[at..<(at + n)])
            }
            guard try bytes(8) == Array("GEOREC1\n".utf8) else { throw FormatError(description: "\(url.lastPathComponent): not a recording") }
            while at < raw.count {
                switch try u8() {
                case UInt8(ascii: "G"):
                    let id = try u32()
                    geometries[id] = try bytes(Int(try u32()))
                case UInt8(ascii: "C"):
                    let name = String(decoding: try bytes(Int(try u8())), as: UTF8.self)
                    let ids = try (0..<Int(try u32())).map { _ in try u32() }
                    let numbers = try (0..<Int(try u8())).map { _ in try f64() }
                    calls.append(Call(name: name, geometries: ids, numbers: numbers))
                case let t:
                    throw FormatError(description: "\(url.lastPathComponent): record type \(t) at \(at - 1)")
                }
            }
        }
    }

    /// Every recording on disk, by name: each `.rec` file under the folder
    /// of recordings, named by its folder.
    static func files() -> [(name: String, url: URL)] {
        let root = TestPaths.recording
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "rec" }.sorted { $0.path < $1.path }.map { url in
            let folder = url.deletingLastPathComponent().standardizedFileURL.path
            let name = String(folder.dropFirst(root.standardizedFileURL.path.count + 1))
            return (name, url)
        }
    }

    /// Whether there are recordings to replay (they stay outside git).
    static var available: Bool { !files().isEmpty }

    /// Whether to replay the long recorded runs too (the overlays, the
    /// predicates, the buffer: tens of minutes in a debug build), which the
    /// tests do only with `TOPOLOGY_LONG_REPLAY=1` and the recordings there.
    static var longReplay: Bool { available && ProcessInfo.processInfo.environment["TOPOLOGY_LONG_REPLAY"] == "1" }

    /// Every recording on disk, read.
    static func load() throws -> [Recording] {
        try files().map { try Recording(url: $0.url, name: $0.name) }
    }
}
