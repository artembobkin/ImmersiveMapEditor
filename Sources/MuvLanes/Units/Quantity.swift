/// muv-osm's `Quantity<U>` (`units/unit.rs`): a `Number` with its unit, as
/// written in OSM (`50`, `20.5 km`, `12'`), kept in that unit, compared and
/// added through conversions. serde writes `{"unit": ..., "value": ...}`.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `PartialUnit`: a unit that may convert to others of its kind.
public protocol PartialUnit: Equatable, Sendable, MuvSerialize {
    /// `partial_default`: the unit of a bare number.
    static var partialDefault: Self? { get }
    /// `from_special_quantity_osm_str`: forms that are not a number and a unit.
    static func fromSpecialQuantityOsmStr(_ s: String) -> Quantity<Self>?
    /// `FromOsmStr` of the unit's name.
    static func unitFromOsmStr(_ s: String) -> Self?
    /// `partial_convert`: `value` in `self` as a value in `to`.
    func partialConvert(to: Self, value: Number) -> Number?
}

/// `Unit`: a unit that always converts.
public protocol FullUnit: PartialUnit {
    func convert(to: Self, value: Number) -> Number
}

extension PartialUnit {
    public static func fromSpecialQuantityOsmStr(_ s: String) -> Quantity<Self>? { nil }
}

public struct Quantity<U: PartialUnit>: Sendable, MuvSerialize {
    public var value: Number
    public var unit: U

    init(_ value: Number, _ unit: U) {
        self.value = value
        self.unit = unit
    }

    public func muvJSON() -> MuvJSON { .object(["value": value.muvJSON(), "unit": unit.muvJSON()]) }

    /// `FromOsmStr for Quantity<U>`: a bare number in the default unit.
    static func fromOsmStr(_ s: String) -> Quantity? {
        fromOsmStrWithUnitFn(s) { U.partialDefault }
    }

    /// `Quantity::from_osm_str_with_unit`.
    static func fromOsmStrWithUnit(_ s: String, _ unit: U) -> Quantity? {
        fromOsmStrWithUnitFn(s) { unit }
    }

    static func fromOsmStrWithUnitFn(_ s: String, _ unitFn: () -> U?) -> Quantity? {
        fromOsmStrWithUnitFnBase(s, unitFn) ?? U.fromSpecialQuantityOsmStr(s)
    }

    static func fromOsmStrWithUnitFnBase(_ s: String, _ unitFn: () -> U?) -> Quantity? {
        guard let (value, rest) = Number.parseStart(s) else { return nil }
        let unitStr = rest.rustTrimStart()
        guard let unit = unitStr.isEmpty ? unitFn() : U.unitFromOsmStr(unitStr) else { return nil }
        return Quantity(value, unit)
    }

    /// `PartialEq for Quantity`: the same unit and value, or `self`
    /// converted to the other's unit equal to its value.
    public static func == (a: Quantity, b: Quantity) -> Bool {
        if a.unit == b.unit { return a.value == b.value }
        return a.unit.partialConvert(to: b.unit, value: a.value) == b.value
    }

    /// `PartialOrd for Quantity`, as Muv writes it: in another unit, the
    /// other's value converted from `self`'s unit, against itself.
    static func partialCompare(_ a: Quantity, _ b: Quantity) -> Int? {
        if a.unit == b.unit { return Number.cmp(a.value, b.value) }
        guard let c = a.unit.partialConvert(to: b.unit, value: b.value) else { return nil }
        return Number.cmp(c, b.value)
    }
}

extension Quantity: Equatable {}

extension Quantity where U: FullUnit {
    /// `Quantity::to`.
    public func to(_ other: U) -> Quantity { Quantity(unit.convert(to: other, value: value), other) }

    /// `Sub<&Self>`: the other converted into this unit.
    static func - (a: Quantity, b: Quantity) -> Quantity {
        Quantity(a.value - b.unit.convert(to: a.unit, value: b.value), a.unit)
    }

    static func * (a: Quantity, n: Number) -> Quantity { Quantity(a.value * n, a.unit) }

    static func / (a: Quantity, n: Number) -> Quantity { Quantity(a.value / n, a.unit) }
}
