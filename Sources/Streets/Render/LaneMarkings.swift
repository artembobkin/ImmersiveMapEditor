/// osm2streets's lane markings: lines between lanes, stop lines, arrows,
/// buffer stripes, parking hatches, sidewalk lines and path outlines.

import StreetGeom

extension StreetNetwork {
    public func toLaneMarkingsGeoJSON(_ filter: Filter) throws -> String {
        let gps = gpsBounds
        var features: [GeoJSONFeature] = []
        func add(_ geometry: GeoJSONGeometry, _ type: String, layer: Int?) {
            var f = GeoJSONFeature(geometry)
            f.setProperty("type", .string(type))
            if let layer { f.setProperty("layer", .int(Int64(layer))) }
            features.append(f)
        }
        for road in filter.roads(self) {
            var laneCenters = road.getLaneCenterLines()
            let specs = road.laneSpecsLTR
            if specs.count >= 2 {
                for idx in 0..<(specs.count - 1) {
                    let pair = (specs[idx], specs[idx + 1])
                    if pair.0.dir != pair.1.dir {
                        let between = try laneCenters[idx].shiftRight(pair.0.width / 2.0)
                        for poly in between.dashedLines(.meters(0.25), .meters(2.0), .meters(1.0)) {
                            add(poly.toGeoJSON(gps), "center line", layer: road.layer)
                        }
                        continue
                    }
                    if pair.0.lt == .driving && pair.1.lt == .driving {
                        let between = try laneCenters[idx].shiftRight(pair.0.width / 2.0)
                        for poly in between.dashedLines(.meters(0.25), .meters(1.0), .meters(1.5)) {
                            add(poly.toGeoJSON(gps), "lane separator", layer: road.layer)
                        }
                    }
                }
            }
            // Stop line distances are relative to the road's direction.
            for (lane, center) in zip(specs, laneCenters) {
                for (polygon, kind) in drawStopLines(lane, center, road) { add(polygon.toGeoJSON(gps), kind, layer: nil) }
            }
            // The rest needs the centers pointing along the lane.
            for k in specs.indices where specs[k].dir == .backward { laneCenters[k] = laneCenters[k].reversed() }

            for (lane, center) in zip(specs, laneCenters) where lane.lt.isForMovingVehicles() {
                let arrowLen = Distance.meters(1.75)
                let thickness = Distance.meters(0.25)
                for (pt, angle) in center.stepAlong(.meters(20.0), .meters(5.0)) {
                    let arrow = PolyLine.mustNew([pt.projectAway(arrowLen / 2.0, angle.opposite()),
                                                  pt.projectAway(arrowLen / 2.0, angle)])
                        .makeArrow(thickness * 2.0, .triangle)
                        .getOuterRing()
                        .toOutline(thickness / 2.0)
                    add(arrow.toGeoJSON(gps), "lane arrow", layer: road.layer)
                }
            }

            for (lane, center) in zip(specs, laneCenters) {
                guard case .buffer(let b) = lane.lt, b != .curb else { continue }
                let thickness = Distance.meters(0.25)
                for dir in [-1.0, 1.0] {
                    let side = try! center.shiftEitherDirection(dir * (lane.width - thickness) / 2.0)
                    add(side.makePolygons(thickness).toGeoJSON(gps), "buffer edge", layer: road.layer)
                }
                for (c, angle) in center.stepAlong(.meters(3.0), .meters(5.0)) {
                    let left = c.projectAway(lane.width / 2.0 + thickness, angle.rotateDegs(45.0))
                    let right = c.projectAway(lane.width / 2.0 + thickness, angle.rotateDegs(45.0).opposite())
                    add(Line.mustNew(left, right).makePolygons(thickness).toGeoJSON(gps), "buffer stripe", layer: road.layer)
                }
            }

            for (lane, center) in zip(specs, laneCenters) {
                let polygons: [Polygon]
                switch lane.lt {
                case .parking(.parallel): polygons = drawParallelParkingLines(lane, center)
                case .parking(.diagonal): polygons = drawDiagonalParkingLines(lane, center)
                case .parking(.perpendicular): polygons = drawPerpendicularParkingLines(lane, center)
                default: continue
                }
                for p in polygons { add(p.toGeoJSON(gps), "parking hatch", layer: nil) }
            }

            for (lane, center) in zip(specs, laneCenters) where lane.lt == .sidewalk {
                for p in drawSidewalkLines(lane, center) { add(p.toGeoJSON(gps), "sidewalk line", layer: nil) }
            }

            for (lane, center) in zip(specs, laneCenters) where lane.lt == .sharedUse || lane.lt == .footway {
                for p in drawPathOutlines(lane, center) { add(p.toGeoJSON(gps), "path outline", layer: nil) }
            }
        }
        return featureCollectionString(features)
    }

