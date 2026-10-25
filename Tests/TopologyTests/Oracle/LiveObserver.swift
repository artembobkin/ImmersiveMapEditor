import Foundation
import Testing
import Geometry

/// The wrapper replay's live mode (`TOPOLOGY_FREEZE=1`), while GEOS is still
/// in the package: the walk runs on the old wrapper (`GEOSWrapper`) and every
/// result is written to the tape for the frozen replay.
func liveObserver(_ name: String, _ store: TapeStore, _ writes: Bool) -> ReplayObserver & Finishing {
    LiveObserver(name, store, writes: writes)
}

/// The walk of a recording on the old wrapper.
func liveReplay(_ r: Recording, fixed: Bool, limit: Int?, _ observer: ReplayObserver) {
    WrapperReplayTests.replay(GEOSWrapper.Geometry.self, r, fixed: fixed, limit: limit, observer)
}

/// The walk of the non-finite inputs on the old wrapper.
func liveNonFinite(_ observer: ReplayObserver) {
    WrapperReplayTests.nonFiniteWalk(GEOSWrapper.Geometry.self, observer)
}

final class LiveObserver: ReplayObserver, Finishing {
    let name: String
    let writes: Bool
    let tape: TapeWriter

    init(_ name: String, _ store: TapeStore, writes: Bool) {
        self.name = name
        self.writes = writes
        tape = TapeWriter(url: store.writeURL(name), limit: store.limit)
    }

    private func write(_ name: String, flags: UInt8, exact: [UInt8], value: [UInt8]?, limit: Int) {
        tape.tag(.observation)
        tape.rawString(name)
        tape.raw { s in
            s.u8(flags | (value != nil ? Tape.Tag.observationValue : 0))
            StoredBytes(exact, limit: limit).write(&s)
            if let value { StoredBytes(value, limit: limit).write(&s) }
        }
    }

    func geometry<G: WrapperGeometry>(_ name: String, _ what: @autoclosure () -> String, _ make: () -> G) {
        let a = make()
        let kind = a.kindCode, grids = a.grids, wkb = a.wkb
        var flags = Tape.Tag.observationGeometry
        var value: [UInt8]?
        if WrapperResult.hasZeroOrNaN(wkb) {
            value = WrapperResult.value(kind: kind, grids: grids, wkb: wkb)
            if (0..<10).contains(where: { _ in make().wkb != wkb }) { flags |= Tape.Tag.observationVaries }
        }
        write(name, flags: flags, exact: WrapperResult.exact(kind: kind, grids: grids, wkb: wkb), value: value, limit: tape.limit)
    }

    func same<T: ObservedValue>(_ name: String, _ what: @autoclosure () -> String, _ value: T) {
        write(name, flags: 0, exact: value.observedBytes, value: nil, limit: tape.limit)
    }

    func steer<T: ObservedValue & Equatable>(_ value: T) -> T {
        write("steer", flags: 0, exact: value.observedBytes, value: nil, limit: .max)
        return value
    }

    func unknown(_ name: String, _ what: String) {}

    func finish(sourceLocation: SourceLocation) {
        print("oracle \(name): \(tape.entries) results of the old wrapper\(writes ? "" : " (not written)")")
        guard writes else { return }
        do { try tape.close() } catch { Issue.record("\(name): the tape cannot be written: \(error)", sourceLocation: sourceLocation) }
    }
}

extension GEOSWrapper.Geometry: WrapperGeometry {
    typealias PreparedType = GEOSWrapper.Prepared
    typealias TreeType = GEOSWrapper.STRtree

    static func readWKB(_ wkb: [UInt8]) -> GEOSWrapper.Geometry { read(wkb: wkb) }
    var kindCode: Int32 { kind.rawValue }

    static func makePoint(_ p: P2) -> GEOSWrapper.Geometry { .point(p) }
    static func makeLineString(_ pts: [P2]) -> GEOSWrapper.Geometry { .lineString(pts) }
    static func makePolygon(_ shell: [P2], holes: [[P2]]) -> GEOSWrapper.Geometry { .polygon(shell, holes: holes) }
    static func makeCollection(_ parts: [GEOSWrapper.Geometry]) -> GEOSWrapper.Geometry { .collection(parts) }
    static func makeUnaryUnion(_ parts: [GEOSWrapper.Geometry]) -> GEOSWrapper.Geometry { .unaryUnion(parts) }
    static func makePolygonize(_ lines: [GEOSWrapper.Geometry]) -> GEOSWrapper.Geometry { .polygonize(lines) }

    func styledBuffer(_ d: Double, quadSegs: Int, cap: Int32, join: Int32, mitreLimit: Double) -> GEOSWrapper.Geometry {
        buffer(d, quadSegs: quadSegs, cap: Cap(rawValue: cap)!, join: Join(rawValue: join)!, mitreLimit: mitreLimit)
    }

    func styledOffsetCurve(_ d: Double, quadSegs: Int, join: Int32, mitreLimit: Double) -> GEOSWrapper.Geometry {
        offsetCurve(d, quadSegs: quadSegs, join: Join(rawValue: join)!, mitreLimit: mitreLimit)
    }
}

extension GEOSWrapper.Prepared: WrapperPrepared {
    typealias G = GEOSWrapper.Geometry
}

extension GEOSWrapper.STRtree: WrapperTree {
    typealias G = GEOSWrapper.Geometry
}
