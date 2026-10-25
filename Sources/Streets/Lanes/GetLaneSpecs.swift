/// osm2lanes's `get_lane_specs_ltr` (`osm2lanes/src/algorithm.rs`): a way's
/// lanes from its tags, read by Muv (the `MuvLanes` target) and turned into
/// osm2streets's lanes: the type of each lane from the modes allowed on it
/// in their order of importance, its direction, width and turns, a kerb
/// where Muv puts one, and every lane under construction when the way is.

import MuvLanes
import StreetGeom

/// The lanes osm2lanes reads, the default `LaneSpecSource`.
public struct MuvLaneSpecs: LaneSpecSource {
    public init() {}

    public func laneSpecsLTR(_ tags: Tags, _ config: MapConfig) -> [LaneSpec] { getLaneSpecsLTR(tags, config) }
}

/// `get_lane_specs_ltr`: purely from OSM tags, the lanes of a road segment.
public func getLaneSpecsLTR(_ tagsIn: Tags, _ cfg: MapConfig) -> [LaneSpec] {
    var tags = tagsIn
    if cfg.inferredSidewalks { inferSidewalkTags(&tags, cfg) }

    // Only the driving side is given in tests, so a country that drives on
    // that side stands in for it (its legal defaults are not checked).
    let country: String
    switch (cfg.countryCode, cfg.drivingSide) {
    case ("", .left): country = "GB"
    case ("", .right): country = "US"
    case (let c, _): country = c
    }

    let muvTags = MuvLanes.Tag(pairs: tags.inner())
    guard let lanes = MuvLanes.lanes(muvTags, [country]) else {
        fatalError("Muv read no lanes from \(tags.inner())")
    }
    let highwayTag = muvTags.subtag("highway")?.value ?? ""

    var specs: [LaneSpec] = []
    specs.reserveCapacity(lanes.lanes.count + 2)
    for (i, lane) in lanes.lanes.enumerated() {
        // Muv's `LaneIndex` is twice a lane's index.
        let index = UInt8(truncatingIfNeeded: i)
        let direction = trafficDirection(Int(index &* 2), Int(lanes.centreLine), cfg.drivingSide)

        // A kerb inside a lane goes to the lane's edge: the left one rounded
        // up, the right one down.
        if cfg.inferredKerbs
            && ((lanes.kerbLeft.map { (Int($0) + 1) / 2 == Int(index) } ?? false)
                || (lanes.kerbRight.map { $0 / 2 == index } ?? false)) {
            let lt = LaneType.buffer(.curb)
            specs.append(LaneSpec(lt: lt, dir: direction, width: LaneSpec.typicalLaneWidth(lt)))
        }
        specs.append(fromLane(lane, highwayTag, direction))
    }

    if lanes.lifecycle == .construction {
        for i in specs.indices { specs[i].lt = .construction }
    }
    return specs
}

/// `from_lane`.
private func fromLane(_ lane: MuvLanes.Lane, _ highwayTag: String, _ trafficDirection: Direction) -> LaneSpec {
    let (lt, dir, turns): (LaneType, Direction, TurnDirections)
    switch lane.variant {
    case .travel(let t): (lt, dir, turns) = travelLane(t, lane.isSidepath, trafficDirection)
    case .parking(let p): (lt, dir, turns) = parkingLane(p, trafficDirection)
    }
    let width = lane.width.map(distanceFromMuv) ?? LaneSpec.typicalLaneWidths(lt, highwayTag)[0].0
    return LaneSpec(lt: lt, dir: dir, width: width, allowedTurns: turns, lane: lane)
}

/// `Rank`: a mode to look for on a lane, and the lane type it makes.
private struct Rank {
    var main: TMode
    var secondary: TMode?
    var designated: Bool
    var laneType: LaneType

    static func normal(_ main: TMode, _ lt: LaneType) -> Rank { Rank(main: main, designated: false, laneType: lt) }
    static func designated(_ main: TMode, _ lt: LaneType) -> Rank { Rank(main: main, designated: true, laneType: lt) }

