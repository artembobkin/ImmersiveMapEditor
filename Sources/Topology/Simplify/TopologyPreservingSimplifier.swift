/// Simplifies a geometry with Douglas-Peucker while keeping its topology
/// (no new intersections, rings keeping their points on the right side of
/// other components): JTS's `TopologyPreservingSimplifier` with
/// `TaggedLinesSimplifier`, `TaggedLineStringSimplifier`, `TaggedLineString`,
/// `TaggedLineSegment`, `LineSegmentIndex` and `ComponentJumpChecker`.
///
/// As GEOS 3.13 runs it (`GEOSTopologyPreserveSimplify`): the lines are
/// simplified in the order of the geometry's components (JTS: a `HashMap`'s
/// order), a segment kept as it is enters the result as a copy, so taking
/// a ring's end point out removes from the indexes only the segments
/// themselves (by identity; JTS removes equal segments), and the result is
/// rebuilt by GEOS's transformer.
public final class TopologyPreservingSimplifier {
    public static func simplify(_ geom: Geometry, _ distanceTolerance: Double) throws -> Geometry {
        let tss = TopologyPreservingSimplifier(geom)
        try tss.setDistanceTolerance(distanceTolerance)
        return try tss.getResultGeometry()
    }

    let inputGeom: Geometry
    @exclusivity(unchecked) var distanceTolerance = 0.0

    public init(_ inputGeom: Geometry) { self.inputGeom = inputGeom }

    public func setDistanceTolerance(_ distanceTolerance: Double) throws {
        if distanceTolerance < 0.0 { throw IllegalArgumentException("Tolerance must be non-negative") }
        self.distanceTolerance = distanceTolerance
    }

    public func getResultGeometry() throws -> Geometry {
        if inputGeom.isEmpty() { return inputGeom.copy() }
        var lines: [TaggedLineString] = []
        var map: [ObjectIdentifier: TaggedLineString] = [:]
        inputGeom.applyComponents { g in
            guard let line = g as? LineString, !line.isEmpty() else { return }
            let minSize = line.isClosed() ? 4 : 2
            let tagged = TaggedLineString(line, minSize, line is LinearRing)
            map[ObjectIdentifier(line)] = tagged
            lines.append(tagged)
        }
        try TaggedLinesSimplifier(distanceTolerance).simplify(lines)
        return try LineStringTransformer(map).transform(inputGeom)
    }

    /// Rebuilds the geometry with each line's simplified coordinates.
    final class LineStringTransformer: GeometryTransformer {
        let linestringMap: [ObjectIdentifier: TaggedLineString]

        init(_ map: [ObjectIdentifier: TaggedLineString]) { linestringMap = map }

        override func transformCoordinates(_ coords: [Coordinate], _ parent: Geometry) throws -> [Coordinate]? {
            if coords.isEmpty { return nil }
            if parent is LineString { return linestringMap[ObjectIdentifier(parent)]!.getResultCoordinates() }
            return try super.transformCoordinates(coords, parent)
        }
    }
}

/// A segment of an input line, with the line and its index in it: JTS's
/// `TaggedLineSegment`, a class (the indexes keep segments by identity).
final class TaggedLineSegment {
    @exclusivity(unchecked) var p0: Coordinate
    @exclusivity(unchecked) var p1: Coordinate
    /// The line it belongs to (nil for a segment made by simplifying).
    unowned(unsafe) let parent: LineString?
    let index: Int
    /// Whether it is in the input index now.
    @exclusivity(unchecked) var inInputIndex = false
    /// Whether it is in the output index now.
    @exclusivity(unchecked) var inOutputIndex = false
    /// The last query of each index that saw it.
    @exclusivity(unchecked) var inputStamp = 0
    @exclusivity(unchecked) var outputStamp = 0

    init(_ p0: Coordinate, _ p1: Coordinate, _ parent: LineString? = nil, _ index: Int = -1) {
        self.p0 = p0
        self.p1 = p1
        self.parent = parent
        self.index = index
    }

