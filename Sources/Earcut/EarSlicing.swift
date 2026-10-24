/// The ear slicing loop of the earcutr port and its fallbacks: filtering repeated and collinear
/// points, curing small local self-intersections, and splitting the polygon in two.

/// Slices ears off the ring at `earIdx` one by one, appending their vertex indices to `triangles`
/// (`earcut_linked_hashed` and `earcut_linked_unhashed` in earcutr).
///
/// `pass` is the Rust const generic `PASS`. When no more ears are found, pass 0 filters the points
/// and tries again, pass 1 cures local intersections and tries again, and pass 2 splits the
/// polygon. `hashed` picks the z-order ear test. The split always goes on hashed, as in the Rust.
func earcutLinked(
    _ ll: LinkedLists,
    _ startEarIdx: Int,
    _ triangles: inout [Int],
    pass: Int,
    hashed: Bool
) throws {
    var earIdx = startEarIdx
    // Interlink the polygon nodes in z-order.
    if hashed && pass == 0 {
        try ll.indexCurve(earIdx)
    }
    // Iterate through the ears, slicing them one by one.
    var stopIdx = earIdx
    var prevIdx = 0
    var nextIdx = ll.nodes[earIdx].nextLinkedListNodeIndex
    while stopIdx != nextIdx {
        prevIdx = ll.nodes[earIdx].prevLinkedListNodeIndex
        nextIdx = ll.nodes[earIdx].nextLinkedListNodeIndex
        let nodeIndexTriangle = NodeIndexTriangle(prevIdx, earIdx, nextIdx)
        let isEar: Bool
        if hashed {
            isEar = try nodeIndexTriangle.nodeTriangle(ll).isEarHashed(ll)
        } else {
            isEar = nodeIndexTriangle.isEar(ll)
        }
        if isEar {
            triangles.append(ll.nodes[prevIdx].verticesIndex)
            triangles.append(ll.nodes[earIdx].verticesIndex)
            triangles.append(ll.nodes[nextIdx].verticesIndex)
            ll.removeNode(earIdx)
            // Skipping the next vertex leads to fewer sliver triangles.
            earIdx = ll.nodes[nextIdx].nextLinkedListNodeIndex
            stopIdx = earIdx
        } else {
            earIdx = nextIdx
        }
    }

    if prevIdx == nextIdx {
        return
    }
    // The loop went through the whole remaining polygon and found no more ears.
    if pass == 0 {
        let tmp = filterPoints(ll, nextIdx, nil)
        try earcutLinked(ll, tmp, &triangles, pass: 1, hashed: hashed)
    } else if pass == 1 {
        earIdx = cureLocalIntersections(ll, nextIdx, &triangles)
        try earcutLinked(ll, earIdx, &triangles, pass: 2, hashed: hashed)
    } else if pass == 2 {
        try splitEarcut(ll, nextIdx, &triangles)
    }
}

/// The inverse of the longer side of the bounding box, scaled to the 15-bit z-order range, or zero
/// for an empty box (`calc_invsize` in earcutr).
func calcInvsize(_ min: Coord, _ max: Coord) -> Double {
    let invsize = rustMax(max.x - min.x, max.y - min.y)
    if invsize == 0 {
        return 0
    }
    return 32767.0 / invsize
}

/// Removes repeated and collinear points from the ring between `start` and `end` (`end` defaults
/// to `start`), and returns the node the filtering stopped at, or `null`.
func filterPoints(_ ll: LinkedLists, _ start: Int, _ endIdx: Int?) -> Int {
    var end = endIdx ?? start
    if end >= ll.nodes.count || start >= ll.nodes.count {
        return null
    }

    var p = start
    var again: Bool

    // This loop wastes work by going over the same points several times. Moving the `end` node
    // instead could disrupt the code that calls this function.
    while true {
        again = false
        if !ll.nodes[p].isSteinerPoint
            && (ll.nodes[p].xyEq(ll.nodes[ll.nodes[p].nextLinkedListNodeIndex])
                || NodeTriangle.fromEarNode(ll.nodes[p], ll).area() == 0)
        {
            ll.removeNode(p)
            end = ll.nodes[p].prevLinkedListNodeIndex
            p = end
            if p == ll.nodes[p].nextLinkedListNodeIndex {
                return end
            }
            again = true
        } else {
            if p == ll.nodes[p].nextLinkedListNodeIndex {
                return null
            }
            p = ll.nodes[p].nextLinkedListNodeIndex
        }
        if !again && p == end {
            return end
        }
    }
}

/// Goes through all the nodes of a ring and cures small local self-intersections.
///
/// Of four consecutive points a, p, pn, b, when the segments a-p and pn-b cross, the triangle
/// a, p, b is output and p and pn are removed. So this is part of the triangulation itself.
func cureLocalIntersections(_ ll: LinkedLists, _ inStart: Int, _ triangles: inout [Int]) -> Int {
    var p = inStart
    var start = inStart

    while true {
        let a = ll.nodes[p].prevLinkedListNodeIndex
        let b = ll.next(p).nextLinkedListNodeIndex

        if !ll.nodes[a].xyEq(ll.nodes[b])
            && pseudoIntersects(ll.nodes[a], ll.nodes[p], ll.next(p), ll.nodes[b])
            && locallyInside(ll, ll.nodes[a], ll.nodes[b])
            && locallyInside(ll, ll.nodes[b], ll.nodes[a])
        {
            triangles.append(ll.nodes[a].verticesIndex)
            triangles.append(ll.nodes[p].verticesIndex)
            triangles.append(ll.nodes[b].verticesIndex)

            // Remove the two nodes involved.
            ll.removeNode(p)
            let nIdx = ll.nodes[p].nextLinkedListNodeIndex
            ll.removeNode(nIdx)

            start = ll.nodes[b].idx
            p = start
        }
        p = ll.nodes[p].nextLinkedListNodeIndex
        if p == start {
            break
        }
    }

    return p
}

/// Looks for a valid diagonal that splits the polygon in two, and triangulates both halves.
func splitEarcut(_ ll: LinkedLists, _ startIdx: Int, _ triangles: inout [Int]) throws {
    var a = startIdx
    while true {
        var b = ll.next(a).nextLinkedListNodeIndex
        while b != ll.nodes[a].prevLinkedListNodeIndex {
            if ll.nodes[a].verticesIndex != ll.nodes[b].verticesIndex
                && ll.isValidDiagonal(ll.nodes[a], ll.nodes[b])
            {
                // Split the polygon in two by the diagonal.
                var c = splitBridgePolygon(ll, a, b)

                // Filter the collinear points around the cuts.
                let an = ll.nodes[a].nextLinkedListNodeIndex
                let cn = ll.nodes[c].nextLinkedListNodeIndex
                a = filterPoints(ll, a, an)
                c = filterPoints(ll, c, cn)

                // Run earcut on each half.
                try earcutLinked(ll, a, &triangles, pass: 0, hashed: true)
                try earcutLinked(ll, c, &triangles, pass: 0, hashed: true)
                return
            }
            b = ll.nodes[b].nextLinkedListNodeIndex
        }
        a = ll.nodes[a].nextLinkedListNodeIndex
        if a == startIdx {
            break
        }
    }
}