    /// `Rank::evaluate_mode` without a date: the closest unconditional
    /// access up the mode's hierarchy.
    static func evaluateMode(_ mode: TMode, _ on: TModes<Conditional<AccessLevel>>) -> AccessLevel? {
        for m in mode.iterHierarchy() {
            if let base = on.getRaw(m)?.base { return base }
        }
        return nil
    }

    func isAllowed(_ on: TModes<Conditional<AccessLevel>>) -> Bool {
        guard let accessMain = Rank.evaluateMode(main, on) else { return false }
        if designated {
            if accessMain != .designated { return false }
        } else if !accessLevelAllowed(accessMain) {
            return false
        }
        guard let secondary else { return true }
        guard let accessSecondary = Rank.evaluateMode(secondary, on) else { return false }
        if accessSecondary == .designated && accessMain != .designated { return false }
        return accessLevelAllowed(accessSecondary)
    }
}

private func accessLevelAllowed(_ access: AccessLevel) -> Bool {
    switch access {
    case .designated, .yes, .permissive, .discouraged, .destination, .customers, .private, .permit: return true
    default: return false
    }
}

/// The importance of the modes, most first: train > car > bus > shared use > bicycle > foot.
private let ranks: [Rank] = [
    .normal(.lightRail, .lightRail),
    .normal(.train, .lightRail),
    .designated(.motorcar, .driving),
    .designated(.bus, .bus),
    .normal(.motorcar, .driving),
    .normal(.bus, .bus),
    Rank(main: .bicycle, secondary: .foot, designated: false, laneType: .sharedUse),
    .designated(.bicycle, .biking),
    .designated(.foot, .footway),
    .normal(.bicycle, .biking),
    .normal(.foot, .footway),
    .normal(.all, .shoulder),
]

/// `travel_lane`.
private func travelLane(_ t: TravelLane, _ isSidepath: Bool,
                        _ trafficDirection: Direction) -> (LaneType, Direction, TurnDirections) {
    if let turnForward = t.forward.turn.get(.all), let turnBackward = t.backward.turn.get(.all) {
        let forwardBase = turnForward.base
        if forwardBase != nil && forwardBase == turnBackward.base {
            return (.sharedLeftTurn, .forward, TurnDirections())
        }
    }
    for rank in ranks {
        let accessForward = rank.isAllowed(t.forward.access)
        let accessBackward = rank.isAllowed(t.backward.access)
        let dir: Direction
        switch (accessForward, accessBackward) {
        case (true, false): dir = .forward
        case (false, true): dir = .backward
        case (true, true): dir = trafficDirection
        case (false, false): continue
        }
        // A footway that is a sidepath of another road is its sidewalk.
        let laneType = isSidepath && rank.laneType == .footway ? LaneType.sidewalk : rank.laneType
        let turns = (accessForward ? t.forward : t.backward).turn.get(rank.main)?.base.map(turnDirections) ?? TurnDirections()
        return (laneType, dir, turns)
    }
    return (.construction, .forward, TurnDirections())
}

/// `parking_lane`.
private func parkingLane(_ p: ParkingLane, _ trafficDirection: Direction) -> (LaneType, Direction, TurnDirections) {
    let parkingType: ParkingType
    switch p.orientation {
    case .parallel, nil: parkingType = .parallel
    case .diagonal: parkingType = .diagonal
    case .perpendicular: parkingType = .perpendicular
    }
    return (.parking(parkingType), trafficDirection, TurnDirections())
}

/// `distance_from_muv`.
private func distanceFromMuv(_ q: Quantity<MuvLanes.Distance>) -> StreetGeom.Distance {
    .meters(Double(q.to(.metre).value.number))
}

/// `TurnDirection::from_muv`.
private func turnDirections(_ value: Turn) -> TurnDirections {
    var res = TurnDirections()
    let pairs: [(Turn, TurnDirection)] = [
        (.through, .through), (.left, .left), (.right, .right), (.slightLeft, .slightLeft), (.slightRight, .slightRight),
        (.sharpLeft, .sharpLeft), (.sharpRight, .sharpRight), (.mergeToLeft, .mergeLeft), (.mergeToRight, .mergeRight),
        (.reverse, .reverse),
    ]
    for (t, d) in pairs where value.contains(t) { res.insert(d) }
    return res
}
