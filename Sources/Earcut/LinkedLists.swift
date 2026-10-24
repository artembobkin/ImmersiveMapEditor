/// The node arena of the earcutr port: circular doubly linked rings of polygon vertices kept as
/// indices into one array, with the z-order links, the bounding box used for hashing, and the
/// operations that build, edit and sort the rings.

/// One vertex of a polygon ring (`LinkedListNode` in earcutr).
struct LinkedListNode {
    /// The vertex index in the flat coordinate array, that is the coordinate offset divided by two.
    var verticesIndex: Int
    /// The vertex position.
    var coord: Coord
    /// The previous node in the polygon ring.
    var prevLinkedListNodeIndex: Int
    /// The next node in the polygon ring.
    var nextLinkedListNodeIndex: Int
    /// The z-order curve value.
    var z: Int32
    /// The previous node in z-order.
    var prevzIdx: Int
    /// The next node in z-order.
    var nextzIdx: Int
    /// Whether this is a Steiner point (a hole of a single vertex).
    var isSteinerPoint: Bool
    /// The index of this node in the arena.
    var idx: Int

    init(_ verticesIndex: Int, _ coord: Coord, _ idx: Int) {
        self.verticesIndex = verticesIndex
        self.coord = coord
        self.prevLinkedListNodeIndex = null
        self.nextLinkedListNodeIndex = null
        self.z = 0
        self.prevzIdx = null
        self.nextzIdx = null
        self.isSteinerPoint = false
        self.idx = idx
    }

    /// Whether two nodes stand at the same point.
    @inline(__always)
    func xyEq(_ other: LinkedListNode) -> Bool {
        coord == other.coord
    }
}

/// All the rings of one triangulation (`LinkedLists` in earcutr).
///
/// `nodes[0]` is the sentinel node `null`. Nodes are never freed: a removed node keeps its own
/// links, and the algorithm relies on reading them after the removal, as the Rust code does.
final class LinkedLists {
    var nodes: [LinkedListNode]
    var invsize: Double = 0
    var min = Coord(x: Double.greatestFiniteMagnitude, y: Double.greatestFiniteMagnitude)
    var max = Coord(x: -Double.greatestFiniteMagnitude, y: -Double.greatestFiniteMagnitude)
    var usehash = true

    init(sizeHint: Int) {
        nodes = []
        nodes.reserveCapacity(sizeHint)
        var sentinel = LinkedListNode(0, Coord(x: 0, y: 0), 0)
        sentinel.prevLinkedListNodeIndex = 0
        sentinel.nextLinkedListNodeIndex = 0
        nodes.append(sentinel)
    }

    /// The node after the node at `idx` in its ring.
    @inline(__always)
    func next(_ idx: Int) -> LinkedListNode {
        nodes[nodes[idx].nextLinkedListNodeIndex]
    }

    /// The node before the node at `idx` in its ring.
    @inline(__always)
    func prev(_ idx: Int) -> LinkedListNode {
        nodes[nodes[idx].prevLinkedListNodeIndex]
    }

    /// Appends a node and links it after `last`, or makes it a ring of its own when `last` is nil.
    func insertNode(_ i: Int, _ coord: Coord, _ last: Int?) -> Int {
        var p = LinkedListNode(i, coord, nodes.count)
        if let last {
            p.nextLinkedListNodeIndex = nodes[last].nextLinkedListNodeIndex
            p.prevLinkedListNodeIndex = last
            let lastNextIdx = nodes[last].nextLinkedListNodeIndex
            nodes[lastNextIdx].prevLinkedListNodeIndex = p.idx
            nodes[last].nextLinkedListNodeIndex = p.idx
        } else {
            p.nextLinkedListNodeIndex = p.idx
            p.prevLinkedListNodeIndex = p.idx
        }
        let result = p.idx
        nodes.append(p)
        return result
    }

    /// Unlinks a node from its ring and from the z-order list, leaving its own links as they are.
    func removeNode(_ pIdx: Int) {
        let pi = nodes[pIdx].prevLinkedListNodeIndex
        let ni = nodes[pIdx].nextLinkedListNodeIndex
        let pz = nodes[pIdx].prevzIdx
        let nz = nodes[pIdx].nextzIdx
        nodes[pi].nextLinkedListNodeIndex = ni
        nodes[ni].prevLinkedListNodeIndex = pi
        nodes[pz].nextzIdx = nz
        nodes[nz].prevzIdx = pz
    }

    /// Interlinks the nodes of a ring in z-order.
    func indexCurve(_ start: Int) throws {
        let invsize = self.invsize
        var p = start
        while true {
            if nodes[p].z == 0 {
                nodes[p].z = try nodes[p].coord.zorder(invsize)
            }
            nodes[p].prevzIdx = nodes[p].prevLinkedListNodeIndex
            nodes[p].nextzIdx = nodes[p].nextLinkedListNodeIndex
            p = nodes[p].nextLinkedListNodeIndex
            if p == start {
                break
            }
        }

        let pzi = nodes[start].prevzIdx
        nodes[pzi].nextzIdx = null
        nodes[start].prevzIdx = null
        sortLinked(start)
    }

