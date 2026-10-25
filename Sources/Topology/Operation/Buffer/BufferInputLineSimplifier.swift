/// Simplifies a line before it is offset: removes the vertices of shallow
/// concavities on the side the buffer grows to, which the buffer would fill
/// anyway, so it has fewer segments to node: JTS's
/// `BufferInputLineSimplifier`.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: the scan
/// starts at the second vertex for a ring too (JTS: the first), the sampled
/// test measures the middle vertex against the segments from the first to
/// each sampled one (JTS: each sampled vertex against the first and
/// middle), and the kept points are taken without repeats.
struct BufferInputLineSimplifier {
    private static let numPtsToCheck = 10

    private let inputLine: [Coordinate]
    private var distanceTol = 0.0
    private var isDeleted: [Bool]
    private var angleOrientation = Orientation.counterclockwise

    /// The line simplified within `distanceTol`, on the left for a positive
    /// tolerance and the right for a negative one.
    static func simplify(_ inputLine: [Coordinate], _ distanceTol: Double) -> [Coordinate] {
        var simp = BufferInputLineSimplifier(inputLine)
        return simp.simplify(distanceTol)
    }

    private init(_ inputLine: [Coordinate]) {
        self.inputLine = inputLine
        isDeleted = [Bool](repeating: false, count: inputLine.count)
    }

    private mutating func simplify(_ distanceTol: Double) -> [Coordinate] {
        self.distanceTol = abs(distanceTol)
        if distanceTol < 0 { angleOrientation = Orientation.clockwise }
        while deleteShallowConcavities() {}
        return collapseLine()
    }

    /// One pass over the line, deleting each middle vertex that may go.
    private mutating func deleteShallowConcavities() -> Bool {
        var index = 1
        var midIndex = nextIndex(index)
        var lastIndex = nextIndex(midIndex)
        var isChanged = false
        while lastIndex < inputLine.count {
            var isMiddleVertexDeleted = false
            if isDeletable(index, midIndex, lastIndex) {
                isDeleted[midIndex] = true
                isMiddleVertexDeleted = true
                isChanged = true
            }
            index = isMiddleVertexDeleted ? lastIndex : midIndex
            midIndex = nextIndex(index)
            lastIndex = nextIndex(midIndex)
        }
        return isChanged
    }

    private func nextIndex(_ index: Int) -> Int {
        var next = index + 1
        while next < inputLine.count && isDeleted[next] { next += 1 }
        return next
    }

    private func collapseLine() -> [Coordinate] {
        var coordList: [Coordinate] = []
        for i in inputLine.indices where !isDeleted[i] {
            if let last = coordList.last, last.equals2D(inputLine[i]) { continue }
            coordList.append(inputLine[i])
        }
        return coordList
    }

    private func isDeletable(_ i0: Int, _ i1: Int, _ i2: Int) -> Bool {
        let p0 = inputLine[i0], p1 = inputLine[i1], p2 = inputLine[i2]
        if !isConcave(p0, p1, p2) { return false }
        if !isShallow(p0, p1, p2) { return false }
        return isShallowSampled(p0, p1, i0, i2)
    }

    private func isShallowSampled(_ p0: Coordinate, _ p2: Coordinate, _ i0: Int, _ i2: Int) -> Bool {
        var inc = (i2 - i0) / BufferInputLineSimplifier.numPtsToCheck
        if inc <= 0 { inc = 1 }
        for i in stride(from: i0, to: i2, by: inc) where !isShallow(p0, p2, inputLine[i]) { return false }
        return true
    }

    /// Whether `p1` is within the tolerance of the segment `p0`-`p2`.
    private func isShallow(_ p0: Coordinate, _ p1: Coordinate, _ p2: Coordinate) -> Bool {
        Distance.pointToSegment(p1, p0, p2) < distanceTol
    }

    private func isConcave(_ p0: Coordinate, _ p1: Coordinate, _ p2: Coordinate) -> Bool {
        Orientation.index(p0, p1, p2) == angleOrientation
    }
}
