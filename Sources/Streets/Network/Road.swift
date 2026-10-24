/// osm2streets's `Road`: one segment between two intersections, its
/// reference line from OSM, its trimmed center line and its lanes.

import OSMReader
import StreetGeom

public enum TrafficInterruption: Hashable, Sendable {
    case uninterrupted, yield, stop, signal, deadEnd
}

public struct StopLine: Equatable, Sendable {
    /// Along the reference line, only when tagged.
    public var vehicleDistance: Distance?
    /// An advanced stop line for cyclists.
    public var bikeDistance: Distance?
    public var interruption: TrafficInterruption

    public static func dummy() -> StopLine { StopLine(vehicleDistance: nil, bikeDistance: nil, interruption: .uninterrupted) }
}

public struct Road: Sendable {
    public var id: RoadID
    /// The OSM ways making up this road (several once an intersection is collapsed).
    public var osmIDs: [WayID]
    public var srcI: IntersectionID
    public var dstI: IntersectionID
    /// The `highway` tag (or `railway` for railways).
    public var highwayType: String
    public var name: String?
    /// Only for connectivity, physically part of a complex intersection.
    public var internalJunctionRoad: Bool
    public var layer: Int
    public var speedLimit: Speed?
    /// The OSM geometry, slightly smoothed, untrimmed.
    public var referenceLine: PolyLine
    public var referenceLinePlacement: Placement
    /// The physical center of all the lanes, trimmed.
    public var centerLine: PolyLine
    public var trimStart: Distance
    public var trimEnd: Distance
    public var turnRestrictions: [(RestrictionType, RoadID)]
    /// (via, to), via an entire road. Only bans.
    public var complicatedTurnRestrictions: [(RoadID, RoadID)]
    public var laneSpecsLTR: [LaneSpec]
    public var stopLineStart: StopLine
    public var stopLineEnd: StopLine

    public init(id: RoadID, osmIDs: [WayID], srcI: IntersectionID, dstI: IntersectionID, referenceLine: PolyLine,
                osmTags: Tags, config: MapConfig, laneSpecs: LaneSpecSource) {
        let lanes = laneSpecs.laneSpecsLTR(osmTags, config)
        var layer = 0
        if let l = osmTags.get("layer") {
            if let v = parseRustF64ForLayer(l) { layer = Int(rustAsI64(v)) }
        }
        let speedLimit = osmTags.get("maxspeed").flatMap(parseMaxspeed)
        let placement = (try? Placement.parse(osmTags)) ?? .consistent(.center)
        guard let highway = osmTags.get("highway") ?? osmTags.get("railway") else {
            fatalError("Can't create a Road without the highway or railway tag")
        }
        self.id = id
        self.osmIDs = osmIDs
        self.srcI = srcI
        self.dstI = dstI
        self.highwayType = highway
        self.name = osmTags.get("name")
        self.internalJunctionRoad = osmTags.is("junction", "intersection")
        self.layer = layer
        self.speedLimit = speedLimit
        self.referenceLine = referenceLine
        self.referenceLinePlacement = placement
        self.centerLine = .dummy()
        self.trimStart = .zero
        self.trimEnd = .zero
        self.turnRestrictions = []
        self.complicatedTurnRestrictions = []
        self.laneSpecsLTR = lanes
        self.stopLineStart = .dummy()
        self.stopLineEnd = .dummy()
        updateCenterLine(config.drivingSide)
    }

    /// For `InputRoad.toRoad`: only what `RoadEdge.calculate` needs is real.
    init(id: RoadID, srcI: IntersectionID, dstI: IntersectionID, centerLine: PolyLine, totalWidth: Distance) {
        self.id = id
        self.osmIDs = []
        self.srcI = srcI
        self.dstI = dstI
        self.highwayType = ""
        self.name = nil
        self.internalJunctionRoad = false
        self.layer = 0
        self.speedLimit = nil
        self.referenceLine = .dummy()
        self.referenceLinePlacement = .transition
        self.centerLine = centerLine
        self.trimStart = .zero
        self.trimEnd = .zero
        self.turnRestrictions = []
        self.complicatedTurnRestrictions = []
        self.laneSpecsLTR = [LaneSpec(lt: .driving, dir: .forward, width: totalWidth)]
        self.stopLineStart = .dummy()
        self.stopLineEnd = .dummy()
    }

