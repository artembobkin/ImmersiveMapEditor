/// Runs a noder on coordinates scaled to integers and scales the result
/// back: JTS's `ScaledNoder` (with no offset, as JTS uses it).
public final class ScaledNoder: Noder {
    let noder: Noder
    let scaleFactor: Double
    let offsetX = 0.0, offsetY = 0.0
    let isScaled: Bool

    public init(_ noder: Noder, _ scaleFactor: Double) {
        self.noder = noder
        self.scaleFactor = scaleFactor
        isScaled = scaleFactor != 1.0
    }

    public var isIntegerPrecision: Bool { scaleFactor == 1.0 }

    public func getNodedSubstrings() -> [SegmentString] {
        let split = noder.getNodedSubstrings()
        guard isScaled else { return split }
        // JTS rescales the coordinates in place: here each string is made again.
        return split.map { ss in
            NodedSegmentString(ss.getCoordinates().map { Coordinate($0.x / scaleFactor + offsetX, $0.y / scaleFactor + offsetY) },
                               ss.getData())
        }
    }

    public func computeNodes(_ inputSegStrings: [SegmentString]) throws {
        var strings = inputSegStrings
        if isScaled {
            strings = inputSegStrings.map { ss in
                let round = ss.getCoordinates().map {
                    Coordinate(geosRound(($0.x - offsetX) * scaleFactor), geosRound(($0.y - offsetY) * scaleFactor))
                }
                return NodedSegmentString(CoordinateArrays.removeRepeatedPoints(round), ss.getData())
            }
        }
        try noder.computeNodes(strings)
    }
}
