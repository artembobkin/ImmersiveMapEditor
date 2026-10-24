/// A binary heap that orders as Java's `java.util.PriorityQueue` does, the
/// same sift up and sift down, so elements that compare equal come out in
/// the order JTS's searches see them.
struct JavaPriorityQueue<Element> {
    private var queue: [Element] = []
    private let compare: (Element, Element) -> Int

    init(_ compare: @escaping (Element, Element) -> Int) { self.compare = compare }

    var isEmpty: Bool { queue.isEmpty }
    var count: Int { queue.count }
    var peek: Element? { queue.first }

    mutating func add(_ x: Element) {
        queue.append(x)
        var k = queue.count - 1
        while k > 0 {
            let parent = (k - 1) >> 1
            let e = queue[parent]
            if compare(x, e) >= 0 { break }
            queue[k] = e
            k = parent
        }
        queue[k] = x
    }

    mutating func poll() -> Element? {
        guard !queue.isEmpty else { return nil }
        let result = queue[0]
        let x = queue.removeLast()
        let n = queue.count
        if n > 0 {
            var k = 0
            let half = n >> 1
            while k < half {
                var child = 2 * k + 1
                var c = queue[child]
                let right = child + 1
                if right < n && compare(c, queue[right]) > 0 {
                    child = right
                    c = queue[child]
                }
                if compare(x, c) <= 0 { break }
                queue[k] = c
                k = child
            }
            queue[k] = x
        }
        return result
    }
}
