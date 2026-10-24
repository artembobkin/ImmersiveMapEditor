/// A coordinate array compared in its increasing direction, so a line and
/// its reverse are equal: JTS's `OrientedCoordinateArray`.
public struct OrientedCoordinateArray {
    let pts: [Coordinate]
    let orientation: Bool

    public init(_ pts: [Coordinate]) {
        self.pts = pts
        orientation = CoordinateArrays.increasingDirection(pts) == 1
    }

    public func compareTo(_ o: OrientedCoordinateArray) -> Int {
        let dir1 = orientation ? 1 : -1, dir2 = o.orientation ? 1 : -1
        let limit1 = orientation ? pts.count : -1, limit2 = o.orientation ? o.pts.count : -1
        var i1 = orientation ? 0 : pts.count - 1, i2 = o.orientation ? 0 : o.pts.count - 1
        while true {
            let c = pts[i1].compareTo(o.pts[i2])
            if c != 0 { return c }
            i1 += dir1
            i2 += dir2
            let done1 = i1 == limit1, done2 = i2 == limit2
            if done1 && !done2 { return -1 }
            if !done1 && done2 { return 1 }
            if done1 && done2 { return 0 }
        }
    }
}
