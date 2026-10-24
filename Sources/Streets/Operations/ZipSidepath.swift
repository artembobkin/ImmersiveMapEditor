/// osm2streets's sidepaths: a cycleway running beside a main road, joined to
/// it by short connectors at both ends, is zipped into the main road as
/// lanes behind a buffer.

import StreetGeom

public struct Sidepath {
    var sidepath: RoadID
    var sidepathCenter: PolyLine
    var mainRoadSrcI: IntersectionID
    var mainRoadDstI: IntersectionID
    var mainRoads: [RoadID]

    public init?(_ streets: StreetNetwork, _ start: RoadID) {
        let shortRoadThreshold = Distance(constMeters: 10.0)
        let sidepathRoad = streets.roads[start]!
        // Each end should have exactly one very short connector.
        var mainRoadEndpoints: [IntersectionID] = []
        for i in sidepathRoad.endpoints() {
            let candidates = streets.roadsPerIntersection(i).filter { $0.untrimmedLength() < shortRoadThreshold }.map(\.id)
            if candidates.count == 1 { mainRoadEndpoints.append(streets.roads[candidates[0]]!.otherSide(i)) }
        }
        if mainRoadEndpoints.count != 2 { return nil }
        let src = mainRoadEndpoints[0]
        let dst = mainRoadEndpoints[1]
        guard let path = streets.simplePath(src, dst, [.driving]) ?? streets.simplePath(dst, src, [.driving]) else {
            return nil
        }
        sidepath = sidepathRoad.id
        sidepathCenter = sidepathRoad.centerLine
        mainRoadSrcI = src
        mainRoadDstI = dst
        mainRoads = path.map(\.0)
    }

    public func zip(_ streets: inout StreetNetwork) {
        precondition(streets.roads.contains(sidepath))
        var sidepathLanes = streets.removeRoad(sidepath).laneSpecsLTR
        // Shoulders were likely inferred for the shared path. Drop them.
        if sidepathLanes[0].lt == .shoulder { sidepathLanes.remove(at: 0) }
        if sidepathLanes.last!.lt == .shoulder { sidepathLanes.removeLast() }
        let buffer = LaneSpec(lt: .buffer(.planters), dir: .forward, width: LaneSpec.typicalLaneWidth(.buffer(.planters)))
        for r in mainRoads {
            let mainRoad = streets.roads[r]!
            let (left, right) = try! mainRoad.getUntrimmedSides(streets.config.drivingSide)
            let snapToLeft = sidepathCenter.middle().distTo(left.middle()) < sidepathCenter.middle().distTo(right.middle())
            let orientedSameWay = sidepathCenter.overallAngle().approxEq(left.overallAngle(), 90.0)
            let insertIdx: Int
            if snapToLeft {
                insertIdx = mainRoad.laneSpecsLTR[0].lt.isWalkable() ? 1 : 0
            } else {
                insertIdx = mainRoad.laneSpecsLTR.last!.lt.isWalkable() ? mainRoad.laneSpecsLTR.count - 1 : mainRoad.laneSpecsLTR.count
            }
            var insertLanes = sidepathLanes.map { lane -> LaneSpec in
                var lane = lane
                if !orientedSameWay { lane.dir = lane.dir.opposite() }
                return lane
            }
            var bufferLane = buffer
            if snapToLeft {
                bufferLane.dir = insertLanes.last!.dir
                insertLanes.append(bufferLane)
            } else {
                bufferLane.dir = insertLanes[0].dir
                insertLanes.insert(bufferLane, at: 0)
            }
            streets.roads.modify(r) { $0.laneSpecsLTR.insert(contentsOf: insertLanes, at: insertIdx) }
        }
    }
}

extension Road {
    /// The untrimmed left and right sides, in the road's direction.
    public func getUntrimmedSides(_ drivingSide: DrivingSide) throws -> (PolyLine, PolyLine) {
        let totalWidth = self.totalWidth()
        let refPosition: RoadPosition
        switch referenceLinePlacement {
        case .consistent(let p), .varying(let p, _): refPosition = p
        case .transition: refPosition = .center
        }
        let refOffset = leftEdgeOffsetOf(refPosition, drivingSide)
        let left = try referenceLine.shiftFromCenter(totalWidth, refOffset - totalWidth)
        let right = try referenceLine.shiftFromCenter(totalWidth, totalWidth - refOffset)
        return (left, right)
    }
}

extension StreetNetwork {
    /// Zips every cycleway that runs beside a main road into it.
    mutating func zipSidepaths() {
        var sidepaths: [Sidepath] = []
        for r in roads.values where r.isCycleway() {
            if let s = Sidepath(self, r.id) { sidepaths.append(s) }
        }
        for s in sidepaths { s.zip(&self) }
    }
}