    convenience init(copying s: TaggedLineSegment) { self.init(s.p0, s.p1, s.parent, s.index) }

    var segment: LineSegment { LineSegment(p0, p1) }
}

/// A line with its segments and the segments of its simplified result:
/// JTS's `TaggedLineString`.
final class TaggedLineString {
    let parentLine: LineString
    @exclusivity(unchecked) private(set) var segs: [TaggedLineSegment] = []
    @exclusivity(unchecked) var resultSegs: [TaggedLineSegment] = []
    let minimumSize: Int
    let isRing: Bool

    init(_ parentLine: LineString, _ minimumSize: Int, _ isRing: Bool) {
        self.parentLine = parentLine
        self.minimumSize = minimumSize
        self.isRing = isRing
        let pts = parentLine.points
        if !pts.isEmpty {
            for i in 0..<(pts.count - 1) { segs.append(TaggedLineSegment(pts[i], pts[i + 1], parentLine, i)) }
        }
    }

    func getParentCoordinates() -> [Coordinate] { parentLine.points }
    func getCoordinate(_ i: Int) -> Coordinate { parentLine.points[i] }
    func getComponentPoint() -> Coordinate { parentLine.points[1] }
    func getResultSize() -> Int { resultSegs.isEmpty ? 0 : resultSegs.count + 1 }
    func getSegment(_ i: Int) -> TaggedLineSegment { segs[i] }
    func addToResult(_ seg: TaggedLineSegment) { resultSegs.append(seg) }

    func getResultCoordinates() -> [Coordinate] {
        guard let last = resultSegs.last else { return [] }
        var pts = resultSegs.map(\.p0)
        pts.append(last.p1)
        return pts
    }

    /// Joins the last result segment into the first, taking the ring's end
    /// point out.
    func removeRingEndpoint() -> TaggedLineSegment {
        let firstSeg = resultSegs[0]
        let lastSeg = resultSegs[resultSegs.count - 1]
        firstSeg.p0 = lastSeg.p0
        resultSegs.removeLast()
        return firstSeg
    }
}

/// The segments of the input or of the output, found by the envelope of a
/// query segment: JTS's `LineSegmentIndex`. JTS and GEOS keep them in a
/// quadtree and filter what it finds by envelope; every use of the result
/// asks only whether one of them intersects badly, so the order does not
/// matter, and the port keeps them in a uniform grid over the input's
/// envelope (by identity, as GEOS removes them).
final class LineSegmentIndex {
    private let isInput: Bool
    private let frame: Envelope
    private let nx: Int, ny: Int
    private let cellW: Double, cellH: Double
    @exclusivity(unchecked) private var cells: [[TaggedLineSegment]]
    /// A query's mark, so a segment in several cells is seen once.
    @exclusivity(unchecked) private var stamp = 0

    init(input: Bool, frame: Envelope, count: Int) {
        isInput = input
        self.frame = frame
        let side = max(1, min(256, Int(Double(count / 2).squareRoot())))
        nx = frame.width > 0 ? side : 1
        ny = frame.height > 0 ? side : 1
        cellW = frame.width > 0 ? frame.width / Double(nx) : 1
        cellH = frame.height > 0 ? frame.height / Double(ny) : 1
        cells = Array(repeating: [], count: nx * ny)
    }

    private func cellX(_ x: Double) -> Int { min(nx - 1, max(0, Int((x - frame.minX) / cellW))) }
    private func cellY(_ y: Double) -> Int { min(ny - 1, max(0, Int((y - frame.minY) / cellH))) }

    func add(_ line: TaggedLineString) throws {
        for seg in line.segs { try add(seg) }
    }

