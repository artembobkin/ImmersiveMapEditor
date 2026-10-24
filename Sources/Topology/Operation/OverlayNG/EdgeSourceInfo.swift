/// Where a noded edge came from: which input, its dimension, and for a
/// ring its depth delta and whether it is a hole: JTS's `EdgeSourceInfo`.
struct EdgeSourceInfo {
    let index: Int
    let dim: Int
    let isHole: Bool
    let depthDelta: Int

    /// Of a polygon's ring.
    init(_ index: Int, _ depthDelta: Int, _ isHole: Bool) {
        self.index = index
        dim = Dimension.a
        self.depthDelta = depthDelta
        self.isHole = isHole
    }

    /// Of a line.
    init(_ index: Int) {
        self.index = index
        dim = Dimension.l
        isHole = false
        depthDelta = 0
    }
}
