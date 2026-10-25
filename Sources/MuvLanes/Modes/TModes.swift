/// muv-osm's `TModes<T>`: a value per mode of transport, a `BTreeMap` keyed
/// by `TMode` (so iterated in the modes' declaration order), read through
/// the hierarchy (`get(Motorcar)` falls back to `Vehicle`'s value).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public struct TModes<T> {
    /// The entries, sorted by mode.
    public private(set) var entries: [(TMode, T)] = []

    public init() {}

    /// `TModes::from([(mode, value), ...])`: later pairs replace earlier ones.
    init(_ pairs: [(TMode, T)]) {
        for (m, v) in pairs { set(m, v) }
    }

    /// `TModes::all(value)`.
    static func all(_ value: T) -> TModes<T> { TModes([(.all, value)]) }

    private func position(_ mode: TMode) -> (found: Bool, at: Int) {
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].0.rawValue < mode.rawValue { lo = mid + 1 } else { hi = mid }
        }
        return (lo < entries.count && entries[lo].0 == mode, lo)
    }

    /// `TModes::set`: the old value, if there was one.
    @discardableResult
    mutating func set(_ mode: TMode, _ value: T) -> T? {
        let (found, at) = position(mode)
        if found {
            let old = entries[at].1
            entries[at].1 = value
            return old
        }
        entries.insert((mode, value), at: at)
        return nil
    }

    /// `TModes::get_raw`: this exact mode only.
    public func getRaw(_ mode: TMode) -> T? {
        let (found, at) = position(mode)
        return found ? entries[at].1 : nil
    }

    /// `TModes::get`: the value of the closest mode up the hierarchy.
    public func get(_ mode: TMode) -> T? {
        for m in mode.iterHierarchy() { if let v = getRaw(m) { return v } }
        return nil
    }

    /// The mode `get` would read, for `get_mut`.
    func found(_ mode: TMode) -> TMode? { mode.iterHierarchy().first { getRaw($0) != nil } }

    /// Changes the value of an exact mode in place, if present.
    mutating func modifyRaw(_ mode: TMode, _ f: (inout T) -> Void) {
        let (found, at) = position(mode)
        if found { f(&entries[at].1) }
    }

    /// `entry(mode).or_default()` then a change in place.
    mutating func modifyOrInsert(_ mode: TMode, _ initial: @autoclosure () -> T, _ f: (inout T) -> Void) {
        let (found, at) = position(mode)
        if !found { entries.insert((mode, initial()), at: at) }
        f(&entries[at].1)
    }

    /// Removes a mode's entry.
    mutating func remove(_ mode: TMode) {
        let (found, at) = position(mode)
        if found { entries.remove(at: at) }
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// `TModes::map`.
    func map<R>(_ f: (TMode, T) -> R?) -> TModes<R> {
        var res = TModes<R>()
        res.entries = entries.compactMap { m, v in f(m, v).map { (m, $0) } }
        return res
    }

    /// Every value changed in place, in mode order (`iter_mut`).
    mutating func modifyEach(_ f: (TMode, inout T) -> Void) {
        for i in entries.indices { f(entries[i].0, &entries[i].1) }
    }

    /// `TModes::zip`: for each mode of `self` then of `other`, in that
    /// order, the first time it is met, `f` of the two values read through
    /// the hierarchy.
    func zip<O, R>(_ other: TModes<O>, _ f: (T?, O?) -> R?) -> TModes<R> {
        var res = TModes<R>()
        for mode in entries.map(\.0) + other.entries.map(\.0) where res.getRaw(mode) == nil {
            if let v = f(get(mode), other.get(mode)) { res.set(mode, v) }
        }
        return res
    }
}

extension TModes: Equatable where T: Equatable {
    public static func == (a: TModes<T>, b: TModes<T>) -> Bool {
        a.entries.count == b.entries.count && Swift.zip(a.entries, b.entries).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

extension TModes: MuvSerialize where T: MuvSerialize {
    /// A map from the mode's Rust name.
    public func muvJSON() -> MuvJSON {
        var map: [String: MuvJSON] = [:]
        for (m, v) in entries { map[m.rustName] = v.muvJSON() }
        return .object(map)
    }
}

extension TModes: Sendable where T: Sendable {}