    /// Throws on a segment of a non-finite envelope, as GEOS's quadtree does.
    func add(_ seg: TaggedLineSegment) throws {
        if !(seg.p0.x.isFinite && seg.p0.y.isFinite && seg.p1.x.isFinite && seg.p1.y.isFinite) {
            throw IllegalArgumentException("Non-finite envelope bounds passed to index insert")
        }
        if isInput { seg.inInputIndex = true } else { seg.inOutputIndex = true }
        let x0 = cellX(min(seg.p0.x, seg.p1.x)), x1 = cellX(max(seg.p0.x, seg.p1.x))
        let y0 = cellY(min(seg.p0.y, seg.p1.y)), y1 = cellY(max(seg.p0.y, seg.p1.y))
        for j in y0...y1 {
            for i in x0...x1 { cells[j * nx + i].append(seg) }
        }
    }

    func remove(_ seg: TaggedLineSegment) {
        if isInput { seg.inInputIndex = false } else { seg.inOutputIndex = false }
    }

    /// Calls `f` with every segment in the index whose envelope meets the
    /// query segment's, until it returns true; whether one did.
    func contains(_ query: LineSegment, where f: (TaggedLineSegment) -> Bool) -> Bool {
        stamp += 1
        let x0 = cellX(min(query.p0.x, query.p1.x)), x1 = cellX(max(query.p0.x, query.p1.x))
        let y0 = cellY(min(query.p0.y, query.p1.y)), y1 = cellY(max(query.p0.y, query.p1.y))
        for j in y0...y1 {
            for i in x0...x1 {
                for s in cells[j * nx + i] {
                    guard isInput ? s.inInputIndex : s.inOutputIndex else { continue }
                    if isInput {
                        if s.inputStamp == stamp { continue }
                        s.inputStamp = stamp
                    } else {
                        if s.outputStamp == stamp { continue }
                        s.outputStamp = stamp
                    }
                    if Envelope.intersects(s.p0, s.p1, query.p0, query.p1) && f(s) { return true }
                }
            }
        }
        return false
    }
}

/// Simplifies the tagged lines in order, sharing the indexes: JTS's
/// `TaggedLinesSimplifier`.
struct TaggedLinesSimplifier {
    let distanceTolerance: Double

    init(_ distanceTolerance: Double) { self.distanceTolerance = distanceTolerance }

    func simplify(_ taggedLines: [TaggedLineString]) throws {
        var frame = Envelope()
        var count = 0
        for t in taggedLines {
            for p in t.parentLine.points where p.x.isFinite && p.y.isFinite { frame.expandToInclude(p) }
            count += t.segs.count
        }
        let inputIndex = LineSegmentIndex(input: true, frame: frame, count: count)
        let outputIndex = LineSegmentIndex(input: false, frame: frame, count: count)
        let jumpChecker = ComponentJumpChecker(taggedLines)
        for t in taggedLines { try inputIndex.add(t) }
        for t in taggedLines {
            var tlss = TaggedLineStringSimplifier(inputIndex, outputIndex, jumpChecker)
            try tlss.simplify(t, distanceTolerance)
        }
    }
}

/// Simplifies one line, testing each flattened section against the other
/// segments: JTS's `TaggedLineStringSimplifier`.
struct TaggedLineStringSimplifier {
    var li = RobustLineIntersector()
    let inputIndex: LineSegmentIndex
    let outputIndex: LineSegmentIndex
    let jumpChecker: ComponentJumpChecker
    var line: TaggedLineString!
    var linePts: [Coordinate] = []

    init(_ inputIndex: LineSegmentIndex, _ outputIndex: LineSegmentIndex, _ jumpChecker: ComponentJumpChecker) {
        self.inputIndex = inputIndex
        self.outputIndex = outputIndex
        self.jumpChecker = jumpChecker
    }

    mutating func simplify(_ line: TaggedLineString, _ distanceTolerance: Double) throws {
        self.line = line
        linePts = line.getParentCoordinates()
        if linePts.isEmpty { return }
        try simplifySection(0, linePts.count - 1, 0, distanceTolerance)
        if line.isRing && CoordinateSequences.isRing(linePts) { try simplifyRingEndpoint(distanceTolerance) }
    }

