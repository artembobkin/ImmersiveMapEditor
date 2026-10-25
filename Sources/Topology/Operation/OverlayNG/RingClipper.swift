/// Clips a ring to a rectangle, one side of it at a time, keeping it a
/// ring (possibly with segments along the rectangle that collapse later):
/// JTS's `RingClipper`. Points on a side count as outside it.
public struct RingClipper {
    private static let boxLeft = 3, boxTop = 2, boxRight = 1, boxBottom = 0

    private let clipEnvMinY: Double
    private let clipEnvMaxY: Double
    private let clipEnvMinX: Double
    private let clipEnvMaxX: Double

    public init(_ clipEnv: Envelope) {
        clipEnvMinY = clipEnv.minY
        clipEnvMaxY = clipEnv.maxY
        clipEnvMinX = clipEnv.minX
        clipEnvMaxX = clipEnv.maxX
    }

    public func clip(_ input: [Coordinate]) -> [Coordinate] {
        var pts = input
        for edgeIndex in 0..<4 {
            pts = clipToBoxEdge(pts, edgeIndex, edgeIndex == 3)
            if pts.isEmpty { return pts }
        }
        return pts
    }

    private func clipToBoxEdge(_ pts: [Coordinate], _ edgeIndex: Int, _ closeRing: Bool) -> [Coordinate] {
        var ptsClip = CoordinateList()
        var p0 = pts[pts.count - 1]
        for p1 in pts {
            if isInsideEdge(p1, edgeIndex) {
                if !isInsideEdge(p0, edgeIndex) { ptsClip.add(intersection(p0, p1, edgeIndex), false) }
                ptsClip.add(p1, false)
            } else if isInsideEdge(p0, edgeIndex) {
                ptsClip.add(intersection(p0, p1, edgeIndex), false)
            }
            p0 = p1
        }
        if closeRing && ptsClip.count > 0 {
            let start = ptsClip[0]
            if !start.equals2D(ptsClip[ptsClip.count - 1]) { ptsClip.add(start) }
        }
        return ptsClip.points
    }

    private func intersection(_ a: Coordinate, _ b: Coordinate, _ edgeIndex: Int) -> Coordinate {
        switch edgeIndex {
        case RingClipper.boxBottom: return Coordinate(intersectionLineY(a, b, clipEnvMinY), clipEnvMinY)
        case RingClipper.boxRight: return Coordinate(clipEnvMaxX, intersectionLineX(a, b, clipEnvMaxX))
        case RingClipper.boxTop: return Coordinate(intersectionLineY(a, b, clipEnvMaxY), clipEnvMaxY)
        default: return Coordinate(clipEnvMinX, intersectionLineX(a, b, clipEnvMinX))
        }
    }

    private func intersectionLineY(_ a: Coordinate, _ b: Coordinate, _ y: Double) -> Double {
        let m = (b.x - a.x) / (b.y - a.y)
        let intercept = (y - a.y) * m
        return a.x + intercept
    }

    private func intersectionLineX(_ a: Coordinate, _ b: Coordinate, _ x: Double) -> Double {
        let m = (b.y - a.y) / (b.x - a.x)
        let intercept = (x - a.x) * m
        return a.y + intercept
    }

    private func isInsideEdge(_ p: Coordinate, _ edgeIndex: Int) -> Bool {
        switch edgeIndex {
        case RingClipper.boxBottom: return p.y > clipEnvMinY
        case RingClipper.boxRight: return p.x < clipEnvMaxX
        case RingClipper.boxTop: return p.y < clipEnvMaxY
        default: return p.x > clipEnvMinX
        }
    }
}
