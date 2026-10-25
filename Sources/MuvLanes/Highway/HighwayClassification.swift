/// muv-osm's `HighwayClassification` (`lanes/highway/class.rs`) and the
/// default access of each class (`lanes/highway/access.rs`), with the
/// regional rules of cycle streets.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// The access a lane starts from.
typealias Access = TModes<Conditional<AccessLevel>>

private func access(_ pairs: [(TMode, AccessLevel)]) -> Access {
    TModes(pairs.map { ($0.0, Conditional($0.1)) })
}

enum HighwayClassification: Equatable {
    /// The flag: a `_link`.
    case motorway(Bool), trunk(Bool), primary(Bool), secondary(Bool), tertiary(Bool)
    case unclassified, residential
    case livingStreet, service, pedestrian, track, busGuideway, escape, raceway, road, busway
    case footway, bridleway, steps, corridor, path, viaFerrata, cycleway, platform
    case shoulder

    /// `FromOsmStr`: exact names, case matters.
    static func fromOsmStr(_ s: String) -> HighwayClassification? {
        switch s {
        case "motorway": return .motorway(false)
        case "motorway_link": return .motorway(true)
        case "trunk": return .trunk(false)
        case "trunk_link": return .trunk(true)
        case "primary": return .primary(false)
        case "primary_link": return .primary(true)
        case "secondary": return .secondary(false)
        case "secondary_link": return .secondary(true)
        case "tertiary": return .tertiary(false)
        case "tertiary_link": return .tertiary(true)
        case "unclassified": return .unclassified
        case "residential": return .residential
        case "living_street": return .livingStreet
        case "service": return .service
        case "pedestrian": return .pedestrian
        case "track": return .track
        case "bus_guideway": return .busGuideway
        case "escape": return .escape
        case "raceway": return .raceway
        case "road": return .road
        case "busway": return .busway
        case "footway": return .footway
        case "bridleway": return .bridleway
        case "steps": return .steps
        case "corridor": return .corridor
        case "path": return .path
        case "via_ferrata": return .viaFerrata
        case "cycleway": return .cycleway
        case "platform": return .platform
        default: return nil
        }
    }

    /// `HighwayClassification::default_access`.
    func defaultAccess<T: Taglike>(_ regions: [String], _ tags: T, _ motorroad: Bool) -> Access {
        if motorroad { return HighwayAccess.motorway() }
        let bicycleRoad = tags.getValue("bicycle_road") == "yes"
        if bicycleRoad || tags.getValue("cyclestreet") == "yes" {
            return HighwayAccess.cyclestreet(regions, bicycleRoad)
        }
        switch self {
        case .motorway: return HighwayAccess.motorway()
        case .trunk, .primary, .secondary, .tertiary, .unclassified, .residential, .livingStreet, .service, .road, .track:
            return HighwayAccess.highway()
        case .path: return access([(.all, .no), (.foot, .yes), (.horse, .yes), (.bicycle, .yes)])
        case .bridleway: return access([(.all, .no), (.horse, .designated)])
        case .cycleway: return access([(.all, .no), (.bicycle, .designated)])
        case .pedestrian, .footway, .corridor, .viaFerrata, .platform: return access([(.all, .no), (.foot, .designated)])
        case .steps: return HighwayAccess.steps(tags)
        case .busway: return access([(.all, .no), (.bus, .designated), (.emergency, .yes)])
        case .busGuideway: return access([(.all, .no), (.bus, .designated)])
        case .shoulder: return access([(.all, .no), (.foot, .yes)])
        case .escape: return access([(.all, .no), (.landBased, .escape)])
        case .raceway: return access([(.all, .no)])
        }
    }

    /// `HighwayClassification::default_speed`: the minimum and maximum
    /// speeds of the first region that has them.
    func defaultSpeed(_ regions: [String]) -> (DefaultSpeed, DefaultSpeed)? {
        let cls: String
        switch self {
        case .pedestrian: cls = "pedestrian"
        case .livingStreet: cls = "living_street"
        case .service: cls = "service"
        case .motorway: cls = "motorway"
        default: return nil
        }
        for r in regions { if let s = SpeedDefault.lookup(r, cls) { return s } }
        return nil
    }
}

/// `lanes/highway/access.rs`.
enum HighwayAccess {
    static func motorway() -> Access {
        access([(.all, .no), (.landBased, .yes), (.motorcar, .designated), (.motorcycle, .designated),
                (.goods, .designated), (.hgv, .designated), (.psv, .designated), (.moped, .no), (.horse, .no),
                (.bicycle, .no), (.foot, .no)])
    }

    static func highway() -> Access { access([(.all, .no), (.landBased, .yes)]) }

    static func steps<T: Taglike>(_ tags: T) -> Access {
        var a = access([(.all, .no), (.foot, .yes)])
        var rampWheelchair = false, rampStroller = false, rampBicycle = false
        if let ramp = tags.get("ramp") {
            if ramp.getValue("wheelchair") == "yes" {
                rampWheelchair = true
            } else if ramp.getValue("stroller") == "yes" {
                rampStroller = true
            } else if ["yes", "automatic"].contains(ramp.getValue("bicycle") ?? "") {
                rampBicycle = true
            } else if ["yes", "automatic"].contains(ramp.getValue("luggage") ?? "") {
            } else if ramp.value == "yes" {
                rampStroller = true
            }
        }
        if rampStroller || rampWheelchair { a.set(.stroller, Conditional(AccessLevel.yes)) }
        if rampBicycle || rampStroller || rampWheelchair { a.set(.bicycle, Conditional(AccessLevel.dismount)) }
        return a
    }

    static func cyclestreet(_ regions: [String], _ bicycleRoad: Bool) -> Access {
        var a = access([(.all, .no), (.landBased, .yes), (.bicycle, .designated)])
        if !regions.contains(where: { cyclestreetRegion($0, &a) }) && bicycleRoad {
            a.set(.vehicle, Conditional(AccessLevel.destination))
        }
        return a
    }

    private static func cyclestreetRegion(_ region: String, _ a: inout Access) -> Bool {
        func set(_ m: TMode, _ l: AccessLevel) { a.set(m, Conditional(l)) }
        switch region {
        case "AT":
            set(.vehicle, .destination)
            set(.psv, .yes)
            set(.emergency, .yes)
        case "BE":
            set(.mofa, .designated)
        case "CH", "ES", "FI", "FR", "LU", "NL", "RU", "SE", "US":
            break
        case "CZ":
            set(.vehicle, .no)
        case "DE":
            set(.vehicle, .no)
            set(.smallElectricVehicle, .yes)
        case "DK":
            set(.vehicle, .no)
            set(.mofa, .designated)
        case "EE":
            set(.landBased, .no)
            set(.foot, .yes)
            set(.mofa, .designated)
            set(.moped, .designated)
            set(.smallElectricVehicle, .designated)
        default:
            return false
        }
        return true
    }
}