    private mutating func simplifySection(_ i: Int, _ j: Int, _ depth: Int, _ distanceTolerance: Double) throws {
        let depth = depth + 1
        if i + 1 == j {
            line.addToResult(TaggedLineSegment(copying: line.getSegment(i)))
            return
        }
        var isValidToSimplify = true
        // Following the start of the line, a section may not be flattened
        // below the line's minimum size.
        if line.getResultSize() < line.minimumSize {
            let worstCaseSize = depth + 1
            if worstCaseSize < line.minimumSize { isValidToSimplify = false }
        }
        let (furthestPtIndex, distance) = TaggedLineStringSimplifier.findFurthestPoint(linePts, i, j)
        // No points between (GEOS): the section's segments are kept.
        if distance < 0 {
            for k in i..<j { line.addToResult(TaggedLineSegment(copying: line.getSegment(k))) }
            return
        }
        if distance > distanceTolerance { isValidToSimplify = false }
        if isValidToSimplify {
            let flatSeg = LineSegment(linePts[i], linePts[j])
            isValidToSimplify = isTopologyValid(line, i, j, flatSeg)
        }
        if isValidToSimplify {
            line.addToResult(try flatten(i, j))
            return
        }
        try simplifySection(i, furthestPtIndex, depth, distanceTolerance)
        try simplifySection(furthestPtIndex, j, depth, distanceTolerance)
    }

    private mutating func simplifyRingEndpoint(_ distanceTolerance: Double) throws {
        guard line.getResultSize() > line.minimumSize else { return }
        let firstSeg = line.resultSegs[0]
        let lastSeg = line.resultSegs[line.resultSegs.count - 1]
        let simpSeg = LineSegment(lastSeg.p0, firstSeg.p1)
        let endPt = firstSeg.p0
        if simpSeg.distance(endPt) <= distanceTolerance && isTopologyValid(line, firstSeg.segment, lastSeg.segment, simpSeg) {
            inputIndex.remove(firstSeg)
            inputIndex.remove(lastSeg)
            outputIndex.remove(firstSeg)
            outputIndex.remove(lastSeg)
            let flatSeg = line.removeRingEndpoint()
            try outputIndex.add(flatSeg)
        }
    }

    private static func findFurthestPoint(_ pts: [Coordinate], _ i: Int, _ j: Int) -> (Int, Double) {
        let seg = LineSegment(pts[i], pts[j])
        var maxDist = -1.0
        var maxIndex = i
        var k = i + 1
        while k < j {
            let distance = seg.distance(pts[k])
            if distance > maxDist {
                maxDist = distance
                maxIndex = k
            }
            k += 1
        }
        return (maxIndex, maxDist)
    }

    private func flatten(_ start: Int, _ end: Int) throws -> TaggedLineSegment {
        let newSeg = TaggedLineSegment(linePts[start], linePts[end])
        try outputIndex.add(newSeg)
        for i in start..<end { inputIndex.remove(line.getSegment(i)) }
        return newSeg
    }

    private mutating func isTopologyValid(_ line: TaggedLineString, _ sectionStart: Int, _ sectionEnd: Int, _ flatSeg: LineSegment) -> Bool {
        if hasOutputIntersection(flatSeg) { return false }
        if hasInputIntersection(line, sectionStart, sectionEnd, flatSeg) { return false }
        if jumpChecker.hasJump(line, sectionStart, sectionEnd, flatSeg) { return false }
        return true
    }

    private mutating func isTopologyValid(_ line: TaggedLineString, _ seg1: LineSegment, _ seg2: LineSegment, _ flatSeg: LineSegment) -> Bool {
        // Removing a collinear end point leaves the topology as it is.
        if Orientation.collinear == flatSeg.orientationIndex(seg1.p0) { return true }
        if hasOutputIntersection(flatSeg) { return false }
        if hasInputIntersection(nil, 0, 0, flatSeg) { return false }
        if jumpChecker.hasJump(line, seg1, seg2, flatSeg) { return false }
        return true
    }

    private mutating func hasOutputIntersection(_ flatSeg: LineSegment) -> Bool {
        var li = self.li
        defer { self.li = li }
        return outputIndex.contains(flatSeg) { TaggedLineStringSimplifier.hasInvalidIntersection(&li, $0.segment, flatSeg) }
    }

