/// geom's `PolyLine`: slicing by distance, points along it, slices ending or
/// starting at a point, and intersections with other lines.

extension PolyLine {
    /// Returns the excess distance left over from the end.
    public func slice(_ start: Distance, _ end: Distance) throws -> (PolyLine, Distance) {
        if start > end || start < .zero || end < .zero {
            throw bail("Can't get a polyline slice [\(start), \(end)]")
        }
        if start > length {
            throw bail("Can't get a polyline slice [\(start), \(end)] on something of length \(length)")
        }
        if end - start < epsilonDist {
            throw bail("Can't get a polyline slice [\(start), \(end)] -- too small")
        }
        var result: [Pt2D] = []
        var distSoFar = Distance.zero
        for line in lines() {
            let length = line.length()
            if result.isEmpty && distSoFar + length >= start {
                result.append(line.mustDistAlong(start - distSoFar))
            }
            if distSoFar + length >= end {
                let lastPt = line.mustDistAlong(end - distSoFar)
                if result.last! == lastPt { result.removeLast() }
                result.append(lastPt)
                if result.count == 1 {
                    throw bail("slice(\(start), \(end)) on \(self) did something weird")
                }
                return (try PolyLine.new(result), .zero)
            }
            if !result.isEmpty && result.last! != line.pt2 {
                result.append(line.pt2)
            }
            distSoFar += length
        }
        if result.isEmpty {
            throw bail("Slice [\(start), \(end)] has a start too big for polyline of length \(length)")
        }
        if result.count == 1 {
            throw bail("Slice [\(start), \(end)] on \(self) wound up a single point")
        }
        return (try PolyLine.new(result), end - distSoFar)
    }

    /// No excess leftover distance allowed.
    public func exactSlice(_ start: Distance, _ end: Distance) -> PolyLine {
        do { return try maybeExactSlice(start, end) } catch { fatalError("\(error)") }
    }

    public func maybeExactSlice(_ start: Distance, _ end: Distance) throws -> PolyLine {
        let (pl, leftover): (PolyLine, Distance)
        do {
            (pl, leftover) = try slice(start, end)
        } catch {
            throw bail("exact_slice(\(start), \(end)) yielded empty slice: \(error)")
        }
        if leftover > epsilonDist {
            throw bail("exact_slice(\(start), \(end)) on a PL of length \(length) yielded leftover distance of \(leftover)")
        }
        return pl
    }

    public func firstHalf() throws -> PolyLine { try maybeExactSlice(.zero, length / 2.0) }
    public func secondHalf() throws -> PolyLine { try maybeExactSlice(length / 2.0, length) }

    public func distAlong(_ distAlong: Distance) throws -> (Pt2D, Angle) {
        if distAlong < .zero { throw bail("dist_along \(distAlong) is negative") }
        if distAlong > length { throw bail("dist_along \(distAlong) is longer than \(length)") }
        if distAlong == length { return (lastPt(), lastLine().angle()) }
        var distLeft = distAlong
        for (idx, l) in lines().enumerated() {
            let length = l.length()
            let epsilon = idx == points.count - 2 ? epsilonDist : .zero
            if distLeft <= length + epsilon {
                let dist = (try? l.distAlong(distLeft)) ?? l.pt2
                return (dist, l.angle())
            }
            distLeft -= length
        }
        fatalError("PolyLine dist_along of \(distAlong) broke on length \(length): \(self)")
    }

    public func mustDistAlong(_ distAlong: Distance) -> (Pt2D, Angle) {
        do { return try self.distAlong(distAlong) } catch { fatalError("\(error)") }
    }

    /// The middle point, or the first point of a tiny line.
    public func middle() -> Pt2D {
        if let (pt, _) = try? distAlong(length / 2.0) { return pt }
        return firstPt()
    }

    /// The first hit from `self`'s perspective, with the angle of `self`'s line there.
    public func intersection(_ other: PolyLine) -> (Pt2D, Angle)? {
        if self == other { return nil }
        var closestIntersection: (Pt2D, Angle)?
        var closestIntersectionDistance: Distance?
        let otherLines = other.lines()
        for l1 in lines() {
            for l2 in otherLines {
                guard let pt = l1.intersection(l2) else { continue }
                guard let newDistance = getSliceEndingAt(pt).map({ $0.length }) else { continue }
                if let existing = closestIntersectionDistance {
                    if existing > newDistance {
                        closestIntersection = (pt, l1.angle())
                        closestIntersectionDistance = newDistance
                    }
                } else {
                    closestIntersection = (pt, l1.angle())
                    closestIntersectionDistance = newDistance
                }
            }
        }
        if closestIntersection == nil && lastPt() == other.lastPt() {
            return (lastPt(), lastLine().angle())
        }
        return closestIntersection
    }

