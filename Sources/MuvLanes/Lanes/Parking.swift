/// muv-osm's parking lanes (`lanes/parking.rs`): read from `parking:<side>=*`
/// and its subtags, or from the older `parking:lane:<side>=*` scheme with
/// `parking:condition:<side>=*`, where the lane is (on the street, on the
/// kerb, in bays), its orientation, capacity, zone and limits.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `ParkingPosition`: where the parked vehicles stand. Not written.
enum ParkingPosition: Int, CaseIterable {
    case lane, streetSide, layBy, onKerb, halfOnKerb, shoulder, yes

    private static let names = OsmNames(
        [(ParkingPosition.lane, "Lane"), (.streetSide, "StreetSide"), (.layBy, "LayBy"), (.onKerb, "OnKerb"),
         (.halfOnKerb, "HalfOnKerb"), (.shoulder, "Shoulder"), (.yes, "Yes")],
        aliases: [.lane: ["lane", "on_street", "on_lane"]])

    static func fromOsmStr(_ s: String) -> ParkingPosition? { names.parse(s) }

    var bays: Bool { self == .streetSide || self == .layBy }
    var kerb: Bool { self == .onKerb || self == .halfOnKerb }
}

public enum ParkingOrientation: Int, SimpleEnum, Sendable {
    case parallel, diagonal, perpendicular

    public static let rustNames = ["Parallel", "Diagonal", "Perpendicular"]
    public static let osmNames = makeOsmNames()
}

public enum ParkingDirection: Int, SimpleEnum, Sendable {
    case backIn, headIn

    public static let rustNames = ["BackIn", "HeadIn"]
    public static let osmNames = makeOsmNames()
}

public enum ParkingRestriction: Int, SimpleEnum, Sendable {
    case noParking, noStanding, noStopping, onlyLoading, onlyCharging

    public static let rustNames = ["NoParking", "NoStanding", "NoStopping", "OnlyLoading", "OnlyCharging"]
    public static let osmNames = makeOsmNames([.onlyLoading: ["loading_only", "loading", "loading_zone"],
                                        .onlyCharging: ["charging_only"]])
}

/// `CapacityValue`: serde's untagged enum writes `Yes` as null.
public enum CapacityValue: Equatable, Sendable, MuvSerialize {
    case yes
    case exact(UInt32)

    static func fromOsmStr(_ s: String) -> CapacityValue? {
        switch s {
        case "yes": return .yes
        case "no": return .exact(0)
        default: return rustParseU32(s).map { .exact($0) }
        }
    }

    public func muvJSON() -> MuvJSON {
        switch self {
        case .yes: return .null
        case .exact(let n): return .uint(UInt64(n))
        }
    }
}

/// `Capacity`: per mode, flattened by serde beside the special spaces.
public struct Capacity: Equatable, Sendable, MuvSerialize {
    public var modes: TModes<CapacityValue>
    public var women: CapacityValue?
    public var parent: CapacityValue?
    public var charging: CapacityValue?

    /// `Capacity::parse_osm`.
    static func parseOsm<T: Taglike>(_ tags: T) -> Capacity {
        var modes = TModes<CapacityValue>.all(.exact(0))
        for (mode, tag) in TMode.iterTagsWithAll(tags) {
            if let v = tag.value.flatMap(CapacityValue.fromOsmStr) { modes.set(mode, v) }
        }
        return Capacity(modes: modes, women: tags.getValue("women").flatMap(CapacityValue.fromOsmStr),
                        parent: tags.getValue("parent").flatMap(CapacityValue.fromOsmStr),
                        charging: tags.getValue("charging").flatMap(CapacityValue.fromOsmStr))
    }

    public func muvJSON() -> MuvJSON {
        guard case .object(var map) = modes.muvJSON() else { fatalError("unreachable") }
        map["women"] = women.muvJSON()
        map["parent"] = parent.muvJSON()
        map["charging"] = charging.muvJSON()
        return .object(map)
    }
}

public struct ParkingLane: Equatable, Sendable, MuvSerialize {
    public var access: TModes<Conditional<AccessLevel>>
    public var restriction = TModes<Conditional<ParkingRestriction>>()
    /// Bays beside the roadway, which could not easily become a travel lane.
    public var bays: Bool?
    public var orientation: ParkingOrientation?
    public var direction: ParkingDirection?
    public var markings: Bool?
    public var capacity: Capacity?
    /// Local parking zones (`A`, `II`, `23`).
    public var zone: [String] = []
    public var maxstay = TModes<Conditional<Quantity<Duration>>>()

    public func muvJSON() -> MuvJSON {
        var map: [String: MuvJSON] = [
            "bays": bays.muvJSON(), "orientation": orientation.muvJSON(), "direction": direction.muvJSON(),
            "markings": markings.muvJSON(), "capacity": capacity.muvJSON(), "zone": zone.muvJSON(),
        ]
        if !access.isEmpty { map["access"] = access.muvJSON() }
        if !restriction.isEmpty { map["restriction"] = restriction.muvJSON() }
        if !maxstay.isEmpty { map["maxstay"] = maxstay.muvJSON() }
        return .object(map)
    }
}

