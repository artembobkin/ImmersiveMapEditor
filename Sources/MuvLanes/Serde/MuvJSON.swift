/// What serde makes of Muv's types, as `serde_json::to_value` holds it: a
/// tree of JSON values whose objects are maps (serde_json's `Value` sorts
/// them by key when written, its `preserve_order` feature being off).
/// osm2lanes writes each lane's `Lane` this way into the lane polygons.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public indirect enum MuvJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case uint(UInt64)
    case string(String)
    case array([MuvJSON])
    case object([String: MuvJSON])
}

/// A Muv type serde can write (`Serialize`, human readable).
public protocol MuvSerialize {
    func muvJSON() -> MuvJSON
}

extension Optional where Wrapped: MuvSerialize {
    /// `Option<T>`: null, or the value.
    func muvJSON() -> MuvJSON { map { $0.muvJSON() } ?? .null }
}

extension Array where Element: MuvSerialize {
    func muvJSON() -> MuvJSON { .array(map { $0.muvJSON() }) }
}

extension Bool: MuvSerialize {
    public func muvJSON() -> MuvJSON { .bool(self) }
}

extension String: MuvSerialize {
    public func muvJSON() -> MuvJSON { .string(self) }
}

extension UInt32: MuvSerialize {
    public func muvJSON() -> MuvJSON { .uint(UInt64(self)) }
}
