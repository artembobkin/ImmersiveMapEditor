/// osm2streets's geometry for three roads where one is a highway ramp: the
/// thin road is trimmed to where it meets a thick one, and the other thick
/// road is lengthened over the merge.

import StreetGeom

private let mergePointLength = Distance(constMeters: 5.0)

private struct Piece {
    var id: RoadID
    var dstI: IntersectionID
    var left: PolyLine
    var center: PolyLine
    var right: PolyLine
}

func onOffRamp(_ results: GeometryResults, _ roads: InputRoads, _ sortedRoads: [RoadID]) -> GeometryResults? {
    var results = results
    var roads = roads
    if roads.count != 3 { return nil }
    let rampTypes = ["motorway", "motorway_link", "primary_link", "secondary_link", "tertiary_link", "trunk_link"]
    if !roads.values.contains(where: { rampTypes.contains($0.highwayType) }) { return nil }

    var pieces: [Piece] = []
    for r in sortedRoads {
        let road = roads[r]!
        let center = road.centerLinePointedAt(results.intersectionID)
        guard let left = try? center.shiftLeft(road.halfWidth()),
              let right = try? center.shiftRight(road.halfWidth()) else { return nil }
        pieces.append(Piece(id: road.id, dstI: road.dstI, left: left, center: center, right: right))
    }
    // Break ties by preferring the outbound roads for thin.
    let iid = results.intersectionID
    pieces = pieces.stableSorted { Pair(roads[$0.id]!.halfWidth(), $0.dstI == iid) }
    let thick1 = pieces.removeLast()
    let thick2 = pieces.removeLast()
    let thin = pieces.removeLast()

    var bestHit: (PolyLine, PolyLine, RoadID)?
    for thinPl in [thin.left, thin.right] {
        for thick in [thick1, thick2] {
            for thickPl in [thick.left, thick.right] {
                if thinPl == thickPl { return nil }
                guard let (hit, angle) = thinPl.intersection(thickPl) else { continue }
                let perp = InfiniteLine.fromPtAngle(hit, angle.rotateDegs(90.0))
                guard let trimTo = thin.center.reversed().intersectionInfinite(perp),
                      let trimmedThin = thin.center.getSliceEndingAt(trimTo) else { return nil }
                guard let (_, angle2) = thickPl.distAlongOfPoint(hit) else { return nil }
                let perp2 = InfiniteLine.fromPtAngle(hit, angle2.rotateDegs(90.0))
                guard let trimTo2 = thick.center.reversed().intersectionInfinite(perp2),
                      let trimmedThick = thick.center.getSliceEndingAt(trimTo2) else { return nil }
                if bestHit.map({ trimmedThin.length < $0.0.length }) ?? true {
                    bestHit = (trimmedThin, trimmedThick, thick.id)
                }
            }
        }
    }

    guard let best = bestHit else { return nil }
    var trimmedThin = best.0
    var trimmedThick = best.1
    let thickID = best.2
    if thin.dstI != results.intersectionID { trimmedThin = trimmedThin.reversed() }
    roads.modify(thin.id) { $0.centerLine = trimmedThin }

    let extra: PolyLine
    if roads[thickID]!.dstI == results.intersectionID {
        guard let e = roads[thickID]!.centerLine.getSliceStartingAt(trimmedThick.lastPt()) else { return nil }
        extra = e
    } else {
        trimmedThick = trimmedThick.reversed()
        guard let e = roads[thickID]!.centerLine.getSliceEndingAt(trimmedThick.firstPt()) else { return nil }
        extra = e.reversed()
    }
    roads.modify(thickID) { $0.centerLine = trimmedThick }
    if extra.length <= mergePointLength + 3.0 * epsilonDist { return nil }
    let extraSlice = extra.exactSlice(mergePointLength, extra.length)

    // Lengthen the other thick road.
    let otherID = thick1.id == thickID ? thick2.id : thick1.id
    var other = roads[otherID]!
    if other.dstI == results.intersectionID {
        guard let pl = try? other.centerLine.extend(extraSlice.reversed()) else { return nil }
        other.centerLine = pl
    } else {
        guard let pl = try? extraSlice.extend(other.centerLine) else { return nil }
        other.centerLine = pl
    }
    roads[otherID] = other

    var endpts: [Pt2D] = []
    for id in sortedRoads {
        let r = roads[id]!
        if r.dstI == results.intersectionID {
            guard let a = try? r.centerLine.shiftRight(r.halfWidth()), let b = try? r.centerLine.shiftLeft(r.halfWidth())
            else { return nil }
            endpts.append(a.lastPt())
            endpts.append(b.lastPt())
        } else {
            guard let a = try? r.centerLine.shiftLeft(r.halfWidth()), let b = try? r.centerLine.shiftRight(r.halfWidth())
            else { return nil }
            endpts.append(a.firstPt())
            endpts.append(b.firstPt())
        }
    }
    endpts.append(endpts[0])
    guard let ring = try? Ring.dedupingNew(endpts) else { return nil }
    results.intersectionPolygon = ring.intoPolygon()
    for id in roads.keys { results.trimmedCenterPts[id] = roads[id]!.centerLine }
    return results
}
