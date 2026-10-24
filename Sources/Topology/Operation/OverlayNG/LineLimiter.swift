/// Cuts a line into the sections that may meet a rectangle: the runs of
/// points inside it, with the points just outside, and the segments that
/// cross it: JTS's `LineLimiter`. The sections are not clipped, so the
/// overlay's noding is unchanged where it matters.
public struct LineLimiter {
    private let limitEnv: Envelope
    private var ptList: CoordinateList?
    private var lastOutside: Coordinate?
    private var sections: [[Coordinate]] = []

    public init(_ env: Envelope) { limitEnv = env }

    public mutating func limit(_ pts: [Coordinate]) -> [[Coordinate]] {
        lastOutside = nil
        ptList = nil
        sections = []
        for p in pts {
            if limitEnv.intersects(p) { addPoint(p) } else { addOutside(p) }
        }
        finishSection()
        return sections
    }

    private mutating func addPoint(_ p: Coordinate?) {
        guard let p else { return }
        startSection()
        ptList!.add(p, false)
    }

    private mutating func addOutside(_ p: Coordinate) {
        if !isLastSegmentIntersecting(p) {
            finishSection()
        } else {
            addPoint(lastOutside)
            addPoint(p)
        }
        lastOutside = p
    }

    private func isLastSegmentIntersecting(_ p: Coordinate) -> Bool {
        guard let lastOutside else { return ptList != nil }
        return limitEnv.intersects(lastOutside, p)
    }

    private mutating func startSection() {
        if ptList == nil { ptList = CoordinateList() }
        if let lastOutside { ptList!.add(lastOutside, false) }
        lastOutside = nil
    }

    private mutating func finishSection() {
        guard ptList != nil else { return }
        if let lastOutside {
            ptList!.add(lastOutside, false)
            self.lastOutside = nil
        }
        sections.append(ptList!.points)
        ptList = nil
    }
}
