/// The hot pixels of a snap rounding, in a KD-tree by their rounded points:
/// JTS's `HotPixelIndex`. The points of each string are added in a seeded
/// shuffle (Java's `Random(13)`), which keeps the tree balanced.
final class HotPixelIndex {
    let precModel: PrecisionModel
    let scaleFactor: Double
    let index = KdTree<HotPixel>()

    init(_ pm: PrecisionModel) {
        precModel = pm
        scaleFactor = pm.scale
    }

    func add(_ pts: [Coordinate]) throws {
        var rnd = JavaRandom(seed: 13)
        var indices = Array(0..<pts.count)
        var i = pts.count - 1
        while i >= 0 {
            let j = Int(rnd.nextInt(Int32(i + 1)))
            let p = pts[indices[j]]
            indices[j] = indices[i]
            i -= 1
            try add(p)
        }
    }

    func addNodes(_ pts: [Coordinate]) throws {
        for p in pts { try add(p).setToNode() }
    }

    @discardableResult
    func add(_ p: Coordinate) throws -> HotPixel {
        let pRound = precModel.makePrecise(p)
        if let hp = find(pRound) {
            hp.setToNode()
            return hp
        }
        let hp = try HotPixel(pRound, scaleFactor)
        index.insert(hp.coordinate, hp)
        return hp
    }

    func find(_ pixelPt: Coordinate) -> HotPixel? {
        guard let i = index.query(pixelPt) else { return nil }
        return index.nodes[i].data
    }

    /// Visits the pixels near the segment `p0`-`p1`.
    func query(_ p0: Coordinate, _ p1: Coordinate, _ visit: (HotPixel) -> Void) {
        var env = Envelope(p0, p1)
        env.expandBy(1.0 / scaleFactor)
        index.query(env) { visit(index.nodes[$0].data!) }
    }
}