    /// Resets the center line from the reference line and placement, untrimmed.
    public mutating func updateCenterLine(_ drivingSide: DrivingSide) {
        centerLine = getUntrimmedCenterLine(drivingSide)
    }

    public func getUntrimmedCenterLine(_ drivingSide: DrivingSide) -> PolyLine {
        let refPosition: RoadPosition
        switch referenceLinePlacement {
        case .consistent(let p): refPosition = p
        case .varying(let p, _): refPosition = p
        case .transition: refPosition = .center
        }
        let refOffset = leftEdgeOffsetOf(refPosition, drivingSide)
        let targetOffset = leftEdgeOffsetOf(.fullWidthCenter, drivingSide)
        return (try? referenceLine.shiftEitherDirection(targetOffset - refOffset)) ?? referenceLine
    }

    public func isLightRail() -> Bool { laneSpecsLTR.allSatisfy { $0.lt == .lightRail } }
    public func isService() -> Bool { highwayType == "service" }

    public func isCycleway() -> Bool {
        var bike = false
        for spec in laneSpecsLTR {
            if spec.lt == .biking { bike = true } else if !spec.lt.isWalkable() { return false }
        }
        return bike
    }

    public func isDriveable() -> Bool { laneSpecsLTR.contains { $0.lt == .driving } }

    /// Only for walking.
    public func isFootway() -> Bool { laneSpecsLTR.count == 1 && laneSpecsLTR[0].lt.isWalkable() }

    public func onewayForDriving() -> Direction? { LaneSpec.onewayForDriving(laneSpecsLTR) }

    public func canDriveOutOfEnd(_ whichEnd: IntersectionID) -> Bool {
        guard let d = onewayForDriving() else { return true }
        return d == (dstI == whichEnd ? .forward : .backward)
    }

    func canDriveIntoEnd(_ whichEnd: IntersectionID) -> Bool {
        guard let d = onewayForDriving() else { return true }
        return d == (srcI == whichEnd ? .forward : .backward)
    }

    public func allowedToTurnTo(_ dest: RoadID) -> Bool {
        var hasExclusiveAllows = false
        for (t, other) in turnRestrictions {
            switch t {
            case .banTurns:
                if other == dest { return false }
            case .onlyAllowTurns:
                if other == dest { return true }
                hasExclusiveAllows = true
            }
        }
        return !hasExclusiveAllows
    }

    public func angle() -> Angle { referenceLine.firstPt().angleTo(referenceLine.lastPt()) }

    public func untrimmedLength() -> Distance { referenceLine.length }

    public func totalWidth() -> Distance { laneSpecsLTR.map(\.width).sum() }
    public func halfWidth() -> Distance { totalWidth() / 2.0 }

    public func endpoints() -> [IntersectionID] { [srcI, dstI] }

    func toInputRoad(_ drivingSide: DrivingSide) -> InputRoad {
        InputRoad(id: id, srcI: srcI, dstI: dstI, centerLine: getUntrimmedCenterLine(drivingSide),
                  totalWidth: totalWidth(), highwayType: highwayType)
    }

    public func otherSide(_ i: IntersectionID) -> IntersectionID {
        if srcI == i { return dstI }
        if dstI == i { return srcI }
        fatalError("\(id) doesn't have \(i) on either side")
    }

    public func commonEndpoint(_ other: Road) -> CommonEndpoint {
        CommonEndpoint((srcI, dstI), (other.srcI, other.dstI))
    }

    public func fromOSMWay(_ way: WayID) -> Bool { osmIDs.contains(way) }
}

/// Rust's `str::parse::<f64>` for the `layer` tag.
func parseRustF64ForLayer(_ s: String) -> Double? { parseRustF64(s) }

func parseMaxspeed(_ maxspeed: String) -> Speed? {
    if let kmph = parseRustF64(maxspeed) { return .kmPerHour(kmph) }
    if maxspeed.hasSuffix(" mph"), let mph = parseRustF64(String(maxspeed.dropLast(4))) {
        return .milesPerHour(mph)
    }
    return nil
}