    /// Finds a bridge between a hole and the outer ring and links the hole in through it.
    func eliminateHole(_ holeIdx: Int, _ outerNodeIdx: Int) {
        let testIdx = findHoleBridge(self, holeIdx, outerNodeIdx)
        let b = splitBridgePolygon(self, testIdx, holeIdx)
        let ni = nodes[b].nextLinkedListNodeIndex
        _ = filterPoints(self, b, ni)
    }

    /// Sorts the z-order list starting at `list` by `z`, with Simon Tatham's linked list merge sort.
    ///
    /// See http://www.chiark.greenend.org.uk/~sgtatham/algorithms/listsort.html
    func sortLinked(_ start: Int) {
        var list = start
        var p: Int
        var q: Int
        var e: Int
        var numMerges: Int
        var pSize: Int
        var qSize: Int
        var inSize = 1
        var tail: Int

        while true {
            p = list
            list = null
            tail = null
            numMerges = 0

            while p != null {
                numMerges += 1
                q = p
                pSize = 0
                while q != null && pSize < inSize {
                    pSize += 1
                    q = nodes[q].nextzIdx
                }
                qSize = inSize

                while pSize > 0 || (qSize > 0 && q != null) {
                    if pSize > 0 && (qSize == 0 || q == null || nodes[p].z <= nodes[q].z) {
                        e = p
                        p = nodes[p].nextzIdx
                        pSize -= 1
                    } else {
                        e = q
                        q = nodes[q].nextzIdx
                        qSize -= 1
                    }

                    if tail != null {
                        nodes[tail].nextzIdx = e
                    } else {
                        list = e
                    }

                    nodes[e].prevzIdx = tail
                    tail = e
                }

                p = q
            }

            nodes[tail].nextzIdx = null
            inSize *= 2
            if numMerges <= 1 {
                break
            }
        }
    }

    /// Adds the ring `vertices[start..<end]` as a new linked ring, wound clockwise or not.
    ///
    /// Returns the last node added and the leftmost node. The bounding box for hashing reads the
    /// array at the offsets relative to `start`, not at the absolute ones, exactly as earcutr 0.4.3
    /// does: for a hole this reads the outer ring's values.
    func addContour(
        _ vertices: Vertices, _ start: Int, _ end: Int, _ clockwise: Bool
    ) throws -> (Int, Int) {
        if start > vertices.count || end > vertices.count || vertices.isEmpty {
            throw EarcutError.unknown
        }
        if end < dim || end - dim < start {
            throw EarcutError.unknown
        }

        var lastIdx: Int? = nil
        var leftmostIdx: Int? = nil
        var contourMinX = Double.greatestFiniteMagnitude

        func body(_ xIndex: Int, _ x: Double, _ yIndex: Int, _ y: Double) {
            lastIdx = insertNode((start + xIndex) / dim, Coord(x: x, y: y), lastIdx)
            if contourMinX > x {
                contourMinX = x
                leftmostIdx = lastIdx
            }
            if usehash {
                min.y = rustMin(vertices[yIndex], min.y)
                max.x = rustMax(vertices[xIndex], max.x)
                max.y = rustMax(vertices[yIndex], max.y)
            }
        }

        let length = end - start
        if clockwise == (vertices.signedArea(start, end) > 0) {
            var k = 0
            while k + 1 < length {
                body(k, vertices[start + k], k + 1, vertices[start + k + 1])
                k += 2
            }
        } else {
            // The Rust code walks the slice backwards and takes the elements in pairs (y, x).
            var k = length - 1
            while k - 1 >= 0 {
                body(k - 1, vertices[start + k - 1], k, vertices[start + k])
                k -= 2
            }
        }

        min.x = rustMin(contourMinX, min.x)

        if nodes[lastIdx!].xyEq(next(lastIdx!)) {
            removeNode(lastIdx!)
            lastIdx = nodes[lastIdx!].nextLinkedListNodeIndex
        }
        return (lastIdx!, leftmostIdx!)
    }

    /// Whether a diagonal between two nodes is valid, that is lies in the polygon's interior.
    func isValidDiagonal(_ a: LinkedListNode, _ b: LinkedListNode) -> Bool {
        next(a.idx).verticesIndex != b.verticesIndex
            && prev(a.idx).verticesIndex != b.verticesIndex
            && !intersectsPolygon(self, a, b)
            && locallyInside(self, a, b)
            && locallyInside(self, b, a)
            && middleInside(self, a, b)
    }
}

/// Creates the arena with one ring of `vertices[start..<end]` (`linked_list` in earcutr).
///
/// Hashing is off for inputs of fewer than 80 coordinates.
func linkedList(
    _ vertices: Vertices, _ start: Int, _ end: Int, _ clockwise: Bool
) throws -> (LinkedLists, Int) {
    let ll = LinkedLists(sizeHint: vertices.count / dim)
    if vertices.count < 80 {
        ll.usehash = false
    }
    let (lastIdx, _) = try ll.addContour(vertices, start, end, clockwise)
    return (ll, lastIdx)
}
