/// The snakes of geo's region assembly: monotone chains of output edges started in pairs at a
/// sweep point, and `into_ring`, which walks a cycle of snakes (forwards, then backwards, in
/// turn) into one ring and decides from its winding whether it is a hole.

struct Snake {
    var points: [SweepPoint]
    let startPair: Int
    var endPair: Int?
    let region: GeoWindingOrder
    let parentSnakeIdx: Int

    init(start: SweepPoint, end: SweepPoint, pair: Int, region: GeoWindingOrder, parentSnakeIdx: Int) {
        self.points = [start, end]
        self.startPair = pair
        self.endPair = nil
        self.region = region
        self.parentSnakeIdx = parentSnakeIdx
    }

    mutating func push(_ right: SweepPoint) {
        points.append(right)
    }

    mutating func finish(_ other: Int) {
        endPair = other
    }
}

struct AssemblyRing {
    let ls: GeoLineString
    let isHole: Bool
    let parentSnakeIdx: Int
}

/// `Snake::into_ring`: the ring through the snake at `startIdx`, draining the snakes it visits,
/// or `nil` if that snake was already drained. `visited` receives each snake index walked.
private func snakeIntoRing(
    _ slice: inout [Snake], _ startIdx: Int, _ visited: inout [Int]
) throws(GeoPanic) -> AssemblyRing? {
    var output: [GeoCoord] = []
    var idx = startIdx
    var atStart = true

    let el = slice[idx]
    if el.points.isEmpty {
        return nil
    }
    let lastEl = try slice.checked(el.startPair)
    let startL = LineOrPoint.new(el.points[0], el.points[1])
    let endL = LineOrPoint.new(el.points[0], try lastEl.points.checked(1))
    guard let ordering = startL.partialCmp(endL) else { throw GeoPanic.unwrapNone }
    let lsWinding: GeoWindingOrder
    switch ordering {
    case .less: lsWinding = .counterClockwise
    case .greater: lsWinding = .clockwise
    case .equal: throw GeoPanic.unreachable
    }
    let parentSnakeIdx = el.parentSnakeIdx
    let isHole = el.region != lsWinding

    while true {
        try checkIndex(idx, slice.count)
        let current = slice[idx]
        visited.append(idx)
        let pts = current.points
        slice[idx].points = []
        if atStart {
            guard let endPair = current.endPair else { throw GeoPanic.unwrapNone }
            idx = endPair
            output.append(contentsOf: pts.dropFirst().map(\.coord))
        } else {
            idx = current.startPair
            output.append(contentsOf: pts.reversed().dropFirst().map(\.coord))
        }
        atStart.toggle()
        if idx == startIdx {
            break
        }
    }

    return AssemblyRing(ls: GeoLineString(output), isHole: isHole, parentSnakeIdx: parentSnakeIdx)
}

/// `rings_from_snakes`: every ring, and for each snake the index of the ring it ended up in.
func ringsFromSnakes(_ snakes: inout [Snake]) throws(GeoPanic) -> ([AssemblyRing], [Int: Int]) {
    var snakeIdxMap: [Int: Int] = [:]
    var rings: [AssemblyRing] = []
    for idx in 0..<snakes.count {
        var visited: [Int] = []
        if let ring = try snakeIntoRing(&snakes, idx, &visited) {
            // The callback of `into_ring` maps each visited snake to the ring about to be pushed.
            for midx in visited {
                snakeIdxMap[midx] = rings.count
            }
            rings.append(ring)
        }
    }
    return (rings, snakeIdxMap)
}
