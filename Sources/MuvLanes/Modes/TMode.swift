/// muv-osm's `TMode` (`tmode.rs`, `hierarchy.rs`): the modes of transport of
/// OSM's access keys, in declaration order (which is also their order in a
/// `TModes` map), their OSM names, the hierarchy (`motorcar` under
/// `double_tracked_motor_vehicle` under `motor_vehicle` ...), and how a
/// tag's subtags are read as modes.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public enum TMode: Int, SimpleEnum, Sendable {
    case all, landBased, foot
    case animal, dog, horse
    case ski, skiNordic, skiAlpine, skiTelemark, inlineSkates
    case vehicle, bicycle, electricBicycle, mtb, cargoBike, kickScooter
    case stroller
    case carriage, cycleRickshaw, handCart, trailer, caravan
    case motorVehicle, motorcycle, moped, speedPedelec, mofa, smallElectricVehicle
    case doubleTrackedMotorVehicle, motorcar, motorhome, touristBus, coach, goods, hgv, hhvArticulated, bDouble,
         agricultural, autoRickshaw, nev, golfCart, atv, ohv, snowmobile
    case psv, taxi, minibus, shareTaxi
    case bus, schoolBus, truckBus
    case hov, carpool, carSharing, emergency, disabled
    case hazmat, hazmatWater, hazmatExplosive, hazmatE, hazmatD, hazmatC, hazmatB, hazmatA
    case railBased, train, monorail, funicular, lightRail, subway, tram
    case waterBased, swimming, iceSkates
    case boat, motorboat, sailboat, canoe
    case fishingVessel
    case ship, passenger, cargo, bulk, tanker, container, imdg, isps
    case airBased, aeroplane

    public static let rustNames = [
        "All", "LandBased", "Foot",
        "Animal", "Dog", "Horse",
        "Ski", "SkiNordic", "SkiAlpine", "SkiTelemark", "InlineSkates",
        "Vehicle", "Bicycle", "ElectricBicycle", "Mtb", "CargoBike", "KickScooter",
        "Stroller",
        "Carriage", "CycleRickshaw", "HandCart", "Trailer", "Caravan",
        "MotorVehicle", "Motorcycle", "Moped", "SpeedPedelec", "Mofa", "SmallElectricVehicle",
        "DoubleTrackedMotorVehicle", "Motorcar", "Motorhome", "TouristBus", "Coach", "Goods", "Hgv", "HhvArticulated",
        "BDouble", "Agricultural", "AutoRickshaw", "Nev", "GolfCart", "Atv", "Ohv", "Snowmobile",
        "Psv", "Taxi", "Minibus", "ShareTaxi",
        "Bus", "SchoolBus", "TruckBus",
        "Hov", "Carpool", "CarSharing", "Emergency", "Disabled",
        "Hazmat", "HazmatWater", "HazmatExplosive", "HazmatE", "HazmatD", "HazmatC", "HazmatB", "HazmatA",
        "RailBased", "Train", "Monorail", "Funicular", "LightRail", "Subway", "Tram",
        "WaterBased", "Swimming", "IceSkates",
        "Boat", "Motorboat", "Sailboat", "Canoe",
        "FishingVessel",
        "Ship", "Passenger", "Cargo", "Bulk", "Tanker", "Container", "Imdg", "Isps",
        "AirBased", "Aeroplane",
    ]

    public static let osmNames = makeOsmNames([
        .all: [], .landBased: [], .skiNordic: [], .skiAlpine: [], .skiTelemark: [],
        .autoRickshaw: ["auto_rickshaw", "tricycle"],
        .hazmatWater: [], .hazmatExplosive: [], .hazmatE: [], .hazmatD: [], .hazmatC: [], .hazmatB: [], .hazmatA: [],
        .railBased: [], .train: [], .monorail: [], .funicular: [], .lightRail: [], .subway: [], .tram: [],
        .waterBased: [], .airBased: [], .aeroplane: [],
    ])

    /// `TMode::from_osm_ski_str`.
    static func fromOsmSkiStr(_ s: String) -> TMode? {
        switch s {
        case "nordic": return .skiNordic
        case "alpine": return .skiAlpine
        case "telemark": return .skiTelemark
        default: return nil
        }
    }

    /// `TMode::from_osm_hazmat_str`.
    static func fromOsmHazmatStr(_ s: String) -> TMode? {
        switch s {
        case "water": return .hazmatWater
        case "explosive": return .hazmatExplosive
        case "A": return .hazmatA
        case "B": return .hazmatB
        case "C": return .hazmatC
        case "D": return .hazmatD
        case "E": return .hazmatE
        default: return nil
        }
    }

    /// `TMode::hierarchy_parent`: the mode this one is the direct child of.
    public var hierarchyParent: TMode? {
        switch self {
        case .all: return nil
        case .landBased, .railBased, .waterBased, .airBased: return .all
        case .foot, .animal, .ski, .inlineSkates, .vehicle: return .landBased
        case .dog, .horse: return .animal
        case .skiNordic, .skiAlpine, .skiTelemark: return .ski
        case .bicycle, .kickScooter, .stroller, .carriage, .cycleRickshaw, .handCart, .trailer, .motorVehicle: return .vehicle
        case .electricBicycle, .mtb, .cargoBike: return .bicycle
        case .caravan: return .trailer
        case .motorcycle, .moped, .mofa, .smallElectricVehicle, .doubleTrackedMotorVehicle, .psv, .hov, .carSharing,
             .emergency, .disabled, .hazmat:
            return .motorVehicle
        case .speedPedelec: return .moped
        case .motorcar, .motorhome, .touristBus, .goods, .hgv, .agricultural, .autoRickshaw, .nev, .golfCart, .atv, .ohv,
             .snowmobile:
            return .doubleTrackedMotorVehicle
        case .coach: return .touristBus
        case .hhvArticulated, .bDouble: return .hgv
        case .bus, .taxi, .minibus, .shareTaxi: return .psv
        case .schoolBus, .truckBus: return .bus
        case .carpool: return .hov
        case .hazmatWater, .hazmatExplosive, .hazmatE: return .hazmat
        case .hazmatD: return .hazmatE
        case .hazmatC: return .hazmatD
        case .hazmatB: return .hazmatC
        case .hazmatA: return .hazmatB
        case .train, .monorail, .funicular, .lightRail, .subway, .tram: return .railBased
        case .swimming, .iceSkates, .boat, .fishingVessel, .ship: return .waterBased
        case .motorboat, .sailboat, .canoe: return .boat
        case .passenger, .cargo, .isps: return .ship
        case .bulk, .tanker, .container, .imdg: return .cargo
        case .aeroplane: return .airBased
        }
    }

    /// `TMode::iter_hierarchy`: this mode, then its parents up to `All`.
    public func iterHierarchy() -> [TMode] {
        var res: [TMode] = []
        var next: TMode? = self
        while let m = next {
            res.append(m)
            next = m.hierarchyParent
        }
        return res
    }

    /// `TMode::iter_tags`: the subtags that name a mode, each followed by
    /// the inner subtags of `ski` and `hazmat` that name one.
    static func iterTags<T: Taglike>(_ tags: T) -> [(TMode, T)] {
        var res: [(TMode, T)] = []
        for (key, tag) in tags.iterSubtags() {
            guard let mode = fromOsmStr(key) else { continue }
            res.append((mode, tag))
            switch mode {
            case .ski:
                for (k, t) in tag.iterSubtags() { if let m = fromOsmSkiStr(k) { res.append((m, t)) } }
            case .hazmat:
                for (k, t) in tag.iterSubtags() { if let m = fromOsmHazmatStr(k) { res.append((m, t)) } }
            default:
                break
            }
        }
        return res
    }

    /// `TMode::iter_tags_with_all`: `All` for the tag itself, then `iter_tags`.
    static func iterTagsWithAll<T: Taglike>(_ tags: T) -> [(TMode, T)] {
        [(.all, tags)] + iterTags(tags)
    }
}
