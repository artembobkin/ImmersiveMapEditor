/// The clipping envelope of an overlay, made safe: the target envelope
/// grown to every segment of the inputs' rings that meets it, so clipping
/// never cuts a ring segment that matters: JTS's `RobustClipEnvelopeComputer`.
struct RobustClipEnvelopeComputer {
    private let targetEnv: Envelope
    private var clipEnv: Envelope

    static func getEnvelope(_ a: Geometry?, _ b: Geometry?, _ targetEnv: Envelope) -> Envelope {
        var cec = RobustClipEnvelopeComputer(targetEnv)
        cec.add(a)
        cec.add(b)
        return cec.clipEnv
    }

    init(_ targetEnv: Envelope) {
        self.targetEnv = targetEnv
        clipEnv = targetEnv
    }

    mutating func add(_ g: Geometry?) {
        guard let g, !g.isEmpty() else { return }
        if let poly = g as? Polygon {
            addPolygonRing(poly.shell)
            for hole in poly.holes { addPolygonRing(hole) }
        } else if let gc = g as? GeometryCollection {
            for c in gc.geometries { add(c) }
        }
    }

    private mutating func addPolygonRing(_ ring: LinearRing) {
        if ring.isEmpty() { return }
        let seq = ring.points
        for i in stride(from: 1, to: seq.count, by: 1) where targetEnv.intersects(seq[i - 1], seq[i]) {
            clipEnv.expandToInclude(seq[i - 1])
            clipEnv.expandToInclude(seq[i])
        }
    }
}
