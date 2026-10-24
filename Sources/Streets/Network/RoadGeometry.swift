/// Where things lie across a road's width: the offset of a placement from
/// the left edge, the lanes' center lines, the sides, trimming both ends,
/// and the edges of roads around an intersection.

import StreetGeom

extension Road {
    /// The distance from the left edge to a position across the road.
    public func leftEdgeOffsetOf(_ position: RoadPosition, _ drivingSide: DrivingSide) -> Distance {
        switch position {
        case .fullWidthCenter:
            return halfWidth()
        case .center:
            // The midpoint between the first and last roadway lane.
            var leftBuffer = Distance.zero
            var roadwayWidth = Distance.zero
            var rightBuffer = Distance.zero
            for lane in laneSpecsLTR {
                if !lane.lt.isRoadway() {
                    if roadwayWidth == .zero { leftBuffer += lane.width } else { rightBuffer += lane.width }
                } else {
                    // The right buffer was a middle buffer.
                    roadwayWidth += rightBuffer
                    rightBuffer = .zero
                    roadwayWidth += lane.width
                }
            }
            return roadwayWidth == .zero ? leftBuffer / 2.0 : leftBuffer + roadwayWidth / 2.0
        case .separation:
            let leftDir: Direction = drivingSide == .left ? .forward : .backward
            var foundFirstSide = false
            var medianWidth = Distance.zero
            var distSoFar = Distance.zero
            for lane in laneSpecsLTR {
                if lane.lt == .sharedLeftTurn {
                    return distSoFar + lane.width / 2.0
                } else if lane.lt.isTaggedByLanesSuffix() {
                    if lane.dir == leftDir {
                        foundFirstSide = true
                    } else {
                        return distSoFar - medianWidth / 2.0
                    }
                    medianWidth = .zero
                } else if foundFirstSide {
                    medianWidth += lane.width
                }
                distSoFar += lane.width
            }
            return distSoFar - medianWidth
        case .leftOf(let target), .middleOf(let target), .rightOf(let target):
            let targetDir = target.direction()
            let targetNum = target.number()
            var distSoFar = Distance.zero
            var lanesFound = 0
            let lanes = targetDir == .forward ? laneSpecsLTR : laneSpecsLTR.reversed()
            for lane in lanes {
                if lane.dir == targetDir && lane.lt.isTaggedByLanesSuffix() {
                    lanesFound += 1
                    if lanesFound == targetNum {
                        if case .middleOf = position {
                            distSoFar += lane.width / 2.0
                        } else if case .rightOf = position {
                            distSoFar += lane.width
                        }
                        return targetDir == .forward ? distSoFar : totalWidth() - distSoFar
                    }
                }
                distSoFar += lane.width
            }
            return halfWidth()
        }
    }

    /// The center of each lane, facing the road's direction.
    func getLaneCenterLines() -> [PolyLine] {
        let totalWidth = self.totalWidth()
        var widthSoFar = Distance.zero
        var output: [PolyLine] = []
        for lane in laneSpecsLTR {
            widthSoFar += lane.width / 2.0
            output.append((try? centerLine.shiftFromCenter(totalWidth, widthSoFar)) ?? centerLine)
            widthSoFar += lane.width / 2.0
        }
        return output
    }

    /// Trims both ends: a positive distance shortens, a negative one extends
    /// in a straight line. Nil when the two trims overlap.
    public static func trimPolylineBothEnds(_ pl: PolyLine, _ trimStart: Distance, _ trimEnd: Distance) -> PolyLine? {
        var pl = pl
        if trimStart + trimEnd > pl.length { return nil }
        if trimStart > .zero {
            guard let s = try? pl.maybeExactSlice(trimStart, pl.length) else { return nil }
            pl = s
        } else if trimStart < .zero {
            pl = pl.reversed().extendToLength(pl.length - trimStart).reversed()
        }
        if trimEnd > .zero {
            guard let s = try? pl.maybeExactSlice(.zero, pl.length - trimEnd) else { return nil }
            pl = s
        } else if trimEnd < .zero {
            pl = pl.extendToLength(pl.length - trimEnd)
        }
        return pl
    }
}

/// The edge of a road, pointed into an intersection.
struct RoadEdge {
    var road: RoadID
    /// Pointed into the intersection.
    var pl: PolyLine
    var lane: LaneSpec
    var side: DrivingSide

    /// The left and right edge of each road, pointed in, all clockwise. To
    /// visit every adjacent pair, the caller repeats the first edge.
    static func calculate(_ sortedRoads: [Road], _ i: IntersectionID) -> [RoadEdge] {
        var edges: [RoadEdge] = []
        for road in sortedRoads {
            var left = RoadEdge(road: road.id, pl: road.centerLine.mustShiftLeft(road.halfWidth()),
                                lane: road.laneSpecsLTR[0], side: .left)
            var right = RoadEdge(road: road.id, pl: road.centerLine.mustShiftRight(road.halfWidth()),
                                 lane: road.laneSpecsLTR.last!, side: .right)
            if road.dstI == i {
                edges.append(right)
                edges.append(left)
            } else {
                left.pl = left.pl.reversed()
                right.pl = right.pl.reversed()
                edges.append(left)
                edges.append(right)
            }
        }
        return edges
    }
}

/// A road as the intersection geometry sees it.
public struct InputRoad {
    public var id: RoadID
    public var srcI: IntersectionID
    public var dstI: IntersectionID
    /// The true center, sidewalks included, untrimmed on both ends.
    public var centerLine: PolyLine
    public var totalWidth: Distance
    public var highwayType: String

    public func halfWidth() -> Distance { totalWidth / 2.0 }

    public func centerLinePointedAt(_ i: IntersectionID) -> PolyLine {
        if dstI == i { return centerLine }
        precondition(srcI == i)
        return centerLine.reversed()
    }

    func toRoad() -> Road { Road(id: id, srcI: srcI, dstI: dstI, centerLine: centerLine, totalWidth: totalWidth) }
}
