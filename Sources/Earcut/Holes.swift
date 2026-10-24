/// Holes in the earcutr port: linking every hole into the outer ring through a bridge found with
/// David Eberly's algorithm, and the bridge itself, which splits one ring in two or joins two
/// rings into one.

/// Links every hole into the outer ring, producing a single ring without holes, and returns the
/// outer ring's node to start from (`eliminate_holes` in earcutr).
func eliminateHoles(
    _ ll: LinkedLists,
    _ vertices: Vertices,
    _ holeIndices: [Int],
    _ inOuterNode: Int
) throws -> Int {
    var outerNode = inOuterNode
    // The leftmost node of each hole with its x, as the Rust queue holds node copies.
    var queue: [(idx: Int, x: Double)] = []

    // Each hole runs from its start to the next hole's start, the last one to the end of the array.
    var bounds: [Int?] = holeIndices.map { index in
        let (product, overflow) = index.multipliedReportingOverflow(by: dim)
        return index < 0 || overflow ? nil : product
    }
    bounds.append(vertices.count)
    var window = 0
    while window + 1 < bounds.count {
        guard let holeStart = bounds[window], let holeEnd = bounds[window + 1] else {
            throw EarcutError.unknown
        }
        let (list, leftmostIdx) = try ll.addContour(vertices, holeStart, holeEnd, false)
        if list == ll.nodes[list].nextLinkedListNodeIndex {
            ll.nodes[list].isSteinerPoint = true
        }
        queue.append((leftmostIdx, ll.nodes[leftmostIdx].coord.x))
        window += 1
    }

    queue = stableSortedByX(queue)

    // Process the holes from left to right.
    for node in queue {
        ll.eliminateHole(node.idx, outerNode)
        let nextIdx = ll.next(outerNode).idx
        outerNode = filterPoints(ll, outerNode, nextIdx)
    }
    return outerNode
}

/// Sorts the hole queue by x, keeping the order of equal elements, as Rust's stable `sort_by`
/// with `partial_cmp` does (incomparable values, that is NaN, count as equal).
private func stableSortedByX(_ items: [(idx: Int, x: Double)]) -> [(idx: Int, x: Double)] {
    if items.count < 2 {
        return items
    }
    var source = items
    var target = items
    var width = 1
    while width < source.count {
        var low = 0
        while low < source.count {
            let middle = Swift.min(low + width, source.count)
            let high = Swift.min(low + 2 * width, source.count)
            var i = low
            var j = middle
            var k = low
            while i < middle && j < high {
                // Take from the right run only when it is strictly less, which keeps the sort stable.
                if source[j].x < source[i].x {
                    target[k] = source[j]
                    j += 1
                } else {
                    target[k] = source[i]
                    i += 1
                }
                k += 1
            }
            while i < middle {
                target[k] = source[i]
                i += 1
                k += 1
            }
            while j < high {
                target[k] = source[j]
                j += 1
                k += 1
            }
            low = high
        }
        swap(&source, &target)
        width *= 2
    }
    return source
}

