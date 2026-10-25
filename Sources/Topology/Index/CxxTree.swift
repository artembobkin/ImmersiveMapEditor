/// libc++'s `std::set` and `std::map` (its `__tree`, a red-black tree, from
/// the macOS SDK GEOS is built with; Apache License 2.0 with LLVM
/// Exceptions, see the package's licence notes), translated to Swift for the
/// part GEOS's ordered containers use: unique insertion, `find`, and
/// iteration in the tree's order.
///
/// For keys of a strict weak order a sorted array gives the same answers.
/// A key with a NaN ordinate breaks the order (it is equivalent to every
/// other key), and then what `find` and insertion answer depends on the
/// tree's shape, which only the same insertions and rotations reproduce.
struct CxxTree<Key, Value> {
    struct Node {
        var key: Key
        var value: Value
        var left = -1
        var right = -1
        /// The parent node, or `end` for the root.
        var parent = CxxTree.end
        var isBlack = false
    }

    /// The end node's index (the root's parent).
    static var end: Int { -2 }

    private(set) var nodes: [Node] = []
    /// The end node's left child: the root.
    private var root = -1
    let less: (Key, Key) -> Bool

    init(_ less: @escaping (Key, Key) -> Bool) { self.less = less }

    var count: Int { nodes.count }

    private func leftOf(_ n: Int) -> Int { n == CxxTree.end ? root : nodes[n].left }

    private mutating func setLeft(_ n: Int, _ c: Int) {
        if n == CxxTree.end { root = c } else { nodes[n].left = c }
    }

    private func isLeftChild(_ x: Int) -> Bool { leftOf(nodes[x].parent) == x }

    /// Inserts the key if no equivalent key is there; the index of the
    /// key's node, and whether it was inserted.
    @discardableResult
    mutating func insert(_ key: Key, _ value: Value) -> (Int, Bool) {
        // __find_equal
        var parent = CxxTree.end
        var asLeft = true
        var nd = root
        if nd >= 0 {
            while true {
                if less(key, nodes[nd].key) {
                    if nodes[nd].left >= 0 { nd = nodes[nd].left } else { parent = nd; asLeft = true; break }
                } else if less(nodes[nd].key, key) {
                    if nodes[nd].right >= 0 { nd = nodes[nd].right } else { parent = nd; asLeft = false; break }
                } else {
                    return (nd, false)
                }
            }
        }
        let x = nodes.count
        var node = Node(key: key, value: value)
        node.parent = parent
        nodes.append(node)
        if asLeft { setLeft(parent, x) } else { nodes[parent].right = x }
        balanceAfterInsert(x)
        return (x, true)
    }

    /// The value of a node, changed in place (`map[key]++` after an insert).
    mutating func modify(_ i: Int, _ change: (inout Value) -> Void) { change(&nodes[i].value) }

    /// The node of a key equivalent to `key`, if any.
    func find(_ key: Key) -> Int? {
        // __lower_bound
        var result = CxxTree.end
        var r = root
        while r >= 0 {
            if !less(nodes[r].key, key) {
                result = r
                r = nodes[r].left
            } else {
                r = nodes[r].right
            }
        }
        if result != CxxTree.end && !less(key, nodes[result].key) { return result }
        return nil
    }

    /// The nodes in the tree's order (in-order).
    func inOrder() -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(nodes.count)
        var stack: [Int] = []
        var n = root
        while n >= 0 || !stack.isEmpty {
            while n >= 0 {
                stack.append(n)
                n = nodes[n].left
            }
            let top = stack.removeLast()
            out.append(top)
            n = nodes[top].right
        }
        return out
    }

    private mutating func leftRotate(_ x: Int) {
        let y = nodes[x].right
        nodes[x].right = nodes[y].left
        if nodes[x].right >= 0 { nodes[nodes[x].right].parent = x }
        nodes[y].parent = nodes[x].parent
        if isLeftChild(x) { setLeft(nodes[x].parent, y) } else { nodes[nodes[x].parent].right = y }
        nodes[y].left = x
        nodes[x].parent = y
    }

    private mutating func rightRotate(_ x: Int) {
        let y = nodes[x].left
        nodes[x].left = nodes[y].right
        if nodes[x].left >= 0 { nodes[nodes[x].left].parent = x }
        nodes[y].parent = nodes[x].parent
        if isLeftChild(x) { setLeft(nodes[x].parent, y) } else { nodes[nodes[x].parent].right = y }
        nodes[y].right = x
        nodes[x].parent = y
    }

    /// __tree_balance_after_insert.
    private mutating func balanceAfterInsert(_ start: Int) {
        var x = start
        nodes[x].isBlack = x == root
        while x != root && !nodes[nodes[x].parent].isBlack {
            let p = nodes[x].parent
            if isLeftChild(p) {
                let y = nodes[nodes[p].parent].right
                if y >= 0 && !nodes[y].isBlack {
                    x = p
                    nodes[x].isBlack = true
                    x = nodes[x].parent
                    nodes[x].isBlack = x == root
                    nodes[y].isBlack = true
                } else {
                    if !isLeftChild(x) {
                        x = nodes[x].parent
                        leftRotate(x)
                    }
                    x = nodes[x].parent
                    nodes[x].isBlack = true
                    x = nodes[x].parent
                    nodes[x].isBlack = false
                    rightRotate(x)
                    break
                }
            } else {
                let y = leftOf(nodes[p].parent)
                if y >= 0 && !nodes[y].isBlack {
                    x = p
                    nodes[x].isBlack = true
                    x = nodes[x].parent
                    nodes[x].isBlack = x == root
                    nodes[y].isBlack = true
                } else {
                    if isLeftChild(x) {
                        x = nodes[x].parent
                        rightRotate(x)
                    }
                    x = nodes[x].parent
                    nodes[x].isBlack = true
                    x = nodes[x].parent
                    nodes[x].isBlack = false
                    leftRotate(x)
                    break
                }
            }
        }
    }
}
