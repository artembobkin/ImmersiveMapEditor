/// geo's `LineAssembly`: joins the clipped pieces of each input line string back into line
/// strings, extending a chain at whichever end a new piece touches.

struct LineAssembly {
    private struct EndKey: Hashable {
        let geomIdx: Int
        let point: SweepPoint
    }

    private var segments: [[SweepPoint]] = []
    private var endPoints: [EndKey: (Int, Bool)] = [:]

    mutating func addEdge(_ geom: LineOrPoint, _ geomIdx: Int) {
        // Find a chain of the same input with either end point.
        if let (segIdx, atFront) = endPoints.removeValue(forKey: EndKey(geomIdx: geomIdx, point: geom.left)) {
            if atFront {
                segments[segIdx].insert(geom.right, at: 0)
            } else {
                segments[segIdx].append(geom.right)
            }
            endPoints[EndKey(geomIdx: geomIdx, point: geom.right)] = (segIdx, atFront)
        } else if let (segIdx, atFront) = endPoints.removeValue(forKey: EndKey(geomIdx: geomIdx, point: geom.right)) {
            if atFront {
                segments[segIdx].insert(geom.left, at: 0)
            } else {
                segments[segIdx].append(geom.left)
            }
            endPoints[EndKey(geomIdx: geomIdx, point: geom.left)] = (segIdx, atFront)
        } else {
            let idx = segments.count
            segments.append([geom.left, geom.right])
            endPoints[EndKey(geomIdx: geomIdx, point: geom.left)] = (idx, true)
            endPoints[EndKey(geomIdx: geomIdx, point: geom.right)] = (idx, false)
        }
    }

    func finish() -> [GeoLineString] {
        segments.map { GeoLineString($0.map(\.coord)) }
    }
}
