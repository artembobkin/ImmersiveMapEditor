/// Geometric predicates of the earcutr port on segments and diagonals of a ring: crossing
/// segments, a diagonal crossing the polygon, a diagonal locally inside, and its midpoint inside.

/// Whether the segments p1-q1 and p2-q2 cross each other (`pseudo_intersects` in earcutr).
///
/// Unlike a plain intersection test, only two segments crossing at an interior point count.
/// Collinear segments, and segments whose ends touch or that touch the other at one point, do
/// not. The rest of the algorithm depends on this reading. As a special case, two segments with
/// the same two ends always count as crossing.
func pseudoIntersects(
    _ p1: LinkedListNode,
    _ q1: LinkedListNode,
    _ p2: LinkedListNode,
    _ q2: LinkedListNode
) -> Bool {
    if (p1.xyEq(p2) && q1.xyEq(q2)) || (p1.xyEq(q2) && q1.xyEq(p2)) {
        return true
    }
    return (NodeTriangle(p1, q1, p2).area() > 0) != (NodeTriangle(p1, q1, q2).area() > 0)
        && (NodeTriangle(p2, q2, p1).area() > 0) != (NodeTriangle(p2, q2, q1).area() > 0)
}

/// Whether the diagonal a-b crosses any segment of a's ring (`intersects_polygon` in earcutr).
func intersectsPolygon(_ ll: LinkedLists, _ a: LinkedListNode, _ b: LinkedListNode) -> Bool {
    var cur = a.idx
    repeat {
        let p = ll.nodes[cur]
        let n = ll.next(cur)
        if p.verticesIndex != a.verticesIndex
            && n.verticesIndex != a.verticesIndex
            && p.verticesIndex != b.verticesIndex
            && n.verticesIndex != b.verticesIndex
            && pseudoIntersects(p, n, a, b)
        {
            return true
        }
        cur = ll.nodes[cur].nextLinkedListNodeIndex
    } while cur != a.idx
    return false
}

/// Whether the diagonal a-b is locally inside the polygon at a (`locally_inside` in earcutr).
func locallyInside(_ ll: LinkedLists, _ a: LinkedListNode, _ b: LinkedListNode) -> Bool {
    let prev = ll.prev(a.idx)
    let next = ll.next(a.idx)
    if NodeTriangle(prev, a, next).area() < 0 {
        return NodeTriangle(a, b, next).area() >= 0 && NodeTriangle(a, prev, b).area() >= 0
    } else {
        return NodeTriangle(a, b, prev).area() < 0 || NodeTriangle(a, next, b).area() < 0
    }
}

/// Whether the midpoint of the diagonal a-b lies inside a's ring, by counting the crossings of a
/// ray from it (`middle_inside` in earcutr).
func middleInside(_ ll: LinkedLists, _ a: LinkedListNode, _ b: LinkedListNode) -> Bool {
    let two = 1.0 + 1.0
    let mx = (a.coord.x + b.coord.x) / two
    let my = (a.coord.y + b.coord.y) / two
    var inside = false
    var cur = a.idx
    repeat {
        let p = ll.nodes[cur]
        let n = ll.next(cur)
        if (p.coord.y > my) != (n.coord.y > my)
            && n.coord.y != p.coord.y
            && mx < (n.coord.x - p.coord.x) * (my - p.coord.y) / (n.coord.y - p.coord.y) + p.coord.x
        {
            inside = !inside
        }
        cur = ll.nodes[cur].nextLinkedListNodeIndex
    } while cur != a.idx
    return inside
}
