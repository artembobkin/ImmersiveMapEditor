/// geom's `PolyLine`: shifting sideways, thickening into polygons, dashes
/// and arrows.

extension PolyLine {
    public func shiftRight(_ width: Distance) throws -> PolyLine { try shiftWithCorrections(width) }
    public func mustShiftRight(_ width: Distance) -> PolyLine {
        do { return try shiftRight(width) } catch { fatalError("\(error)") }
    }
    public func shiftLeft(_ width: Distance) throws -> PolyLine { try shiftWithCorrections(-width) }
    public func mustShiftLeft(_ width: Distance) -> PolyLine {
        do { return try shiftLeft(width) } catch { fatalError("\(error)") }
    }

    /// Right if positive, left if negative.
    public func shiftEitherDirection(_ width: Distance) throws -> PolyLine { try shiftWithCorrections(width) }

    /// `self` is a center of `totalWidth`: shifts as if left by half of it,
    /// then right by `widthFromLeftSide`, in one step.
    public func shiftFromCenter(_ totalWidth: Distance, _ widthFromLeftSide: Distance) throws -> PolyLine {
        let halfWidth = totalWidth / 2.0
        if widthFromLeftSide < halfWidth {
            return try shiftLeft(halfWidth - widthFromLeftSide)
        }
        return try shiftRight(widthFromLeftSide - halfWidth)
    }

    func shiftWithCorrections(_ width: Distance) throws -> PolyLine {
        let raw = try shiftWithSharpAngles(width, miterThreshold)
        let result = try PolyLine.dedupingNew(raw)
        if result.points.count == points.count {
            return try fixAngles(self, result)
        }
        return result
    }

    func shiftWithSharpAngles(_ width: Distance, _ miterThreshold: Double) throws -> [Pt2D] {
        if points.count == 2 {
            let l = try Line.new(points[0], points[1]).shiftEitherDirection(width)
            return [l.pt1, l.pt2]
        }
        var result: [Pt2D] = []
        result.reserveCapacity(points.count)
        var pt3Idx = 2
        var pt1Raw = points[0]
        var pt2Raw = points[1]
        while true {
            let pt3Raw = points[pt3Idx]
            let l1 = try Line.new(pt1Raw, pt2Raw).shiftEitherDirection(width)
            let l2 = try Line.new(pt2Raw, pt3Raw).shiftEitherDirection(width)
            if pt3Idx == 2 { result.append(l1.pt1) }
            if let pt2Shift = l1.infinite().intersection(l2.infinite()) {
                // Miter caps sometimes explode out to infinity.
                let distAway = l1.pt1.rawDistTo(pt2Shift)
                result.append(distAway < miterThreshold ? pt2Shift : l1.pt2)
            } else {
                result.append(l1.pt2)
            }
            if pt3Idx == points.count - 1 {
                result.append(l2.pt2)
                break
            }
            pt1Raw = pt2Raw
            pt2Raw = pt3Raw
            pt3Idx += 1
        }
        precondition(result.count == points.count)
        return result
    }

    /// Like `makePolygons`, but makes sure the points form a ring.
    public func toThickRing(_ width: Distance) -> Ring {
        var side1 = try! shiftWithSharpAngles(width / 2.0, miterThreshold)
        var side2 = try! shiftWithSharpAngles(-width / 2.0, miterThreshold)
        side2.reverse()
        side1.append(contentsOf: side2)
        side1.append(side1[0])
        side1.dedup()
        return Ring.mustNew(side1)
    }

    public func toThickBoundary(_ selfWidth: Distance, _ boundaryWidth: Distance) -> Tessellation? {
        if selfWidth <= boundaryWidth || length <= boundaryWidth + epsilonDist { return nil }
        guard let slice = try? maybeExactSlice(boundaryWidth / 2.0, length - boundaryWidth / 2.0) else { return nil }
        return slice.toThickRing(selfWidth - boundaryWidth).toOutline(boundaryWidth)
    }

    /// A polygon with a valid ring. May crash on a polyline made with `uncheckedNew`.
    public func makePolygons(_ width: Distance) -> Polygon {
        let tessellation = thickenTessellation(width)
        guard let ring = try? Ring.dedupingNew(tessellation.points) else {
            fatalError("PolyLine::make_polygons() failed")
        }
        return Polygon.pretessellated([ring], tessellation)
    }

    /// A polygon with a possibly invalid ring.
    public func unsafeMakePolygons(_ width: Distance) -> Polygon {
        let tessellation = thickenTessellation(width)
        guard let ring = try? Ring.unsafeDedupingNew(tessellation.points) else {
            fatalError("PolyLine::make_polygons() failed")
        }
        return Polygon.pretessellated([ring], tessellation)
    }

    public func thickenTessellation(_ width: Distance) -> Tessellation {
        guard let side1 = try? shiftWithSharpAngles(width / 2.0, miterThreshold),
              var side2 = try? shiftWithSharpAngles(-width / 2.0, miterThreshold) else {
            // Circles look bizarre, which shows there's a bug without crashing.
            return Tessellation.from(Circle(center: firstPt(), radius: width).toPolygon())
        }
        precondition(side1.count == side2.count)
        let len = 2 * side1.count
        var points = side1
        side2.reverse()
        points.append(contentsOf: side2)
        points.append(points[0])
        var indices: [Int] = []
        for highIdx in 1..<self.points.count {
            indices.append(contentsOf: [highIdx, highIdx - 1, len - highIdx])
            indices.append(contentsOf: [len - highIdx, len - highIdx - 1, highIdx])
        }
        return Tessellation(points: points, indices: indices)
    }

