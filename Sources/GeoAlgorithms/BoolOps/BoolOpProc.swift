/// geo's boolean operation driver (`bool_ops/op.rs`): the input edges with the regions on their
/// two sides, and the sweep over them that computes each region and hands the edges between
/// regions of different membership to the spec.

/// An input edge, geo's `Edge`. `region2` holds the region seen when finite precision makes the
/// sweep look at a piece from its end towards its start.
final class BoolOpEdge: SweepCross {
    let line: LineOrPoint
    let idx: Int
    var region: SpecRegion
    var region2: SpecRegion

    init(geom: LineOrPoint, idx: Int, region: SpecRegion) {
        self.line = geom
        self.idx = idx
        self.region = region
        self.region2 = region
    }

    func getRegion(_ piece: LineOrPoint) -> SpecRegion {
        piece.left.lt(line.right) ? region : region2
    }

    func setRegion(_ region: SpecRegion, _ piece: LineOrPoint) {
        if piece.left.lt(line.right) {
            self.region = region
        } else {
            self.region2 = region
        }
    }
}

struct BoolOpProc<S: SweepSpec> {
    var spec: S
    private(set) var edges: [BoolOpEdge] = []

    init(spec: S, capacity: Int) {
        self.spec = spec
        edges.reserveCapacity(capacity)
    }

    /// `idx` tells the first input (0) from the second (1).
    mutating func addMultiPolygon(_ mp: GeoMultiPolygon, _ idx: Int) throws(GeoPanic) {
        for p in mp.polygons {
            try addPolygon(p, idx)
        }
    }

    mutating func addPolygon(_ poly: GeoPolygon, _ idx: Int) throws(GeoPanic) {
        try addClosedRing(poly.exterior, idx)
        for hole in poly.interiors {
            try addClosedRing(hole, idx)
        }
    }

    mutating func addLineString(_ ls: GeoLineString, _ idx: Int) throws(GeoPanic) {
        for line in ls.lines {
            let lp = try LineOrPoint(line)
            if !lp.isLine {
                continue
            }
            edges.append(BoolOpEdge(geom: lp, idx: idx, region: spec.infinity()))
        }
    }

    private mutating func addClosedRing(_ ring: GeoLineString, _ idx: Int) throws(GeoPanic) {
        if !ring.isClosed {
            throw GeoPanic("assertion failed: ring.is_closed()")
        }
        if ring.count <= 3 {
            return
        }
        try addLineString(ring, idx)
    }

    /// `Proc::sweep`.
    func sweep() throws(GeoPanic) -> S.Output {
        var spec = self.spec
        var iter = try CrossingsIter(edges)

        while try iter.next() != nil {
            try iter.sortIntersections()
            let crossings = iter.intersections

            // Process all end segments.
            var idx = 0
            var nextRegion: SpecRegion?
            while idx < crossings.count {
                let c = crossings[idx]
                // A start segment ends this part.
                if c.atLeft {
                    break
                }
                let cross = c.cross
                if nextRegion == nil {
                    nextRegion = cross.getRegion(c.line)
                }
                nextRegion = spec.cross(nextRegion!, cross.idx)
                let hasOverlap = (idx + 1) < crossings.count
                    && c.line.partialCmp(crossings[idx + 1].line) == .equal
                if !hasOverlap {
                    let prevRegion = cross.getRegion(c.line)
                    spec.output((prevRegion, nextRegion!), c.line, c.cross.idx)
                    nextRegion = nil
                }
                idx += 1
            }

            if idx >= crossings.count {
                continue
            }
            let botmostStartSegment = crossings[idx]

            let prev = try iter.prevActive(botmostStartSegment)
            var region = prev.map { $0.1.getRegion($0.0) } ?? spec.infinity()

            while idx < crossings.count {
                var c = crossings[idx]
                var jdx = idx
                while true {
                    region = spec.cross(region, c.cross.idx)
                    let hasOverlap = (idx + 1) < crossings.count
                        && c.line.partialCmp(crossings[idx + 1].line) == .equal
                    if !hasOverlap {
                        break
                    }
                    idx += 1
                    c = crossings[idx]
                }
                while jdx <= idx {
                    let gpiece = crossings[jdx].line
                    crossings[jdx].cross.setRegion(region, gpiece)
                    jdx += 1
                }
                idx += 1
            }
        }
        return try spec.finish()
    }
}
