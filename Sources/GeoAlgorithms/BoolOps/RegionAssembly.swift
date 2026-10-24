/// geo's `RegionAssembly` (`bool_ops/assembly.rs`): builds the output polygons from the boundary
/// edges the sweep kept. A second, simple sweep links the edges into "snakes" (monotone chains),
/// which are joined into rings, sorted into exteriors and holes, and split at repeated points.

/// An output edge with the sweep state of the assembly (geo's assembly `Segment`).
final class AssemblySegment: SweepCross {
    let line: LineOrPoint
    var region = false
    var snakeIdx = 0

    init(_ geom: LineOrPoint) {
        self.line = geom
    }
}

struct RegionAssembly {
    private(set) var segments: [AssemblySegment] = []

    mutating func addEdge(_ edge: LineOrPoint) {
        segments.append(AssemblySegment(edge))
    }

    func finish() throws(GeoPanic) -> GeoMultiPolygon {
        var iter = try CrossingsIter(simple: segments)
        var snakes: [Snake] = []

        while let pt = try iter.next() {
            let numSegments = iter.intersections.count
            try iter.sortIntersections()
            let crossings = iter.intersections

            let first = crossings[0]
            var prevRegion: Bool
            var parentSnakeIdx: Int?
            if first.atLeft {
                // No segment ends here, so the region below comes from the previous active one.
                if let (_, seg) = try iter.prevActive(first) {
                    prevRegion = seg.region
                    parentSnakeIdx = seg.snakeIdx
                } else {
                    prevRegion = false
                    parentSnakeIdx = 0
                }
            } else {
                prevRegion = first.cross.region
                parentSnakeIdx = nil
            }

            // Connect consecutive segments.
            var idx = prevRegion ? 1 : 0
            while idx < crossings.count {
                let c = crossings[idx]
                let d: Crossing<AssemblySegment>
                if idx == numSegments - 1 {
                    d = crossings[0]
                } else {
                    d = try crossings.checked(idx + 1)
                }
                idx += 2

                if c.atLeft {
                    c.cross.region = true
                    if parentSnakeIdx == nil {
                        parentSnakeIdx = try iter.prevActive(c).map { $0.1.snakeIdx } ?? 0
                    }
                }
                if d.atLeft {
                    d.cross.region = false
                    if parentSnakeIdx == nil {
                        parentSnakeIdx = try iter.prevActive(d).map { $0.1.snakeIdx } ?? 0
                    }
                }

                switch (c.atLeft, d.atLeft) {
                case (true, true):
                    // Two new snakes, paired with each other.
                    let l = snakes.count
                    snakes.append(Snake(
                        start: SweepPoint(pt), end: c.line.right, pair: l + 1,
                        region: .counterClockwise, parentSnakeIdx: parentSnakeIdx!))
                    c.cross.snakeIdx = l
                    snakes.append(Snake(
                        start: SweepPoint(pt), end: d.line.right, pair: l,
                        region: .clockwise, parentSnakeIdx: parentSnakeIdx!))
                    d.cross.snakeIdx = l + 1
                case (true, false):
                    // Connect d to c.
                    let sIdx = d.cross.snakeIdx
                    try checkIndex(sIdx, snakes.count)
                    snakes[sIdx].push(c.line.right)
                    c.cross.snakeIdx = sIdx
                case (false, true):
                    // Connect c to d.
                    let sIdx = c.cross.snakeIdx
                    try checkIndex(sIdx, snakes.count)
                    snakes[sIdx].push(d.line.right)
                    d.cross.snakeIdx = sIdx
                case (false, false):
                    let cIdx = c.cross.snakeIdx
                    let dIdx = d.cross.snakeIdx
                    try checkIndex(cIdx, snakes.count)
                    try checkIndex(dIdx, snakes.count)
                    snakes[cIdx].finish(dIdx)
                    snakes[dIdx].finish(cIdx)
                }
            }
        }

        let (rings, snakeIdxMap) = try ringsFromSnakes(&snakes)
        return try assemblePolygons(rings, snakeIdxMap)
    }
}

func checkIndex(_ index: Int, _ count: Int) throws(GeoPanic) {
    if index < 0 || index >= count {
        throw GeoPanic.indexOutOfBounds(index, count)
    }
}

/// Sorts the rings into exteriors with their holes (a hole belongs to the nearest enclosing
/// ring that is not a hole) and splits every ring at its repeated points.
private func assemblePolygons(_ rings: [AssemblyRing], _ snakeIdxMap: [Int: Int]) throws(GeoPanic) -> GeoMultiPolygon {
    var polygons: [GeoPolygon] = []
    var children: [Int: [Int]] = [:]
    for (ringIdx, ring) in rings.enumerated() where ring.isHole {
        var parentSnakeIdx = ring.parentSnakeIdx
        var parentRingIdx: Int
        while true {
            guard let mapped = snakeIdxMap[parentSnakeIdx] else {
                throw GeoPanic("no ring for snake \(parentSnakeIdx)")
            }
            parentRingIdx = mapped
            let parent = try rings.checked(parentRingIdx)
            if !parent.isHole {
                break
            }
            parentSnakeIdx = parent.parentSnakeIdx
        }
        children[parentRingIdx, default: []].append(ringIdx)
    }

    for (ringIdx, ring) in rings.enumerated() where !ring.isHole {
        var holes: [GeoLineString] = []
        for childIdx in children.removeValue(forKey: ringIdx) ?? [] {
            let ls = try splitRing(rings[childIdx].ls) { holes.append($0) }
            holes.append(ls)
        }
        let exterior = try splitRing(ring.ls) { holes.append($0) }
        polygons.append(GeoPolygon(exterior, holes))
    }
    return GeoMultiPolygon(polygons)
}

/// `split_ring`: cuts a ring at every point it passes twice, reporting each cut-off loop to
/// `cb` and returning what is left.
private func splitRing(_ ls: GeoLineString, _ cb: (GeoLineString) -> Void) throws(GeoPanic) -> GeoLineString {
    var ptsMap: [SweepPoint: Int] = [:]
    var exterior: [GeoCoord] = []
    for coord in ls.coords {
        let key = SweepPoint(coord)
        // The Rust map is a `BTreeMap`, whose comparisons panic on NaN.
        if coord.x.isNaN || coord.y.isNaN {
            throw GeoPanic.unwrapNone
        }
        if let idx = ptsMap[key] {
            let drained = Array(exterior[idx...])
            exterior.removeSubrange(idx...)
            for pt in drained {
                if ptsMap.removeValue(forKey: SweepPoint(pt)) == nil {
                    throw GeoPanic.unwrapNone
                }
            }
            cb(GeoLineString(drained))
        }
        ptsMap[key] = exterior.count
        exterior.append(coord)
    }
    return GeoLineString(exterior)
}