/// The access of an ordinary parking lane: nothing, but everything land-based.
private func parkingAccess() -> TModes<Conditional<AccessLevel>> {
    TModes([(.all, Conditional(AccessLevel.no)), (.landBased, Conditional(AccessLevel.yes))])
}

/// `parse_legacy_access`: the access a `parking:condition` value means,
/// and its restrictions if any value was one.
private func parseLegacyAccess(_ tags: Tag) -> (Conditional<AccessLevel>?, Conditional<ParkingRestriction>?) {
    var restrictions = false
    let access = Conditional<AccessLevel>.parseWith(tags) { s -> AccessLevel? in
        switch s {
        case "free", "ticket", "disc": return .yes
        case "residents", "private": return .private
        case "customers": return .customers
        case "disabled", "no": return .no
        default:
            restrictions = restrictions || ParkingRestriction.fromOsmStr(s) != nil
            return nil
        }
    }
    let r = restrictions ? Conditional<ParkingRestriction>.fromOsm(tags, ParkingRestriction.fromOsmStr) : nil
    return (access, r)
}

/// `parse_legacy_lane`.
private func parseLegacyLane(_ tags: Tag, _ side: String) -> (Lane, ParkingPosition)? {
    guard let laneSubtag = tags.get("lane"),
          let lane = DoubleTag.maybeNew(laneSubtag.subtag(side), laneSubtag.get("both")),
          let orientationStr = lane.value else { return nil }
    let orientation: ParkingOrientation?
    let markings: Bool?
    switch orientationStr {
    case "yes": (orientation, markings) = (nil, nil)
    case "marked": (orientation, markings) = (nil, true)
    default:
        guard let o = ParkingOrientation.fromOsmStr(orientationStr) else { return nil }
        (orientation, markings) = (o, nil)
    }
    let position = lane.getValue(orientationStr).flatMap(ParkingPosition.fromOsmStr)

    var access = parkingAccess()
    var restriction = TModes<Conditional<ParkingRestriction>>()
    let condition = tags.get("condition")?.subtag(side)
    if let condition {
        let (conditionAccess, conditionRestriction) = parseLegacyAccess(condition)
        if let conditionAccess { access.set(.landBased, conditionAccess) }
        if let conditionRestriction { restriction.set(.all, conditionRestriction) }
        // Muv reads the modes from the parking tags themselves, not the condition.
        for (mode, t) in TMode.iterTags(tags) {
            let (a, r) = parseLegacyAccess(t)
            if let a { access.set(mode, a) }
            if let r { restriction.set(mode, r) }
        }
    }

    let variant = ParkingLane(
        access: access,
        restriction: restriction,
        bays: position.map(\.bays),
        orientation: orientation,
        direction: nil,
        markings: markings,
        capacity: lane.get("capacity").map { Capacity.parseOsm($0) },
        zone: lane.getValue("residents").map(seperatedValues) ?? [],
        maxstay: condition.flatMap { $0.get("maxstay") }
            .flatMap { Conditional<Quantity<Duration>>.fromOsm($0) { Quantity.fromOsmStr($0) } }
            .map { TModes.all($0) } ?? TModes())
    return (Lane(variant), position ?? .yes)
}

/// `parse_lane`.
private func parseLane(_ tags: Tag, _ side: String) -> (Lane, ParkingPosition)? {
    guard let t = DoubleTag.maybeNew(tags.subtag(side), tags.get("both")),
          let position = t.value.flatMap(ParkingPosition.fromOsmStr) else { return nil }
    var parking = ParkingLane(
        access: parkingAccess(),
        bays: position.bays,
        orientation: t.getValue("orientation").flatMap(ParkingOrientation.fromOsmStr),
        direction: t.getValue("direction").flatMap(ParkingDirection.fromOsmStr),
        markings: t.getValue("markings").flatMap(boolFromOsmStr),
        capacity: t.get("capacity").map { Capacity.parseOsm($0) },
        zone: t.getValue("zone").map(seperatedValues) ?? [])
    var all = AllParser<DoubleTag>(direction: { $0 })
    all.access(t.get("access"), t, false, &parking.access)
    all.withParse(t.get("restriction"), &parking.restriction, ParkingRestriction.fromOsmStr)
    all.withParse(t.get("maxstay"), &parking.maxstay) { Quantity.fromOsmStr($0) }
    return (Lane(parking).addParse(t), position)
}

/// `parse_parking_lane`: the older scheme first.
func parseParkingLane(_ tags: Tag, _ side: String) -> (Lane, ParkingPosition)? {
    parseLegacyLane(tags, side) ?? parseLane(tags, side)
}
