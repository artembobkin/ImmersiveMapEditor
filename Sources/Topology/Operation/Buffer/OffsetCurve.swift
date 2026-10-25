/// The offset curve of a geometry: the lines at a distance to the left of
/// each line (right for a negative distance), the parts of the raw offset
/// curve that lie on the line's buffer; for a polygon, the boundary of its
/// buffer: JTS's `OffsetCurve`, `OffsetCurveSection` and `SegmentMCIndex`,
/// as GEOS 3.13's `GEOSOffsetCurve` runs them.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: the raw
/// offset curve is taken closed (`OffsetCurveBuilder`), a segment of the
/// buffer matches a raw segment when both its ends are within the match
/// distance of it (JTS tests the shorter segment's ends against the longer
/// one), only polygons are looked at for the buffer's largest, and the
/// sections are sorted by libc++'s `std::sort`. The joined form of JTS
/// (`getCurveJoined`) is not ported.
public final class OffsetCurve {
    private static let matchDistanceFactor = 10000.0
    private static let minQuadrantSegments = 8
    private static let notInCurve = -1.0

    private let inputGeom: Geometry
    private let distance: Double
    @exclusivity(unchecked) private var bufferParams = BufferParameters()
    private let matchDistance: Double
    private let geomFactory: GeometryFactory

    public init(_ geom: Geometry, _ distance: Double, _ bufParams: BufferParameters? = nil) {
        inputGeom = geom
        self.distance = distance
        matchDistance = abs(distance) / OffsetCurve.matchDistanceFactor
        geomFactory = geom.factory
        if let bufParams {
            bufferParams.quadrantSegments = max(bufParams.quadrantSegments, OffsetCurve.minQuadrantSegments)
            bufferParams.joinStyle = bufParams.joinStyle
            bufferParams.mitreLimit = bufParams.mitreLimit
        }
    }

    /// The curve as `GEOSOffsetCurve` takes its parameters: a negative
    /// segment count, join style or mitre limit leaves the default.
    public static func getCurve(_ geom: Geometry, _ distance: Double, quadSegs: Int, joinStyle: Int, mitreLimit: Double) throws -> Geometry {
        var p = BufferParameters()
        if quadSegs >= 0 { p.quadrantSegments = quadSegs }
        if joinStyle >= 0 { p.joinStyle = joinStyle }
        if mitreLimit >= 0 { p.mitreLimit = mitreLimit }
        return try OffsetCurve(geom, distance, p).getCurve()
    }

    public func getCurve() throws -> Geometry {
        try GeometryMapper.flatMap(inputGeom, 1) { geom in
            if geom is Point { return nil }
            if geom is Polygon { return try BufferOp.bufferOp(geom, distance).getBoundary() }
            return try computeCurve(geom as! LineString, distance)
        }
    }

    /// The raw offset curve of a line: every segment offset and joined,
    /// with no regard to where it crosses itself.
    static func rawOffsetCurve(_ line: LineString, _ distance: Double, _ bufParams: BufferParameters) throws -> [Coordinate] {
        let cleanPts = BufferCurveSetBuilder.clean(line.points)
        let ocb = OffsetCurveBuilder(line.factory.precisionModel, bufParams)
        return try ocb.getOffsetCurve(cleanPts, distance) ?? []
    }

    private func computeCurve(_ lineGeom: LineString, _ distance: Double) throws -> Geometry {
        if lineGeom.getNumPoints() < 2 || lineGeom.getLength() == 0.0 { return geomFactory.createLineString() }
        if distance == 0 { return lineGeom.copy() }
        if lineGeom.getNumPoints() == 2 { return try offsetSegment(lineGeom.points, distance) }
        var sections = try computeSections(lineGeom, distance)
        return OffsetCurveSection.toGeometry(&sections, geomFactory)
    }

    private func computeSections(_ lineGeom: LineString, _ distance: Double) throws -> [OffsetCurveSection] {
        let rawCurve = try OffsetCurve.rawOffsetCurve(lineGeom, distance, bufferParams)
        var sections: [OffsetCurveSection] = []
        if rawCurve.isEmpty { return sections }
        let bufferPoly = try getBufferOriented(lineGeom, distance, bufferParams)
        computeCurveSections(bufferPoly.shell.points, rawCurve, &sections)
        for hole in bufferPoly.holes { computeCurveSections(hole.points, rawCurve, &sections) }
        return sections
    }

