/// Triangles of nodes in the earcutr port: their signed area, the point in triangle test, and
/// the two ear tests, the plain one that scans the ring and the hashed one that scans the
/// z-order neighbourhood.

/// Three node indices taken as a triangle (`NodeIndexTriangle` in earcutr).
struct NodeIndexTriangle {
    let prev: Int
    let ear: Int
    let next: Int

    init(_ prev: Int, _ ear: Int, _ next: Int) {
        self.prev = prev
        self.ear = ear
        self.next = next
    }

    func nodeTriangle(_ ll: LinkedLists) -> NodeTriangle {
        NodeTriangle(ll.nodes[prev], ll.nodes[ear], ll.nodes[next])
    }

    func area(_ ll: LinkedLists) -> Double {
        nodeTriangle(ll).area()
    }

    /// Whether the ear node forms a valid ear with its neighbours, scanning the whole ring.
    func isEar(_ ll: LinkedLists) -> Bool {
        if area(ll) >= 0 {
            // A reflex vertex cannot be an ear.
            return false
        }
        let triangle = nodeTriangle(ll)
        // The scan runs from the node after `next` up to, but not including, `prev`. Its first node
        // is visited even when it is `prev` itself, and then the scan goes round the whole ring.
        let end = ll.nodes[prev].idx
        var cur = ll.nodes[next].nextLinkedListNodeIndex
        repeat {
            let p = ll.nodes[cur]
            if triangle.containsPoint(p)
                && NodeTriangle(ll.prev(p.idx), p, ll.next(p.idx)).area() >= 0
            {
                return false
            }
            cur = ll.nodes[cur].nextLinkedListNodeIndex
        } while cur != end
        return true
    }
}

/// Three nodes taken as a triangle, copied at the time it is made (`NodeTriangle` in earcutr).
struct NodeTriangle {
    let a: LinkedListNode
    let b: LinkedListNode
    let c: LinkedListNode

    init(_ a: LinkedListNode, _ b: LinkedListNode, _ c: LinkedListNode) {
        self.a = a
        self.b = b
        self.c = c
    }

    /// The triangle of a node and its two neighbours in the ring.
    static func fromEarNode(_ earNode: LinkedListNode, _ ll: LinkedLists) -> NodeTriangle {
        NodeTriangle(
            ll.nodes[earNode.prevLinkedListNodeIndex],
            earNode,
            ll.nodes[earNode.nextLinkedListNodeIndex]
        )
    }

    /// The signed area of the parallelogram on the triangle's sides.
    @inline(__always)
    func area() -> Double {
        let p = a.coord
        let q = b.coord
        let r = c.coord
        return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
    }

    /// Whether a point lies within the triangle, taken as convex, its boundary included.
    @inline(__always)
    func containsPoint(_ p: LinkedListNode) -> Bool {
        let p = p.coord
        let a = self.a.coord
        let b = self.b.coord
        let c = self.c.coord
        return ((c.x - p.x) * (a.y - p.y) - (a.x - p.x) * (c.y - p.y) >= 0)
            && ((a.x - p.x) * (b.y - p.y) - (b.x - p.x) * (a.y - p.y) >= 0)
            && ((b.x - p.x) * (c.y - p.y) - (c.x - p.x) * (b.y - p.y) >= 0)
    }

    /// Whether the middle node forms a valid ear, scanning only the nodes whose z-order lies within
    /// the z-order range of the triangle's bounding box.
    ///
    /// It writes the sentinel node's `z` to stop the scans, as the Rust code does.
    func isEarHashed(_ ll: LinkedLists) throws -> Bool {
        if area() >= 0 {
            return false
        }
        let prev = a
        let ear = b
        let next = c

        let bboxMaxX = rustMax(prev.coord.x, rustMax(ear.coord.x, next.coord.x))
        let bboxMaxY = rustMax(prev.coord.y, rustMax(ear.coord.y, next.coord.y))
        let bboxMinX = rustMin(prev.coord.x, rustMin(ear.coord.x, next.coord.x))
        let bboxMinY = rustMin(prev.coord.y, rustMin(ear.coord.y, next.coord.y))
        // The z-order range of the triangle's bounding box.
        let minZ = try Coord(x: bboxMinX, y: bboxMinY).zorder(ll.invsize)
        let maxZ = try Coord(x: bboxMaxX, y: bboxMaxY).zorder(ll.invsize)

        var p = ear.prevzIdx
        var n = ear.nextzIdx
        while p != null && ll.nodes[p].z >= minZ && n != null && ll.nodes[n].z <= maxZ {
            if earcheck(prev, ear, next, ll.prev(p), ll.nodes[p], ll.next(p)) {
                return false
            }
            p = ll.nodes[p].prevzIdx

            if earcheck(prev, ear, next, ll.prev(n), ll.nodes[n], ll.next(n)) {
                return false
            }
            n = ll.nodes[n].nextzIdx
        }

        ll.nodes[null].z = minZ &- 1
        while ll.nodes[p].z >= minZ {
            if earcheck(prev, ear, next, ll.prev(p), ll.nodes[p], ll.next(p)) {
                return false
            }
            p = ll.nodes[p].prevzIdx
        }

        ll.nodes[null].z = maxZ &+ 1
        while ll.nodes[n].z <= maxZ {
            if earcheck(prev, ear, next, ll.prev(n), ll.nodes[n], ll.next(n)) {
                return false
            }
            n = ll.nodes[n].nextzIdx
        }

        return true
    }
}

/// Whether the node `p` (with its neighbours `prev` and `next`) spoils the ear `a, b, c`: it is
/// not a corner of the ear, lies within it, and is not reflex.
@inline(__always)
func earcheck(
    _ a: LinkedListNode,
    _ b: LinkedListNode,
    _ c: LinkedListNode,
    _ prev: LinkedListNode,
    _ p: LinkedListNode,
    _ next: LinkedListNode
) -> Bool {
    (p.idx != a.idx)
        && (p.idx != c.idx)
        && NodeTriangle(a, b, c).containsPoint(p)
        && NodeTriangle(prev, p, next).area() >= 0
}
