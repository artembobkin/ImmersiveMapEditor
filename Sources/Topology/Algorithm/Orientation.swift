/// The orientation of three points and of rings: JTS's `Orientation`.
public enum Orientation {
    public static let clockwise = -1
    public static let right = clockwise
    public static let counterclockwise = 1
    public static let left = counterclockwise
    public static let collinear = 0
    public static let straight = collinear

    public static func index(_ p1: Coordinate, _ p2: Coordinate, _ q: Coordinate) -> Int {
        CGAlgorithmsDD.orientationIndex(p1, p2, q)
    }

    /// Whether a closed ring is counter-clockwise, from the turn at its
    /// highest point (false for a flat or degenerate ring).
    public static func isCCW(_ ring: [Coordinate]) -> Bool {
        let nPts = ring.count - 1
        if nPts < 3 { return false }
        var upHiPt = ring[0]
        var prevY = upHiPt.y
        var upLowPt: Coordinate?
        var iUpHi = 0
        for i in 1...nPts {
            let py = ring[i].y
            if py > prevY && py >= upHiPt.y {
                upHiPt = ring[i]
                iUpHi = i
                upLowPt = ring[i - 1]
            }
            prevY = py
        }
        if iUpHi == 0 { return false }
        var iDownLow = iUpHi
        repeat {
            iDownLow = (iDownLow + 1) % nPts
        } while iDownLow != iUpHi && ring[iDownLow].y == upHiPt.y
        let downLowPt = ring[iDownLow]
        let iDownHi = iDownLow > 0 ? iDownLow - 1 : nPts - 1
        let downHiPt = ring[iDownHi]
        if upHiPt.equals2D(downHiPt) {
            let low = upLowPt!
            if low.equals2D(upHiPt) || downLowPt.equals2D(upHiPt) || low.equals2D(downLowPt) { return false }
            return index(low, upHiPt, downLowPt) == counterclockwise
        }
        let delX = downHiPt.x - upHiPt.x
        return delX < 0
    }

    /// Whether a ring is counter-clockwise by its signed area.
    public static func isCCWArea(_ ring: [Coordinate]) -> Bool { Area.ofRingSigned(ring) < 0 }
}