    private func offsetSegment(_ pts: [Coordinate], _ distance: Double) throws -> LineString {
        let offsetSeg = try LineSegment(pts[0], pts[1]).offset(distance)
        return geomFactory.createLineString([offsetSeg.p0, offsetSeg.p1])
    }

    /// The largest polygon of the line's buffer, its rings reversed for a
    /// negative distance (so it runs the way the raw curve does).
    private func getBufferOriented(_ geom: LineString, _ distance: Double, _ bufParams: BufferParameters) throws -> Polygon {
        let buffer = try BufferOp.bufferOp(geom, abs(distance), bufParams)
        let bufferPoly = OffsetCurve.extractMaxAreaPolygon(buffer)!
        return distance < 0 ? bufferPoly.reverse() as! Polygon : bufferPoly
    }

    private static func extractMaxAreaPolygon(_ geom: Geometry) -> Polygon? {
        if let p = geom as? Polygon { return p }
        var maxArea = 0.0
        var maxPoly: Polygon?
        for i in 0..<geom.getNumGeometries() {
            guard let poly = geom.getGeometryN(i) as? Polygon else { continue }
            let area = poly.getArea()
            if maxPoly == nil || area > maxArea {
                maxPoly = poly
                maxArea = area
            }
        }
        return maxPoly
    }

    /// The sections of a buffer ring that lie on the raw curve, each with
    /// its position along the raw curve.
    private func computeCurveSections(_ bufferRingPts: [Coordinate], _ rawCurve: [Coordinate], _ sections: inout [OffsetCurveSection]) {
        var rawPosition = [Double](repeating: OffsetCurve.notInCurve, count: bufferRingPts.count - 1)
        let bufferSegIndex = SegmentMCIndex(bufferRingPts)
        var bufferFirstIndex = -1
        var minRawPosition = -1.0
        for i in 0..<(rawCurve.count - 1) {
            let minBufferIndexForSeg = matchSegments(rawCurve[i], rawCurve[i + 1], i, bufferSegIndex, bufferRingPts, &rawPosition)
            if minBufferIndexForSeg >= 0 {
                let pos = rawPosition[minBufferIndexForSeg]
                if bufferFirstIndex < 0 || pos < minRawPosition {
                    minRawPosition = pos
                    bufferFirstIndex = minBufferIndexForSeg
                }
            }
        }
        if bufferFirstIndex < 0 { return }
        extractSections(bufferRingPts, rawPosition, bufferFirstIndex, &sections)
    }

    /// Marks the buffer segments matching a raw segment with their raw
    /// position, and gives the one of least position (-1 for none).
    private func matchSegments(_ raw0: Coordinate, _ raw1: Coordinate, _ rawCurveIndex: Int, _ bufferSegIndex: SegmentMCIndex,
                               _ bufferPts: [Coordinate], _ rawCurvePos: inout [Double]) -> Int {
        var matchEnv = Envelope(raw0, raw1)
        matchEnv.expandBy(matchDistance)
        var minRawLocation = -1.0
        var bufferRingMinIndex = -1
        bufferSegIndex.query(matchEnv) { _, segIndex in
            let frac = OffsetCurve.segmentMatchFrac(bufferPts[segIndex], bufferPts[segIndex + 1], raw0, raw1, matchDistance)
            if frac < 0 { return }
            let location = Double(rawCurveIndex) + frac
            rawCurvePos[segIndex] = location
            if minRawLocation < 0 || location < minRawLocation {
                minRawLocation = location
                bufferRingMinIndex = segIndex
            }
        }
        return bufferRingMinIndex
    }

    /// Where along the raw segment the buffer segment starts, -1 when the
    /// buffer segment is not on it.
    private static func segmentMatchFrac(_ p0: Coordinate, _ p1: Coordinate, _ seg0: Coordinate, _ seg1: Coordinate,
                                         _ matchDistance: Double) -> Double {
        if matchDistance < Distance.pointToSegment(p0, seg0, seg1) { return -1.0 }
        if matchDistance < Distance.pointToSegment(p1, seg0, seg1) { return -1.0 }
        return LineSegment(seg0, seg1).segmentFraction(p0)
    }