    func drawParallelParkingLines(_ lane: LaneSpec, _ center: PolyLine) -> [Polygon] {
        var result: [Polygon] = []
        let spots = (center.length / config.parallelStreetParkingSpotLength).rounded(.down) - 2.0
        guard spots >= 1.0 else { return result }
        let numSpots = rustAsUsize(spots)
        let legLength = Distance.meters(1.0)
        for idx in 0...numSpots {
            let (pt, laneAngle) = center.mustDistAlong(config.parallelStreetParkingSpotLength * (1.0 + Double(idx)))
            let perpAngle = config.drivingSide == .right ? laneAngle.rotateDegs(270.0) : laneAngle.rotateDegs(90.0)
            let tPt = pt.projectAway(lane.width * 0.4, perpAngle)
            let p1 = tPt.projectAway(legLength, perpAngle.opposite())
            result.append(Line.mustNew(tPt, p1).makePolygons(.meters(0.25)))
            let p2 = tPt.projectAway(legLength, laneAngle)
            result.append(Line.mustNew(tPt, p2).makePolygons(.meters(0.25)))
            let p3 = tPt.projectAway(legLength, laneAngle.opposite())
            result.append(Line.mustNew(tPt, p3).makePolygons(.meters(0.25)))
        }
        return result
    }

    func drawDiagonalParkingLines(_ lane: LaneSpec, _ center: PolyLine) -> [Polygon] {
        var result: [Polygon] = []
        let spots = (center.length / config.vehicleWidthForParkingSpots).rounded(.down) - 2.0
        guard spots >= 1.0 else { return result }
        for idx in 0...rustAsUsize(spots) {
            let (pt, laneAngle) = center.mustDistAlong(config.vehicleWidthForParkingSpots * (1.0 + Double(idx)))
            let offset = lane.dir == .forward ? -45.0 : 45.0
            let diagAngle = config.drivingSide == .right ? laneAngle.rotateDegs(270.0 + offset)
                : laneAngle.rotateDegs(90.0 + offset)
            let outsidePt = pt.projectAway(lane.width * 0.4, diagAngle)
            let insidePt = pt.projectAway(lane.width * 0.5, diagAngle.opposite())
            result.append(Line.mustNew(outsidePt, insidePt).makePolygons(.meters(0.25)))
        }
        return result
    }

    func drawPerpendicularParkingLines(_ lane: LaneSpec, _ center: PolyLine) -> [Polygon] {
        var result: [Polygon] = []
        let spots = (center.length / config.vehicleWidthForParkingSpots).rounded(.down) - 2.0
        guard spots >= 1.0 else { return result }
        for idx in 0...rustAsUsize(spots) {
            let (pt, laneAngle) = center.mustDistAlong(config.vehicleWidthForParkingSpots * (1.0 + Double(idx)))
            let perpAngle = config.drivingSide == .right ? laneAngle.rotateDegs(270.0) : laneAngle.rotateDegs(90.0)
            let outsidePt = pt.projectAway(lane.width * 0.4, perpAngle)
            let insidePt = pt.projectAway(lane.width * 0.5, perpAngle.opposite())
            result.append(Line.mustNew(outsidePt, insidePt).makePolygons(.meters(0.25)))
        }
        return result
    }
}

func drawStopLines(_ lane: LaneSpec, _ center: PolyLine, _ road: Road) -> [(Polygon, String)] {
    var results: [(Polygon, String)] = []
    switch lane.lt {
    case .driving, .bus, .biking: break
    default: return results
    }
    let thickness = Distance.meters(0.5)
    let stopLine = lane.dir == .forward ? road.stopLineEnd : road.stopLineStart
    for (dist, kind) in [(stopLine.vehicleDistance, "vehicle stop line"), (stopLine.bikeDistance, "bike stop line")] {
        guard let dist, let (pt, angle) = try? center.distAlong(dist) else { continue }
        let line = Line.mustNew(pt.projectAway(lane.width / 2.0, angle.rotateDegs(90.0)),
                                pt.projectAway(lane.width / 2.0, angle.rotateDegs(-90.0)))
        results.append((line.makePolygons(thickness), kind))
    }
    return results
}

func drawSidewalkLines(_ lane: LaneSpec, _ center: PolyLine) -> [Polygon] {
    center.stepAlong(lane.width, lane.width).map { pt, angle in
        let pt2 = pt.projectAway(.meters(1.0), angle)
        return perpLine(Line.mustNew(pt, pt2), lane.width).makePolygons(.meters(0.25))
    }
}

func drawPathOutlines(_ lane: LaneSpec, _ center: PolyLine) -> [Polygon] {
    var result: [Polygon] = []
    for dir in [-1.0, 1.0] {
        let pl = try! center.shiftEitherDirection(dir * lane.width / 2.0)
        result.append(contentsOf: pl.exactDashedPolygons(.meters(0.25), .meters(1.0), .meters(1.5)))
    }
    return result
}

/// A line of `length` across `l`, at its first point.
func perpLine(_ l: Line, _ length: Distance) -> Line {
    let pt1 = l.shiftRight(length / 2.0).pt1
    let pt2 = l.shiftLeft(length / 2.0).pt1
    return Line.mustNew(pt1, pt2)
}