    private mutating func hasInputIntersection(_ parentLine: TaggedLineString?, _ excludeStart: Int, _ excludeEnd: Int, _ flatSeg: LineSegment) -> Bool {
        var li = self.li
        defer { self.li = li }
        let current = line!
        return inputIndex.contains(flatSeg) { querySeg in
            if TaggedLineStringSimplifier.hasInvalidIntersection(&li, querySeg.segment, flatSeg) {
                if parentLine != nil && TaggedLineStringSimplifier.isInLineSection(current, excludeStart, excludeEnd, querySeg) { return false }
                return true
            }
            return false
        }
    }

    private static func isInLineSection(_ line: TaggedLineString, _ excludeStart: Int, _ excludeEnd: Int, _ seg: TaggedLineSegment) -> Bool {
        if seg.parent !== line.parentLine { return false }
        let segIndex = seg.index
        if excludeStart <= excludeEnd {
            if segIndex >= excludeStart && segIndex < excludeEnd { return true }
        } else {
            if segIndex >= excludeStart || segIndex <= excludeEnd { return true }
        }
        return false
    }

    private static func hasInvalidIntersection(_ li: inout RobustLineIntersector, _ seg0: LineSegment, _ seg1: LineSegment) -> Bool {
        if seg0.equalsTopo(seg1) { return true }
        li.computeIntersection(seg0.p0, seg0.p1, seg1.p0, seg1.p1)
        return li.isInteriorIntersection()
    }
}

/// Whether simplifying a section moves it across the point of another
/// component (which would change their topology): JTS's `ComponentJumpChecker`.
struct ComponentJumpChecker {
    let components: [TaggedLineString]

    init(_ taggedLines: [TaggedLineString]) { components = taggedLines }

    func hasJump(_ line: TaggedLineString, _ start: Int, _ end: Int, _ seg: LineSegment) -> Bool {
        var sectionEnv = Envelope()
        for i in start...end { sectionEnv.expandToInclude(line.getCoordinate(i)) }
        for comp in components where comp !== line {
            let compPt = comp.getComponentPoint()
            if sectionEnv.intersects(compPt) {
                var rcc = RayCrossingCounter(compPt)
                for i in start..<end { rcc.countSegment(line.getCoordinate(i), line.getCoordinate(i + 1)) }
                if rcc.count % 2 != ComponentJumpChecker.crossingCount(compPt, seg) % 2 { return true }
            }
        }
        return false
    }

    func hasJump(_ line: TaggedLineString, _ seg1: LineSegment, _ seg2: LineSegment, _ seg: LineSegment) -> Bool {
        var sectionEnv = Envelope()
        sectionEnv.expandToInclude(seg1.p0)
        sectionEnv.expandToInclude(seg1.p1)
        sectionEnv.expandToInclude(seg2.p0)
        sectionEnv.expandToInclude(seg2.p1)
        for comp in components where comp !== line {
            let compPt = comp.getComponentPoint()
            if sectionEnv.intersects(compPt) {
                var rcc = RayCrossingCounter(compPt)
                rcc.countSegment(seg1.p0, seg1.p1)
                rcc.countSegment(seg2.p0, seg2.p1)
                if rcc.count % 2 != ComponentJumpChecker.crossingCount(compPt, seg) % 2 { return true }
            }
        }
        return false
    }

    static func crossingCount(_ compPt: Coordinate, _ seg: LineSegment) -> Int {
        var rcc = RayCrossingCounter(compPt)
        rcc.countSegment(seg.p0, seg.p1)
        return rcc.count
    }
}

extension Geometry {
    /// The geometry simplified keeping its topology (`GEOSTopologyPreserveSimplify`).
    public func topologyPreserveSimplify(_ tolerance: Double) throws -> Geometry {
        try NonFinite.scope { try TopologyPreservingSimplifier.simplify(self, tolerance) }
    }
}