    private func extractSections(_ ringPts: [Coordinate], _ rawCurveLoc: [Double], _ startIndex: Int,
                                 _ sections: inout [OffsetCurveSection]) {
        var sectionStart = startIndex
        var sectionEnd: Int
        repeat {
            sectionEnd = findSectionEnd(rawCurveLoc, sectionStart, startIndex)
            let location = rawCurveLoc[sectionStart]
            let lastIndex = OffsetCurve.prevIndex(sectionEnd, rawCurveLoc.count)
            let lastLoc = rawCurveLoc[lastIndex]
            sections.append(OffsetCurveSection.create(ringPts, sectionStart, sectionEnd, location, lastLoc))
            sectionStart = findSectionStart(rawCurveLoc, sectionEnd)
        } while sectionStart != startIndex && sectionEnd != startIndex
    }

    private func findSectionStart(_ loc: [Double], _ end: Int) -> Int {
        var start = end
        repeat {
            let next = OffsetCurve.nextIndex(start, loc.count)
            if loc[start] == OffsetCurve.notInCurve {
                start = next
                continue
            }
            let prev = OffsetCurve.prevIndex(start, loc.count)
            if loc[prev] == OffsetCurve.notInCurve { return start }
            start = next
        } while start != end
        return start
    }

    private func findSectionEnd(_ loc: [Double], _ start: Int, _ firstStartIndex: Int) -> Int {
        var end = start
        repeat {
            let next = OffsetCurve.nextIndex(end, loc.count)
            if loc[next] == OffsetCurve.notInCurve { return next }
            end = next
        } while end != start && end != firstStartIndex
        return end
    }

    private static func nextIndex(_ i: Int, _ size: Int) -> Int { i >= size - 1 ? 0 : i + 1 }
    private static func prevIndex(_ i: Int, _ size: Int) -> Int { i == 0 ? size - 1 : i - 1 }
}

/// A section of a buffer ring on the raw offset curve, with its position
/// along the raw curve.
struct OffsetCurveSection {
    let sectionPts: [Coordinate]
    let location: Double
    let locLast: Double

    static func create(_ srcPts: [Coordinate], _ start: Int, _ end: Int, _ loc: Double, _ locLast: Double) -> OffsetCurveSection {
        let len = end <= start ? srcPts.count - start + end : end - start + 1
        let pts = (0..<len).map { srcPts[(start + $0) % (srcPts.count - 1)] }
        return OffsetCurveSection(sectionPts: pts, location: loc, locLast: locLast)
    }

    /// The sections as lines in their order along the raw curve.
    static func toGeometry(_ sections: inout [OffsetCurveSection], _ geomFactory: GeometryFactory) -> Geometry {
        if sections.isEmpty { return geomFactory.createLineString() }
        if sections.count == 1 { return geomFactory.createLineString(sections[0].sectionPts) }
        CxxAlgorithms.sort(&sections) { $0.location < $1.location }
        return geomFactory.createMultiLineString(sections.map { geomFactory.createLineString($0.sectionPts) })
    }
}

/// The segments of a ring in monotone chains in an STR tree, to find those
/// near an envelope.
struct SegmentMCIndex {
    private let index = STRtree<MonotoneChain>()

    init(_ segs: [Coordinate]) {
        for mc in MonotoneChainBuilder.getChains(segs) { index.insert(mc.getEnvelope(), mc) }
    }

    func query(_ env: Envelope, _ action: (MonotoneChain, Int) -> Void) {
        index.query(env) { (mc: MonotoneChain) in mc.select(env, action) }
    }
}

extension Geometry {
    /// The offset curve, as `GEOSOffsetCurve` makes it: `quadSegs` segments a
    /// quadrant (at least 8), the join style and the mitre limit.
    public func offsetCurve(_ distance: Double, quadSegs: Int = BufferParameters.defaultQuadrantSegments,
                            joinStyle: Int = BufferParameters.joinRound,
                            mitreLimit: Double = BufferParameters.defaultMitreLimit) throws -> Geometry {
        if joinStyle > BufferParameters.joinBevel { throw IllegalArgumentException("Invalid buffer join style") }
        let params = BufferParameters(quadrantSegments: quadSegs, joinStyle: joinStyle, mitreLimit: mitreLimit)
        return try OffsetCurve(self, distance, params).getCurve()
    }
}
