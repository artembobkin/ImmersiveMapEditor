import Darwin
import Synchronization
import geos

/// The recording mode of `Geometry`: with the environment variable
/// `GEOMETRY_RECORD` set to a folder, every operation the build asks of GEOS
/// is written there with its inputs, so the port of GEOS to Swift
/// (`Topology`) can be replayed against GEOS on real data
/// (Docs/PortingGoal.md, "Parity"). Without the variable it does nothing:
/// each operation only reads `Recorder.shared`, which is nil.
///
/// A process writes `geometry-<pid>.rec`, little-endian, in records after the
/// eight bytes `GEOREC1\n`:
///
/// - `G`: a geometry, written once, the first time it is an input. `u32` id,
///   `u32` byte count, then its WKB (GEOS's writer, extended flavour, three
///   dimensions when it has them), which keeps every coordinate exactly.
/// - `C`: a call. `u8` name length and the name (as the public API names it,
///   `Prepared.contains`, `STRtree.query`), `u32` geometry count and the ids of
///   its geometry inputs in order, `u8` number count and the numbers (`f64`),
///   the parameters in the order of the function's arguments. A prepared
///   geometry or a tree is a number: the id its `init` call gave it.
///
/// What is only read from a geometry (kind, coordinates, parts) and the
/// constructors are counted, not written: at exit `geometry-<pid>.counts`
/// lists every function's calls, written and counted, one `name count` a line.
final class Recorder: @unchecked Sendable {
    /// The recorder of this process, or nil when not recording.
    static let shared: Recorder? = {
        guard let dir = getenv("GEOMETRY_RECORD").map({ String(cString: $0) }), !dir.isEmpty else { return nil }
        return Recorder(folder: dir)
    }()

    struct State {
        var file: UnsafeMutablePointer<FILE>?
        var nextGeometry: UInt32 = 1
        var nextObject: UInt32 = 1
        var counts: [String: Int] = [:]
        var countsPath = ""
    }

    let state: Mutex<State>
    let writer: OpaquePointer

    init?(folder: String) {
        mkdir(folder, 0o755)
        let base = "\(folder)/geometry-\(getpid())"
        guard let file = fopen(base + ".rec", "wb") else { return nil }
        setvbuf(file, nil, _IOFBF, 1 << 20)
        fputs("GEOREC1\n", file)
        var s = State()
        s.file = file
        s.countsPath = base + ".counts"
        state = Mutex(s)
        writer = GEOSWKBWriter_create_r(ctx)!
        GEOSWKBWriter_setOutputDimension_r(ctx, writer, 3)
        GEOSWKBWriter_setByteOrder_r(ctx, writer, 1)
        atexit { Recorder.shared?.finish() }
    }

    /// Counts a call that is not written.
    func count(_ name: String) {
        state.withLock { $0.counts[name, default: 0] += 1 }
    }

    /// A new id for a prepared geometry or a tree.
    func object() -> UInt32 {
        state.withLock { s in
            defer { s.nextObject += 1 }
            return s.nextObject
        }
    }

    /// Writes a call with its geometry inputs and numbers.
    func call(_ name: String, _ geometries: [Geometry], _ numbers: [Double] = []) {
        state.withLock { s in
            guard let file = s.file else { return }
            s.counts[name, default: 0] += 1
            let ids = geometries.map { id(of: $0, &s, file) }
            put(UInt8(ascii: "C"), file)
            let utf8 = Array(name.utf8)
            put(UInt8(utf8.count), file)
            fwrite(utf8, 1, utf8.count, file)
            put(UInt32(ids.count), file)
            for i in ids { put(i, file) }
            put(UInt8(numbers.count), file)
            for n in numbers { put(n.bitPattern, file) }
        }
    }

    /// The id of a geometry, its WKB written the first time.
    func id(of g: Geometry, _ s: inout State, _ file: UnsafeMutablePointer<FILE>) -> UInt32 {
        if g.recordID != 0 { return g.recordID }
        let id = s.nextGeometry
        s.nextGeometry += 1
        g.recordID = id
        var size = 0
        guard let wkb = GEOSWKBWriter_write_r(ctx, writer, g.ptr, &size) else { return id }
        defer { GEOSFree_r(ctx, wkb) }
        put(UInt8(ascii: "G"), file)
        put(id, file)
        put(UInt32(size), file)
        fwrite(wkb, 1, size, file)
        return id
    }

    func put<T: FixedWidthInteger>(_ v: T, _ file: UnsafeMutablePointer<FILE>) {
        var le = v.littleEndian
        fwrite(&le, MemoryLayout<T>.size, 1, file)
    }

    /// Flushes the calls and writes the counts.
    func finish() {
        state.withLock { s in
            guard let file = s.file else { return }
            fclose(file)
            s.file = nil
            guard let out = fopen(s.countsPath, "w") else { return }
            for (name, n) in s.counts.sorted(by: { $0.key < $1.key }) { fputs("\(name) \(n)\n", out) }
            fclose(out)
        }
    }
}
