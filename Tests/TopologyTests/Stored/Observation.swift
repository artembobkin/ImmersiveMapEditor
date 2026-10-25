import Foundation
import Testing
@testable import Geometry

/// A value the wrapper replay compares: its bytes on the tape. Numbers are
/// their bits, so equal bytes are equal bits.
protocol ObservedValue {
    func observe(_ s: inout ByteSink)
    static func decode(_ s: inout ByteSource) throws -> Self
}

extension Bool: ObservedValue {
    func observe(_ s: inout ByteSink) { s.u8(self ? 1 : 0) }
    static func decode(_ s: inout ByteSource) throws -> Bool { try s.u8() != 0 }
}

extension Int: ObservedValue {
    func observe(_ s: inout ByteSink) { s.zigzag(self) }
    static func decode(_ s: inout ByteSource) throws -> Int { try s.zigzag() }
}

extension UInt8: ObservedValue {
    func observe(_ s: inout ByteSink) { s.u8(self) }
    static func decode(_ s: inout ByteSource) throws -> UInt8 { try s.u8() }
}

extension UInt64: ObservedValue {
    func observe(_ s: inout ByteSink) { s.u64(self) }
    static func decode(_ s: inout ByteSource) throws -> UInt64 { try s.u64() }
}

extension String: ObservedValue {
    func observe(_ s: inout ByteSink) { s.data(Array(utf8)) }
    static func decode(_ s: inout ByteSource) throws -> String { String(decoding: try s.data(), as: UTF8.self) }
}

extension Optional: ObservedValue where Wrapped: ObservedValue {
    func observe(_ s: inout ByteSink) {
        if let v = self { s.u8(1); v.observe(&s) } else { s.u8(0) }
    }
    static func decode(_ s: inout ByteSource) throws -> Wrapped? { try s.u8() == 0 ? nil : try Wrapped.decode(&s) }
}

extension Array: ObservedValue where Element: ObservedValue {
    func observe(_ s: inout ByteSink) {
        s.varint(count)
        for v in self { v.observe(&s) }
    }
    static func decode(_ s: inout ByteSource) throws -> [Element] { try (0..<s.count()).map { _ in try Element.decode(&s) } }
}

extension ObservedValue {
    var observedBytes: [UInt8] {
        var s = ByteSink()
        observe(&s)
        return s.bytes
    }
}

/// A geometry result of the wrapper replay as compared: its kind, the
/// grids of its precision models and its WKB. Its value form makes every
/// zero `+0.0` and every NaN one NaN in the WKB, so two results have the
/// same value form when the old test's `equalByValue` held for them.
enum WrapperResult {
    static func exact(kind: Int32, grids: [Double], wkb: [UInt8]) -> [UInt8] {
        var s = ByteSink()
        s.zigzag(Int(kind))
        grids.map(\.bitPattern).observe(&s)
        s.data(wkb)
        return s.bytes
    }

    /// Whether the WKB has a zero or a NaN, where the value form differs.
    static func hasZeroOrNaN(_ wkb: [UInt8]) -> Bool { split(wkb).values.contains { $0 == 0 || $0.isNaN } }

    static func value(kind: Int32, grids: [Double], wkb: [UInt8]) -> [UInt8] {
        let (structure, values) = split(wkb)
        var canonical = ByteSink()
        for v in values { canonical.f64(v == 0 ? 0 : (v.isNaN ? .nan : v)) }
        var s = ByteSink()
        s.zigzag(Int(kind))
        grids.map { ($0 == 0 ? 0.0 : $0).bitPattern }.observe(&s)
        s.data(structure)
        s.data(canonical.bytes)
        return s.bytes
    }

    /// The structure and the doubles of a WKB apart.
    static func split(_ wkb: [UInt8]) -> (structure: [UInt8], values: [Double]) {
        var structure: [UInt8] = [], values: [Double] = []
        var at = 0
        func u32() -> UInt32 {
            var v: UInt32 = 0
            for i in 0..<4 { v |= UInt32(wkb[at + i]) << (8 * i) }
            structure += wkb[at..<(at + 4)]
            at += 4
            return v
        }
        func f64() {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(wkb[at + i]) << (8 * i) }
            values.append(Double(bitPattern: v))
            at += 8
        }
        func geometry() {
            structure.append(wkb[at])
            at += 1
            switch u32() & 0xFF {
            case 1: f64(); f64()
            case 2: for _ in 0..<u32() { f64(); f64() }
            case 3: for _ in 0..<u32() { for _ in 0..<u32() { f64(); f64() } }
            default: for _ in 0..<u32() { geometry() }
            }
        }
        if !wkb.isEmpty { geometry() }
        return (structure, values)
    }
}

/// What the wrapper replay observes along its walk, in order: geometry
/// results and plain values, each under the name it is tallied by, and the
/// values of the old side that steer the walk. The live observer records
/// the old wrapper's (GEOS's), the frozen one compares the new `Geometry`
/// with them.
protocol ReplayObserver: AnyObject {
    /// A geometry result; `make` is run again by the live observer to see
    /// whether GEOS varies (its snap rounding shuffles at random).
    func geometry<G: WrapperGeometry>(_ name: String, _ what: @autoclosure () -> String, _ make: () -> G)
    func same<T: ObservedValue>(_ name: String, _ what: @autoclosure () -> String, _ value: T)
    /// A value of the old side that the walk goes on with (a parameter, a
    /// branch): the old wrapper's, live or stored.
    func steer<T: ObservedValue & Equatable>(_ value: T) -> T
    /// A call the walk does not know.
    func unknown(_ name: String, _ what: String)
}