    /// (start left, start right, end left, end right) of `makePolygons`.
    public func getFourCornersOfThickened(_ width: Distance) -> (Pt2D, Pt2D, Pt2D, Pt2D)? {
        guard let side1 = try? shiftWithSharpAngles(width / 2.0, miterThreshold),
              let side2 = try? shiftWithSharpAngles(-width / 2.0, miterThreshold) else { return nil }
        return (side1[0], side2[0], side1.last!, side2.last!)
    }

    public func exactDashedPolygons(_ width: Distance, _ dashLen: Distance, _ dashSeparation: Distance) -> [Polygon] {
        var polygons: [Polygon] = []
        let totalLength = length
        var start = Distance.zero
        while true {
            if start + dashLen >= totalLength { break }
            polygons.append(exactSlice(start, start + dashLen).makePolygons(width))
            start += dashLen + dashSeparation
        }
        return polygons
    }

    /// Dashes, kept away from the ends.
    public func dashedLines(_ width: Distance, _ dashLen: Distance, _ dashSeparation: Distance) -> [Polygon] {
        if length <= dashSeparation * 2.0 + epsilonDist { return [makePolygons(width)] }
        return exactSlice(dashSeparation, length - dashSeparation).exactDashedPolygons(width, dashLen, dashSeparation)
    }

    public func maybeMakeArrow(_ thickness: Distance, _ cap: ArrowCap) -> Polygon? {
        let headSize = thickness * 2.0
        let triangleHeight = headSize / (2.0).squareRoot()
        guard let slice = try? maybeExactSlice(.zero, length - triangleHeight) else { return nil }
        let angle = slice.lastPt().angleTo(lastPt())
        let corner1 = lastPt().projectAway(headSize, angle.rotateDegs(-135.0))
        let corner2 = lastPt().projectAway(headSize, angle.rotateDegs(135.0))
        guard var pts = try? slice.shiftWithSharpAngles(thickness / 2.0, miterThreshold) else { return nil }
        switch cap {
        case .triangle:
            pts.append(corner2)
            pts.append(lastPt())
            pts.append(corner1)
        }
        guard var side2 = try? slice.shiftWithSharpAngles(-thickness / 2.0, miterThreshold) else { return nil }
        side2.reverse()
        pts.append(contentsOf: side2)
        pts.append(pts[0])
        pts.dedup()
        return Ring.mustNew(pts).intoPolygon()
    }

    /// Falls back to the thick line when too short.
    public func makeArrow(_ thickness: Distance, _ cap: ArrowCap) -> Polygon {
        maybeMakeArrow(thickness, cap) ?? makePolygons(thickness)
    }

    public func makeDoubleArrow(_ thickness: Distance, _ cap: ArrowCap) -> Polygon {
        let headSize = thickness * 2.0
        let triangleHeight = headSize / (2.0).squareRoot()
        if length < triangleHeight * 2.0 + epsilonDist { return makePolygons(thickness) }
        let slice = exactSlice(triangleHeight, length - triangleHeight)
        let angle = slice.lastPt().angleTo(lastPt())
        let corner1 = lastPt().projectAway(headSize, angle.rotateDegs(-135.0))
        let corner2 = lastPt().projectAway(headSize, angle.rotateDegs(135.0))
        guard var pts = try? slice.shiftWithSharpAngles(thickness / 2.0, miterThreshold) else {
            return makePolygons(thickness)
        }
        switch cap {
        case .triangle:
            pts.append(corner2)
            pts.append(lastPt())
            pts.append(corner1)
        }
        guard var side2 = try? slice.shiftWithSharpAngles(-thickness / 2.0, miterThreshold) else {
            return makePolygons(thickness)
        }
        side2.reverse()
        pts.append(contentsOf: side2)
        let angle2 = firstPt().angleTo(slice.firstPt())
        let corner3 = firstPt().projectAway(headSize, angle2.rotateDegs(-45.0))
        let corner4 = firstPt().projectAway(headSize, angle2.rotateDegs(45.0))
        switch cap {
        case .triangle:
            pts.append(corner3)
            pts.append(firstPt())
            pts.append(corner4)
        }
        pts.append(pts[0])
        pts.dedup()
        return Ring.mustNew(pts).intoPolygon()
    }
}

/// Swaps points whose shifted segment turned around, then rebuilds (the
/// length can change).
func fixAngles(_ orig: PolyLine, _ result: PolyLine) throws -> PolyLine {
    var pts = result.points
    for (idx, (origL, shiftedL)) in zip(orig.lines(), result.lines()).enumerated() {
        if !origL.angle().approxEq(shiftedL.angle(), 1.0) {
            pts.swapAt(idx, idx + 1)
        }
    }
    return try PolyLine.new(pts)
}
