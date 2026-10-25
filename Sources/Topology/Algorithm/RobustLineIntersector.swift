/// The intersection of two segments, or of a point and a segment, decided by
/// robust orientations: JTS's `LineIntersector` with its one implementation,
/// `RobustLineIntersector`, as one value (only x and y: no z is
/// interpolated).
public struct RobustLineIntersector {
    public static let noIntersection = 0
    public static let pointIntersection = 1
    public static let collinearIntersection = 2

    public private(set) var result = 0
    var inputLines = Duo(Duo(Coordinate(0, 0), Coordinate(0, 0)), Duo(Coordinate(0, 0), Coordinate(0, 0)))
    public private(set) var intPt = Duo(Coordinate(0, 0), Coordinate(0, 0))
    var intLineIndex: Duo<Duo<Int>>?
    var isProperValue = false
    /// Rounds computed intersections to this model, when set.
    public var precisionModel: PrecisionModel?

    public init() {}

    /// A measure of where `p` is along `p0`-`p1`, monotone and exact: the
    /// larger ordinate difference from `p0`.
    public static func computeEdgeDistance(_ p: Coordinate, _ p0: Coordinate, _ p1: Coordinate) -> Double {
        let dx = abs(p1.x - p0.x)
        let dy = abs(p1.y - p0.y)
        var dist = -1.0
        if p == p0 {
            dist = 0.0
        } else if p == p1 {
            dist = dx > dy ? dx : dy
        } else {
            let pdx = abs(p.x - p0.x)
            let pdy = abs(p.y - p0.y)
            dist = dx > dy ? pdx : pdy
            if dist == 0.0 && p != p0 { dist = javaMax(pdx, pdy) }
        }
        precondition(!(dist == 0.0 && p != p0), "Bad distance calculation")
        return dist
    }

    public func getEndpoint(_ segmentIndex: Int, _ ptIndex: Int) -> Coordinate { inputLines[segmentIndex][ptIndex] }

    /// Whether the point `p` is on the segment `p1`-`p2`.
    public mutating func computeIntersection(_ p: Coordinate, _ p1: Coordinate, _ p2: Coordinate) {
        isProperValue = false
        if Envelope.intersects(p1, p2, p) {
            if Orientation.index(p1, p2, p) == 0 && Orientation.index(p2, p1, p) == 0 {
                isProperValue = true
                if p == p1 || p == p2 { isProperValue = false }
                result = RobustLineIntersector.pointIntersection
                return
            }
        }
        result = RobustLineIntersector.noIntersection
    }

    public mutating func computeIntersection(_ p1: Coordinate, _ p2: Coordinate, _ p3: Coordinate, _ p4: Coordinate) {
        inputLines[0][0] = p1
        inputLines[0][1] = p2
        inputLines[1][0] = p3
        inputLines[1][1] = p4
        result = computeIntersect(p1, p2, p3, p4)
    }

    public var isCollinear: Bool { result == RobustLineIntersector.collinearIntersection }
    public var isEndPoint: Bool { hasIntersection() && !isProperValue }
    public func hasIntersection() -> Bool { result != RobustLineIntersector.noIntersection }
    public func getIntersectionNum() -> Int { result }
    public func getIntersection(_ i: Int) -> Coordinate { intPt[i] }
    public func isProper() -> Bool { hasIntersection() && isProperValue }

    public func isIntersection(_ pt: Coordinate) -> Bool {
        for i in 0..<result where intPt[i].equals2D(pt) { return true }
        return false
    }

    public func isInteriorIntersection() -> Bool { isInteriorIntersection(0) || isInteriorIntersection(1) }

    public func isInteriorIntersection(_ inputLineIndex: Int) -> Bool {
        for i in 0..<result {
            if !(intPt[i].equals2D(inputLines[inputLineIndex][0]) || intPt[i].equals2D(inputLines[inputLineIndex][1])) {
                return true
            }
        }
        return false
    }

    /// As JTS, the order of the intersections along each segment is computed
    /// once, at the first call after the first intersection, and kept.
    public mutating func getIntersectionAlongSegment(_ segmentIndex: Int, _ intIndex: Int) -> Coordinate {
        computeIntLineIndex()
        return intPt[intLineIndex![segmentIndex][intIndex]]
    }

    public mutating func getIndexAlongSegment(_ segmentIndex: Int, _ intIndex: Int) -> Int {
        computeIntLineIndex()
        return intLineIndex![segmentIndex][intIndex]
    }

    mutating func computeIntLineIndex() {
        if intLineIndex == nil {
            intLineIndex = Duo(Duo(0, 0), Duo(0, 0))
            computeIntLineIndex(0)
            computeIntLineIndex(1)
        }
    }

    mutating func computeIntLineIndex(_ segmentIndex: Int) {
        let dist0 = getEdgeDistance(segmentIndex, 0)
        let dist1 = getEdgeDistance(segmentIndex, 1)
        if dist0 > dist1 {
            intLineIndex![segmentIndex] = Duo(0, 1)
        } else {
            intLineIndex![segmentIndex] = Duo(1, 0)
        }
    }