/// The tallies of one replay, by function.
final class WrapperTallies {
    var byName: [String: ParityTally] = [:]
    var zeroSigns: [String: Int] = [:]
    let label: String

    init(_ label: String) { self.label = label }

    func check(_ name: String, _ equal: Bool, _ detail: @autoclosure () -> String) {
        var t = byName[name] ?? ParityTally("\(label) \(name)")
        t.check(equal, detail())
        byName[name] = t
    }

    func report() {
        for name in byName.keys.sorted() {
            byName[name]!.report()
            if let z = zeroSigns[name] { print("parity \(label) \(name): \(z) equal but for the sign of zeros, GEOS's own randomness") }
        }
    }
}

extension Tape.Tag {
    /// The flags of an observation: a geometry, GEOS varies, a value form follows.
    static let observationGeometry: UInt8 = 1, observationVaries: UInt8 = 2, observationValue: UInt8 = 4
}

/// The frozen observer: the new `Geometry`'s results against the stored ones.
final class FrozenObserver: ReplayObserver {
    let name: String
    let tallies: WrapperTallies
    /// A prefix of the tape is read (the first calls of a recording).
    let partial: Bool
    private let tape: TapeReader?
    private var problem: String?

    init(_ name: String, _ store: TapeStore, _ tallies: WrapperTallies, partial: Bool = false) {
        self.name = name
        self.tallies = tallies
        self.partial = partial
        let url = store.url(name)
        do { tape = try TapeReader(url: url) } catch {
            tape = nil
            problem = "no stored answers of the old wrapper for \(name) at \(url.path): \(error)"
        }
    }

    struct Stored {
        var flags: UInt8
        var exact: StoredBytes
        var value: StoredBytes?
    }

    private func next(_ observed: String) -> Stored? {
        guard let tape, problem == nil else { return nil }
        do {
            guard try tape.tag() == .observation else { throw TapeError("not an observation") }
            let stored = try tape.rawString()
            guard stored == observed else { throw TapeError("\(observed) asked, \(stored) stored") }
            let flags = try tape.raw { try $0.u8() }
            let exact = try tape.raw { try StoredBytes.read(&$0) }
            let value = flags & Tape.Tag.observationValue != 0 ? try tape.raw { try StoredBytes.read(&$0) } : nil
            return Stored(flags: flags, exact: exact, value: value)
        } catch {
            problem = "\(name): the tape is out of step at entry \(tape.entries): \(error)"
            return nil
        }
    }

    func geometry<G: WrapperGeometry>(_ name: String, _ what: @autoclosure () -> String, _ make: () -> G) {
        let b = make()
        let kind = b.kindCode, grids = b.grids, wkb = b.wkb
        guard let s = next(name) else { return tallies.check(name, false, "\(what()): no stored answer") }
        if s.exact.matches(WrapperResult.exact(kind: kind, grids: grids, wkb: wkb)) { return tallies.check(name, true, "") }
        // Equal by value (the sign of zeros, NaNs): accepted where GEOS itself
        // varied. GEOS's value form is stored only where it has a zero or a NaN.
        if let theirs = s.value, s.flags & Tape.Tag.observationVaries != 0,
           theirs.matches(WrapperResult.value(kind: kind, grids: grids, wkb: wkb)) {
            tallies.zeroSigns[name, default: 0] += 1
            return tallies.check(name, true, "")
        }
        tallies.check(name, false, "\(what()): GEOS \(s.exact.whole.map { "\($0.count) bytes" } ?? "(a digest)") port \(b.kindCode) \(grids) \(b)")
    }

    func same<T: ObservedValue>(_ name: String, _ what: @autoclosure () -> String, _ value: T) {
        guard let s = next(name) else { return tallies.check(name, false, "\(what()): no stored answer") }
        let mine = value.observedBytes
        let theirs: String = s.exact.whole.flatMap { b -> String? in
            var src = ByteSource(b)
            return (try? T.decode(&src)).map { "\($0)" }
        } ?? "(a digest)"
        tallies.check(name, s.exact.matches(mine), "\(what()): GEOS \(theirs) port \(value)")
    }

    func steer<T: ObservedValue & Equatable>(_ value: T) -> T {
        guard let s = next("steer"), let b = s.exact.whole else { return value }
        var src = ByteSource(b)
        return (try? T.decode(&src)) ?? value
    }

    func unknown(_ name: String, _ what: String) { tallies.check(name, false, "not replayed: \(name)") }

    func finish(sourceLocation: SourceLocation = #_sourceLocation) {
        if problem == nil, let tape, !partial {
            do { try tape.close() } catch { problem = "\(name): \(error)" }
        }
        if let problem { Issue.record(Comment(rawValue: problem), sourceLocation: sourceLocation) }
    }
}

/// Makes the observer of a replay: frozen, or live while GEOS was in the
/// package (`TOPOLOGY_FREEZE=1`).
enum Observers {
    static func make(_ name: String, _ store: TapeStore, _ tallies: WrapperTallies, partial: Bool = false, writes: Bool = true) -> ReplayObserver & Finishing {
        if Oracles.freezing { return liveObserver(name, store, writes && !partial) }
        return FrozenObserver(name, store, tallies, partial: partial)
    }
}

protocol Finishing {
    func finish(sourceLocation: SourceLocation)
}

extension FrozenObserver: Finishing {}