/// David Eberly's algorithm for finding a bridge between a hole and the outer ring
/// (`find_hole_bridge` in earcutr). Returns `null` when no segment is found.
func findHoleBridge(_ ll: LinkedLists, _ hole: Int, _ outerNode: Int) -> Int {
    var p = outerNode
    let hx = ll.nodes[hole].coord.x
    let hy = ll.nodes[hole].coord.y
    var qx = -Double.infinity
    var m: Int? = nil

    // Find a segment crossed by a ray from the hole's leftmost point to the left. The segment's
    // end with the smaller x is the potential connection point.
    func calcx(_ p: LinkedListNode) -> Double {
        let n = ll.next(p.idx)
        return p.coord.x + (hy - p.coord.y) * (n.coord.x - p.coord.x) / (n.coord.y - p.coord.y)
    }
    repeat {
        let pNode = ll.nodes[p]
        let nNode = ll.next(p)
        if hy <= pNode.coord.y && hy >= nNode.coord.y
            && nNode.coord.y != pNode.coord.y
            && calcx(pNode) <= hx
        {
            if qx < calcx(pNode) {
                qx = calcx(pNode)
                if qx == hx && hy == pNode.coord.y {
                    return pNode.idx
                } else if qx == hx && hy == nNode.coord.y {
                    return pNode.nextLinkedListNodeIndex
                }
                m = pNode.coord.x < nNode.coord.x ? pNode.idx : nNode.idx
            }
        }
        p = ll.nodes[p].nextLinkedListNodeIndex
    } while p != outerNode

    guard let m else {
        return null
    }

    // The hole touches the outer segment: pick the lower end.
    if hx == qx {
        return ll.prev(m).idx
    }

    // Look for points inside the triangle of the hole point, the segment crossing and the end. If
    // none is found, the connection is valid. Otherwise pick the point of the smallest angle with
    // the ray as the connection point.
    let mp = LinkedListNode(0, ll.nodes[m].coord, 0)
    p = ll.next(m).idx
    let x1 = hy < mp.coord.y ? hx : qx
    let x2 = hy < mp.coord.y ? qx : hx
    let n1 = LinkedListNode(0, Coord(x: x1, y: hy), 0)
    let n2 = LinkedListNode(0, Coord(x: x2, y: hy), 0)
    let two = 2.0

    // The tangent of the angle with the ray.
    func calctan(_ p: LinkedListNode) -> Double {
        abs(hy - p.coord.y) / (hx - p.coord.x)
    }
    var best = m
    var tanMin = Double.greatestFiniteMagnitude / two
    repeat {
        let pNode = ll.nodes[p]
        if hx > pNode.coord.x && pNode.coord.x >= mp.coord.x
            && NodeTriangle(n1, mp, n2).containsPoint(pNode)
        {
            if (calctan(pNode) < tanMin
                || (calctan(pNode) == tanMin && pNode.coord.x > ll.nodes[best].coord.x))
                && locallyInside(ll, pNode, ll.nodes[hole])
            {
                best = pNode.idx
                tanMin = calctan(pNode)
            }
        }
        p = ll.nodes[p].nextLinkedListNodeIndex
    } while p != m
    return best
}

/// Links two nodes with a bridge (`split_bridge_polygon` in earcutr).
///
/// When the nodes are in the same ring, this splits it into two rings. When they are in separate
/// rings, this joins them into one. Two new nodes are made, copies of `a` (at index `c`) and of
/// `b` (at index `d`): `a` is linked to `b`, `d` to `c`, `c` to the node after `a`, and the node
/// before `b` to `d`. Returns the new node `d`, the copy of `b`.
func splitBridgePolygon(_ ll: LinkedLists, _ a: Int, _ b: Int) -> Int {
    let cIdx = ll.nodes.count
    let dIdx = cIdx + 1
    var c = LinkedListNode(ll.nodes[a].verticesIndex, ll.nodes[a].coord, cIdx)
    var d = LinkedListNode(ll.nodes[b].verticesIndex, ll.nodes[b].coord, dIdx)

    let an = ll.nodes[a].nextLinkedListNodeIndex
    let bp = ll.nodes[b].prevLinkedListNodeIndex

    ll.nodes[a].nextLinkedListNodeIndex = b
    ll.nodes[b].prevLinkedListNodeIndex = a

    c.nextLinkedListNodeIndex = an
    ll.nodes[an].prevLinkedListNodeIndex = cIdx

    d.nextLinkedListNodeIndex = cIdx
    c.prevLinkedListNodeIndex = dIdx

    ll.nodes[bp].nextLinkedListNodeIndex = dIdx
    d.prevLinkedListNodeIndex = bp

    ll.nodes.append(c)
    ll.nodes.append(d)
    return dIdx
}