    public func intersectionInfinite(_ other: InfiniteLine) -> Pt2D? {
        for l in lines() {
            if let hit = l.intersectionInfinite(other) { return hit }
        }
        return nil
    }

    /// Panics if the point is not on the polyline. Nil if it is the first point.
    public func getSliceEndingAt(_ pt: Pt2D) -> PolyLine? {
        if firstPt() == pt { return nil }
        guard let idx = lines().firstIndex(where: { $0.containsPt(pt) }) else {
            fatalError("Can't get_slice_ending_at: \(self) doesn't contain \(pt)")
        }
        return sliceEnding(at: pt, idx)
    }

    /// Nil if the point is the last point.
    public func getSliceStartingAt(_ pt: Pt2D) -> PolyLine? {
        if lastPt() == pt { return nil }
        guard let idx = lines().firstIndex(where: { $0.containsPt(pt) }) else {
            fatalError("Can't get_slice_starting_at: \(self) doesn't contain \(pt)")
        }
        return sliceStarting(at: pt, idx)
    }

    /// As `getSliceEndingAt`, nil if the point isn't on the polyline.
    public func safeGetSliceEndingAt(_ pt: Pt2D) -> PolyLine? {
        if firstPt() == pt { return nil }
        guard let idx = lines().firstIndex(where: { $0.containsPt(pt) }) else { return nil }
        return sliceEnding(at: pt, idx)
    }

    /// As `getSliceStartingAt`, nil if the point isn't on the polyline.
    public func safeGetSliceStartingAt(_ pt: Pt2D) -> PolyLine? {
        if lastPt() == pt { return nil }
        guard let idx = lines().firstIndex(where: { $0.containsPt(pt) }) else { return nil }
        return sliceStarting(at: pt, idx)
    }

    private func sliceEnding(at pt: Pt2D, _ idx: Int) -> PolyLine? {
        var pts = Array(points[0...idx])
        if pts.last! == pt { pts.removeLast() }
        pts.append(pt)
        if pts.count == 1 { return nil }
        return .mustNew(pts)
    }

    private func sliceStarting(at pt: Pt2D, _ idx: Int) -> PolyLine {
        var pts = Array(points[(idx + 1)...])
        if pt != pts[0] { pts.insert(pt, at: 0) }
        return .mustNew(pts)
    }

    public func distAlongOfPoint(_ pt: Pt2D) -> (Distance, Angle)? {
        var distAlong = Distance.zero
        for l in lines() {
            if let dist = l.distAlongOfPoint(pt) { return (distAlong + dist, l.angle()) }
            distAlong += l.length()
        }
        return nil
    }

    public func trimToEndpts(_ pt1: Pt2D, _ pt2: Pt2D) -> PolyLine {
        precondition(pt1 != pt2)
        var dist1 = distAlongOfPoint(pt1)!.0
        var dist2 = distAlongOfPoint(pt2)!.0
        if dist1 > dist2 { swap(&dist1, &dist2) }
        return exactSlice(dist1, dist2)
    }

    /// Extends the end along the last line's angle until it is at least `minLen` long.
    public func extendToLength(_ minLen: Distance) -> PolyLine {
        let needLen = minLen - length
        if needLen <= .zero { return self }
        let line = lastLine()
        if let ext = try? PolyLine.new([line.pt2, line.pt2.projectAway(needLen, line.angle())]) {
            return mustExtend(ext)
        }
        var pts = points
        pts.removeLast()
        pts.append(line.pt2.projectAway(needLen, line.angle()))
        return .mustNew(pts)
    }

    public func stepAlong(_ stepSize: Distance, _ bufferEnds: Distance) -> [(Pt2D, Angle)] {
        stepAlongStartEnd(stepSize, bufferEnds, bufferEnds)
    }

    public func stepAlongStartEnd(_ stepSize: Distance, _ startBuffer: Distance, _ endBuffer: Distance) -> [(Pt2D, Angle)] {
        var result: [(Pt2D, Angle)] = []
        var distAlong = startBuffer
        let length = self.length
        while distAlong < length - endBuffer {
            result.append(mustDistAlong(distAlong))
            distAlong += stepSize
        }
        return result
    }
}
