/// Cuts a line into monotone chains: JTS's `MonotoneChainBuilder`.
public enum MonotoneChainBuilder {
    public static func getChains(_ pts: [Coordinate], _ context: SegmentString? = nil) -> [MonotoneChain] {
        var list: [MonotoneChain] = []
        appendChains(pts, context, &list)
        return list
    }

    /// The chains of the points appended to a list.
    public static func appendChains(_ pts: [Coordinate], _ context: SegmentString?, _ list: inout [MonotoneChain]) {
        if pts.isEmpty { return }
        var chainStart = 0
        repeat {
            let chainEnd = findChainEnd(pts, chainStart)
            list.append(MonotoneChain(pts, chainStart, chainEnd, context))
            chainStart = chainEnd
        } while chainStart < pts.count - 1
    }

    /// The last index of the chain from `start`: repeated points are part of
    /// it, a segment heading into another quadrant ends it.
    static func findChainEnd(_ pts: [Coordinate], _ start: Int) -> Int {
        var safeStart = start
        while safeStart < pts.count - 1 && pts[safeStart].equals2D(pts[safeStart + 1]) { safeStart += 1 }
        if safeStart >= pts.count - 1 { return pts.count - 1 }
        let chainQuad = Quadrant.quadrant(pts[safeStart], pts[safeStart + 1])
        var last = start + 1
        while last < pts.count {
            if !pts[last - 1].equals2D(pts[last]) {
                if Quadrant.quadrant(pts[last - 1], pts[last]) != chainQuad { break }
            }
            last += 1
        }
        return last - 1
    }
}
