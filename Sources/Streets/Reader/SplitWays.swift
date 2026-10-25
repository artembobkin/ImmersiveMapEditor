/// streets_reader's `split_up_roads`: intersections at every point shared
/// by two roads and at every road's ends, roads split between them, then
/// turn restrictions, signals, stop lines and crossings matched to them.

import OSMReader
import StreetGeom

extension StreetNetwork {
    /// Returns the road each interior point ended up on.
    @discardableResult
    mutating func splitUpRoads(_ input: OsmExtract) -> [HashablePt2D: RoadID] {
        var input = input
        var countPerPt: [HashablePt2D: Int] = [:]
        var ptToIntersectionID: [HashablePt2D: IntersectionID] = [:]
        for (_, pts, _) in input.roads {
            for (idx, pt) in pts.enumerated() {
                let hashPt = pt.toHashable()
                let count = (countPerPt[hashPt] ?? 0) + 1
                countPerPt[hashPt] = count
                if count == 2 || idx == 0 || idx == pts.count - 1, ptToIntersectionID[hashPt] == nil {
                    // Clipped points have no OSM id.
                    var osmIDs: [NodeID] = []
                    if let n = input.osmNodeIDs[hashPt] { osmIDs.append(n) }
                    let kind: IntersectionKind = osmIDs.isEmpty ? .mapEdge : .intersection
                    let control: IntersectionControl
                    if osmIDs.isEmpty {
                        control = .uncontrolled
                    } else if input.trafficSignals.remove(hashPt) != nil {
                        control = .signalled
                    } else {
                        control = .signed
                    }
                    ptToIntersectionID[hashPt] = insertIntersection(osmIDs, pt, kind, control)
                }
            }
        }

        var ptToRoad: [HashablePt2D: RoadID] = [:]
        for (osmWayID, origPts, origTags) in input.roads {
            var pts: [Pt2D] = []
            var i1 = ptToIntersectionID[origPts[0].toHashable()]!
            for pt in origPts {
                pts.append(pt)
                if pts.count == 1 { continue }
                guard let i2 = ptToIntersectionID[pt.toHashable()] else { continue }
                let id = nextRoadID()
                for (idx, p) in pts.enumerated() where idx != 0 && idx != pts.count - 1 {
                    ptToRoad[p.toHashable()] = id
                }
                let untrimmed = simplifyLinestring(pts)
                pts = []
                if let pl = try? PolyLine.new(untrimmed) {
                    roads[id] = Road(id: id, osmIDs: [osmWayID], srcI: i1, dstI: i2, referenceLine: pl, osmTags: origTags,
                                     config: config, laneSpecs: laneSpecs)
                    intersections.modify(i1) { $0.roads.append(id) }
                    intersections.modify(i2) { $0.roads.append(id) }
                }
                i1 = i2
                pts.append(pt)
            }
            precondition(pts.count == 1)
        }

        // Simple turn restrictions, via a node.
        var restrictions: [(RoadID, RestrictionType, RoadID)] = []
        for (restriction, fromOSM, viaOSM, toOSM) in input.simpleTurnRestrictions {
            guard let via = intersections.values.first(where: { $0.osmIDs.contains(viaOSM) }) else { continue }
            let rs = roadsPerIntersection(via.id)
            if let from = rs.first(where: { $0.fromOSMWay(fromOSM) }), let to = rs.first(where: { $0.fromOSMWay(toOSM) }) {
                restrictions.append((from.id, restriction, to.id))
            }
        }
        for (from, rt, to) in restrictions { roads.modify(from) { $0.turnRestrictions.append((rt, to)) } }

        // Complicated turn restrictions, via a way connected to both roads.
        var complicated: [(RoadID, RoadID, RoadID)] = []
        for (_, fromOSM, viaOSM, toOSM) in input.complicatedTurnRestrictions {
            let viaCandidates = roads.values.filter { $0.fromOSMWay(viaOSM) }
            if viaCandidates.count != 1 { continue }
            let via = viaCandidates[0]
            let around = roadsPerIntersection(via.srcI) + roadsPerIntersection(via.dstI)
            if let from = around.first(where: { $0.fromOSMWay(fromOSM) }), let to = around.first(where: { $0.fromOSMWay(toOSM) }) {
                complicated.append((from.id, via.id, to.id))
            }
        }
        for (from, via, to) in complicated { roads.modify(from) { $0.complicatedTurnRestrictions.append((via, to)) } }

        // Traffic signals tagged on incoming ways, not at intersections.
        let signals = hashMapOrder.map { $0.order(input.trafficSignals.entries, last: $0.signalsLast) }
            ?? input.trafficSignals.entries
        for (pt, dir) in signals {
            guard let r = ptToRoad[pt], var road = roads[r] else { continue }
            guard let d = dir ?? road.onewayForDriving() else { continue }
            let i = d == .forward ? road.dstI : road.srcI
            if !intersections[i]!.isMapEdge() { intersections.modify(i) { $0.control = .signalled } }
            if let (dist, _) = road.referenceLine.distAlongOfPoint(pt.toPt2D()) {
                hashMapOrder?.record("signals", r, atEnd: d == .forward, pt)
                if d == .forward {
                    road.stopLineEnd.vehicleDistance = dist
                    road.stopLineEnd.interruption = .signal
                } else {
                    road.stopLineStart.vehicleDistance = dist
                    road.stopLineStart.interruption = .signal
                }
            }
            roads[r] = road
        }

        // Cycleway advanced stop lines.
        for (pt, dir) in input.cyclewayStopLines {
            guard let r = ptToRoad[pt], var road = roads[r], let d = dir else { continue }
            guard let (dist, _) = road.referenceLine.distAlongOfPoint(pt.toPt2D()) else { continue }
            let i = d == .forward ? road.dstI : road.srcI
            let signalled = intersections[i]!.control == .signalled
            if d == .forward {
                road.stopLineEnd.bikeDistance = dist
                if signalled { road.stopLineEnd.interruption = .signal }
            } else {
                road.stopLineStart.bikeDistance = dist
                if signalled { road.stopLineStart.interruption = .signal }
            }
            roads[r] = road
        }

        let crossings = hashMapOrder.map { $0.order(input.crossings.entries, last: $0.crossingsLast) }
            ?? input.crossings.entries
        for (pt, crossing) in crossings {
            if let i = ptToIntersectionID[pt] { intersections.modify(i) { $0.crossing = crossing } }
            if let r = ptToRoad[pt], var road = roads[r] {
                if let (dist, _) = road.referenceLine.distAlongOfPoint(pt.toPt2D()) {
                    // Snap to the start or end within 30% of the length.
                    let pct = dist / road.referenceLine.length
                    if pct < 0.3 {
                        hashMapOrder?.record("crossings", r, atEnd: false, pt)
                        road.stopLineStart.vehicleDistance = dist
                        road.stopLineStart.interruption = .signal
                    } else if pct > 0.7 {
                        hashMapOrder?.record("crossings", r, atEnd: true, pt)
                        road.stopLineEnd.vehicleDistance = dist
                        road.stopLineEnd.interruption = .signal
                    }
                }
                roads[r] = road
            }
        }

        for i in intersections.keys {
            sortRoads(i)
            updateI(i)
        }
        return ptToRoad
    }
}

/// Fewer points along curves (0.5 m), which also keeps shifting sane.
func simplifyLinestring(_ pts: [Pt2D]) -> [Pt2D] {
    Pt2D.simplifyRDP(pts, 0.5)
}