    public func getEdgeDistance(_ segmentIndex: Int, _ intIndex: Int) -> Double {
        RobustLineIntersector.computeEdgeDistance(intPt[intIndex], inputLines[segmentIndex][0], inputLines[segmentIndex][1])
    }

    // MARK: The robust computation

    mutating func computeIntersect(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Int {
        isProperValue = false
        if !Envelope.intersects(p1, p2, q1, q2) { return RobustLineIntersector.noIntersection }
        let pq1 = Orientation.index(p1, p2, q1)
        let pq2 = Orientation.index(p1, p2, q2)
        if (pq1 > 0 && pq2 > 0) || (pq1 < 0 && pq2 < 0) { return RobustLineIntersector.noIntersection }
        let qp1 = Orientation.index(q1, q2, p1)
        let qp2 = Orientation.index(q1, q2, p2)
        if (qp1 > 0 && qp2 > 0) || (qp1 < 0 && qp2 < 0) { return RobustLineIntersector.noIntersection }
        let collinear = pq1 == 0 && pq2 == 0 && qp1 == 0 && qp2 == 0
        if collinear { return computeCollinearIntersection(p1, p2, q1, q2) }
        var p: Coordinate
        if pq1 == 0 || pq2 == 0 || qp1 == 0 || qp2 == 0 {
            isProperValue = false
            if p1.equals2D(q1) {
                p = p1
            } else if p1.equals2D(q2) {
                p = p1
            } else if p2.equals2D(q1) {
                p = p2
            } else if p2.equals2D(q2) {
                p = p2
            } else if pq1 == 0 {
                p = q1
            } else if pq2 == 0 {
                p = q2
            } else if qp1 == 0 {
                p = p1
            } else {
                p = p2
            }
        } else {
            isProperValue = true
            p = intersection(p1, p2, q1, q2)
        }
        intPt[0] = p
        return RobustLineIntersector.pointIntersection
    }

    mutating func computeCollinearIntersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Int {
        let q1inP = Envelope.intersects(p1, p2, q1)
        let q2inP = Envelope.intersects(p1, p2, q2)
        let p1inQ = Envelope.intersects(q1, q2, p1)
        let p2inQ = Envelope.intersects(q1, q2, p2)
        let point = RobustLineIntersector.pointIntersection, collinear = RobustLineIntersector.collinearIntersection
        if q1inP && q2inP {
            intPt[0] = q1
            intPt[1] = q2
            return collinear
        }
        if p1inQ && p2inQ {
            intPt[0] = p1
            intPt[1] = p2
            return collinear
        }
        if q1inP && p1inQ {
            intPt[0] = q1
            intPt[1] = p1
            return q1 == p1 && !q2inP && !p2inQ ? point : collinear
        }
        if q1inP && p2inQ {
            intPt[0] = q1
            intPt[1] = p2
            return q1 == p2 && !q2inP && !p1inQ ? point : collinear
        }
        if q2inP && p1inQ {
            intPt[0] = q2
            intPt[1] = p1
            return q2 == p1 && !q1inP && !p2inQ ? point : collinear
        }
        if q2inP && p2inQ {
            intPt[0] = q2
            intPt[1] = p2
            return q2 == p2 && !q1inP && !p1inQ ? point : collinear
        }
        return RobustLineIntersector.noIntersection
    }

    func intersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Coordinate {
        var intPt = intersectionSafe(p1, p2, q1, q2)
        if !isInSegmentEnvelopes(intPt) { intPt = RobustLineIntersector.nearestEndpoint(p1, p2, q1, q2) }
        if let pm = precisionModel { intPt = pm.makePrecise(intPt) }
        return intPt
    }

    func intersectionSafe(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Coordinate {
        Intersection.intersection(p1, p2, q1, q2) ?? RobustLineIntersector.nearestEndpoint(p1, p2, q1, q2)
    }

    func isInSegmentEnvelopes(_ p: Coordinate) -> Bool {
        let env0 = Envelope(inputLines[0][0], inputLines[0][1])
        let env1 = Envelope(inputLines[1][0], inputLines[1][1])
        return env0.contains(p) && env1.contains(p)
    }

    static func nearestEndpoint(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Coordinate {
        var nearestPt = p1
        var minDist = Distance.pointToSegment(p1, q1, q2)
        var dist = Distance.pointToSegment(p2, q1, q2)
        if dist < minDist {
            minDist = dist
            nearestPt = p2
        }
        dist = Distance.pointToSegment(q1, p1, p2)
        if dist < minDist {
            minDist = dist
            nearestPt = q1
        }
        dist = Distance.pointToSegment(q2, p1, p2)
        if dist < minDist {
            minDist = dist
            nearestPt = q2
        }
        return nearestPt
    }
}

/// Two values indexed 0 and 1, held inline (the intersector's points and
/// input segments: arrays there cost an allocation and a uniqueness check
/// at every write).
public struct Duo<T> {
    public var first: T
    public var second: T

    public init(_ first: T, _ second: T) {
        self.first = first
        self.second = second
    }

    public subscript(i: Int) -> T {
        get { i == 0 ? first : second }
        set { if i == 0 { first = newValue } else { second = newValue } }
    }
}
