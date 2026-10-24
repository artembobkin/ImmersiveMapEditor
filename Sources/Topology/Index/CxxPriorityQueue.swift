/// `std::priority_queue` of libc++ over an array: the top is the greatest
/// by `less` (pass `>` for the least first).
struct CxxPriorityQueue<Element> {
    private(set) var heap: [Element] = []
    let less: (Element, Element) -> Bool

    init(_ less: @escaping (Element, Element) -> Bool) { self.less = less }

    var isEmpty: Bool { heap.isEmpty }
    var count: Int { heap.count }
    var top: Element? { heap.first }

    mutating func push(_ x: Element) {
        heap.append(x)
        CxxAlgorithms.pushHeap(&heap, 0, heap.count, less)
    }

    mutating func pop() {
        CxxAlgorithms.popHeap(&heap, 0, heap.count, less)
        heap.removeLast()
    }
}
