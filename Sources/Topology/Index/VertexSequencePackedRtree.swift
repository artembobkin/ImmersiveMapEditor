/// A packed R-tree over the vertices of a sequence, in their order, from
/// which vertices can be removed: JTS's `VertexSequencePackedRtree`, used by
/// the ear clipper. Queries give the indices of the vertices in an envelope,
/// in sequence order.
public struct VertexSequencePackedRtree {
    static let nodeCapacity = 16

    let items: [Coordinate]
    var levelOffset: [Int] = []
    var bounds: [Envelope] = []
    var isRemoved: [Bool]

    public init(_ pts: [Coordinate]) {
        items = pts
        isRemoved = Array(repeating: false, count: pts.count)
        levelOffset = computeLevelOffsets()
        bounds = createBounds()
    }

    private func computeLevelOffsets() -> [Int] {
        var offsets = [0]
        var levelSize = items.count
        var currOffset = 0
        repeat {
            levelSize = VertexSequencePackedRtree.levelNodeCount(levelSize)
            currOffset += levelSize
            offsets.append(currOffset)
        } while levelSize > 1
        return offsets
    }

    private static func levelNodeCount(_ numNodes: Int) -> Int {
        let div = numNodes / nodeCapacity
        return div * nodeCapacity >= numNodes ? div : div + 1
    }

    private func createBounds() -> [Envelope] {
        var bounds = Array(repeating: Envelope(), count: levelOffset[levelOffset.count - 1] + 1)
        // The items' nodes.
        var nodeStart = 0, boundIndex = 0
        repeat {
            let nodeEnd = min(nodeStart + VertexSequencePackedRtree.nodeCapacity, items.count)
            var env = Envelope()
            for i in nodeStart..<nodeEnd { env.expandToInclude(items[i]) }
            bounds[boundIndex] = env
            boundIndex += 1
            nodeStart = nodeEnd
        } while nodeStart < items.count
        // The levels above.
        for lvl in 1..<levelOffset.count {
            let levelEnd = levelOffset[lvl]
            var nodeStart = levelOffset[lvl - 1]
            var levelBoundIndex = levelOffset[lvl]
            repeat {
                let nodeEnd = min(nodeStart + VertexSequencePackedRtree.nodeCapacity, levelEnd)
                var env = Envelope()
                for i in nodeStart..<nodeEnd { env.expandToInclude(bounds[i]) }
                bounds[levelBoundIndex] = env
                levelBoundIndex += 1
                nodeStart = nodeEnd
            } while nodeStart < levelEnd
        }
        return bounds
    }

    /// The indices of the vertices not removed inside the envelope.
    public func query(_ queryEnv: Envelope) -> [Int] {
        var result: [Int] = []
        queryNode(queryEnv, levelOffset.count - 1, 0, &result)
        return result
    }

    private func queryNode(_ queryEnv: Envelope, _ level: Int, _ nodeIndex: Int, _ result: inout [Int]) {
        let nodeEnv = bounds[levelOffset[level] + nodeIndex]
        if nodeEnv.isNull { return }
        if !queryEnv.intersects(nodeEnv) { return }
        let childNodeIndex = nodeIndex * VertexSequencePackedRtree.nodeCapacity
        if level == 0 {
            for i in 0..<VertexSequencePackedRtree.nodeCapacity {
                let index = childNodeIndex + i
                if index >= items.count { return }
                if !isRemoved[index] && queryEnv.contains(items[index]) { result.append(index) }
            }
        } else {
            let levelMax = levelOffset[level] - levelOffset[level - 1]
            for i in 0..<VertexSequencePackedRtree.nodeCapacity {
                let index = childNodeIndex + i
                if index >= levelMax { return }
                queryNode(queryEnv, level - 1, index, &result)
            }
        }
    }

    /// Removes a vertex, emptying its node (and the node above) when no
    /// vertex is left in it.
    public mutating func remove(_ index: Int) {
        isRemoved[index] = true
        let nodeIndex = index / VertexSequencePackedRtree.nodeCapacity
        if !isItemsNodeEmpty(nodeIndex) { return }
        bounds[nodeIndex] = Envelope()
        if levelOffset.count <= 2 { return }
        let nodeLevelIndex = nodeIndex / VertexSequencePackedRtree.nodeCapacity
        if !isNodeEmpty(1, nodeLevelIndex) { return }
        bounds[levelOffset[1] + nodeLevelIndex] = Envelope()
    }

    private func isNodeEmpty(_ level: Int, _ index: Int) -> Bool {
        let start = index * VertexSequencePackedRtree.nodeCapacity
        let end = min(start + VertexSequencePackedRtree.nodeCapacity, levelOffset[level])
        for i in start..<end where !bounds[i].isNull { return false }
        return true
    }

    private func isItemsNodeEmpty(_ nodeIndex: Int) -> Bool {
        let start = nodeIndex * VertexSequencePackedRtree.nodeCapacity
        let end = min(start + VertexSequencePackedRtree.nodeCapacity, items.count)
        for i in start..<end where !isRemoved[i] { return false }
        return true
    }
}
