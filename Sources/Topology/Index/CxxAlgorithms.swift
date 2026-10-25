/// `std::sort` and the heap algorithms of libc++ (LLVM, Apache License 2.0
/// with LLVM Exceptions, the version of the macOS SDK this package builds
/// with), translated to Swift.
///
/// GEOS is C++ and sorts and queues with them where JTS uses Java's stable
/// sort and `PriorityQueue`. Where elements compare equal, the order they end
/// in is the algorithm's own, so a port that must break ties as GEOS does
/// runs the same algorithm: an introsort (insertion sort below 24 elements,
/// median of three or Tukey's ninther, partitions keeping equal elements on
/// one side, heap sort past the depth limit) and binary heaps with Floyd's
/// sift down. The comparator is a strict weak order, `less(a, b)`.
enum CxxAlgorithms {
    // MARK: Heaps

    static func siftUp<T>(_ a: inout [T], _ first: Int, _ last: Int, _ less: (T, T) -> Bool) {
        var len = last - first
        guard len > 1 else { return }
        len = (len - 2) / 2
        var ptr = first + len
        var hole = last - 1
        guard less(a[ptr], a[hole]) else { return }
        let t = a[hole]
        repeat {
            a[hole] = a[ptr]
            hole = ptr
            if len == 0 { break }
            len = (len - 1) / 2
            ptr = first + len
        } while less(a[ptr], t)
        a[hole] = t
    }

    static func siftDown<T>(_ a: inout [T], _ first: Int, _ len: Int, _ start: Int, _ less: (T, T) -> Bool) {
        var child = start - first
        if len < 2 || (len - 2) / 2 < child { return }
        child = 2 * child + 1
        var childI = first + child
        if child + 1 < len && less(a[childI], a[childI + 1]) {
            childI += 1
            child += 1
        }
        if less(a[childI], a[start]) { return }
        let top = a[start]
        var s = start
        repeat {
            a[s] = a[childI]
            s = childI
            if (len - 2) / 2 < child { break }
            child = 2 * child + 1
            childI = first + child
            if child + 1 < len && less(a[childI], a[childI + 1]) {
                childI += 1
                child += 1
            }
        } while !less(a[childI], top)
        a[s] = top
    }

    static func floydSiftDown<T>(_ a: inout [T], _ first: Int, _ len: Int, _ less: (T, T) -> Bool) -> Int {
        var hole = first
        var childI = first
        var child = 0
        while true {
            childI += child + 1
            child = 2 * child + 1
            if child + 1 < len && less(a[childI], a[childI + 1]) {
                childI += 1
                child += 1
            }
            a[hole] = a[childI]
            hole = childI
            if child > (len - 2) / 2 { return hole }
        }
    }

    static func pushHeap<T>(_ a: inout [T], _ first: Int, _ last: Int, _ less: (T, T) -> Bool) {
        siftUp(&a, first, last, less)
    }

    static func popHeap<T>(_ a: inout [T], _ first: Int, _ last: Int, _ less: (T, T) -> Bool) {
        let len = last - first
        guard len > 1 else { return }
        let top = a[first]
        var hole = floydSiftDown(&a, first, len, less)
        let l = last - 1
        if hole == l {
            a[hole] = top
        } else {
            a[hole] = a[l]
            hole += 1
            a[l] = top
            siftUp(&a, first, hole, less)
        }
    }

    static func makeHeap<T>(_ a: inout [T], _ first: Int, _ last: Int, _ less: (T, T) -> Bool) {
        let n = last - first
        guard n > 1 else { return }
        var start = (n - 2) / 2
        while start >= 0 {
            siftDown(&a, first, n, first + start, less)
            start -= 1
        }
    }

    static func sortHeap<T>(_ a: inout [T], _ first: Int, _ last: Int, _ less: (T, T) -> Bool) {
        var l = last
        while l - first > 1 {
            popHeap(&a, first, l, less)
            l -= 1
        }
    }

    // MARK: std::sort

    static func sort<T>(_ a: inout [T], _ less: (T, T) -> Bool) { sort(&a, 0, a.count, less) }

    static func sort<T>(_ a: inout [T], _ first: Int, _ last: Int, _ less: (T, T) -> Bool) {
        if first == last { return }
        let n = UInt(last - first)
        let depth = 2 * (UInt.bitWidth - 1 - n.leadingZeroBitCount)
        introsort(&a, first, last, less, depth, true)
    }

    @discardableResult
    static func sort3<T>(_ a: inout [T], _ x: Int, _ y: Int, _ z: Int, _ c: (T, T) -> Bool) -> Bool {
        if !c(a[y], a[x]) {
            if !c(a[z], a[y]) { return false }
            a.swapAt(y, z)
            if c(a[y], a[x]) { a.swapAt(x, y) }
            return true
        }
        if c(a[z], a[y]) {
            a.swapAt(x, z)
            return true
        }
        a.swapAt(x, y)
        if c(a[z], a[y]) { a.swapAt(y, z) }
        return true
    }

    static func sort4<T>(_ a: inout [T], _ x1: Int, _ x2: Int, _ x3: Int, _ x4: Int, _ c: (T, T) -> Bool) {
        sort3(&a, x1, x2, x3, c)
        if c(a[x4], a[x3]) {
            a.swapAt(x3, x4)
            if c(a[x3], a[x2]) {
                a.swapAt(x2, x3)
                if c(a[x2], a[x1]) { a.swapAt(x1, x2) }
            }
        }
    }

    static func sort5<T>(_ a: inout [T], _ x1: Int, _ x2: Int, _ x3: Int, _ x4: Int, _ x5: Int, _ c: (T, T) -> Bool) {
        sort4(&a, x1, x2, x3, x4, c)
        if c(a[x5], a[x4]) {
            a.swapAt(x4, x5)
            if c(a[x4], a[x3]) {
                a.swapAt(x3, x4)
                if c(a[x3], a[x2]) {
                    a.swapAt(x2, x3)
                    if c(a[x2], a[x1]) { a.swapAt(x1, x2) }
                }
            }
        }
    }

    static func insertionSort<T>(_ a: inout [T], _ first: Int, _ last: Int, _ c: (T, T) -> Bool) {
        if first == last { return }
        var i = first + 1
        while i != last {
            var j = i - 1
            if c(a[i], a[j]) {
                let t = a[i]
                var k = j
                j = i
                repeat {
                    a[j] = a[k]
                    j = k
                    if j == first { break }
                    k -= 1
                } while c(t, a[k])
                a[j] = t
            }
            i += 1
        }
    }

    /// Insertion sort with an element before `first` that is not greater
    /// than any in the range, so the inner loop needs no bound.
    static func insertionSortUnguarded<T>(_ a: inout [T], _ first: Int, _ last: Int, _ c: (T, T) -> Bool) {
        if first == last { return }
        var i = first + 1
        while i != last {
            var j = i - 1
            if c(a[i], a[j]) {
                let t = a[i]
                var k = j
                j = i
                repeat {
                    a[j] = a[k]
                    j = k
                    k -= 1
                } while c(t, a[k])
                a[j] = t
            }
            i += 1
        }
    }

    /// Sorts small ranges, and a larger one only if it takes at most eight
    /// moves: whether it is sorted.
    static func insertionSortIncomplete<T>(_ a: inout [T], _ first: Int, _ last: Int, _ c: (T, T) -> Bool) -> Bool {
        switch last - first {
        case 0, 1: return true
        case 2:
            if c(a[last - 1], a[first]) { a.swapAt(first, last - 1) }
            return true
        case 3:
            sort3(&a, first, first + 1, last - 1, c)
            return true
        case 4:
            sort4(&a, first, first + 1, first + 2, last - 1, c)
            return true
        case 5:
            sort5(&a, first, first + 1, first + 2, first + 3, last - 1, c)
            return true
        default: break
        }
        var j = first + 2
        sort3(&a, first, first + 1, j, c)
        let limit = 8
        var count = 0
        var i = j + 1
        while i != last {
            if c(a[i], a[j]) {
                let t = a[i]
                var k = j
                j = i
                repeat {
                    a[j] = a[k]
                    j = k
                    if j == first { break }
                    k -= 1
                } while c(t, a[k])
                a[j] = t
                count += 1
                if count == limit {
                    i += 1
                    return i == last
                }
            }
            j = i
            i += 1
        }
        return true
    }

    /// Partitions around the pivot at `first`, equal elements to its right:
    /// the pivot's place, and whether the range was already partitioned.
    static func partitionWithEqualsOnRight<T>(_ a: inout [T], _ firstIn: Int, _ lastIn: Int, _ c: (T, T) -> Bool) -> (Int, Bool) {
        let begin = firstIn
        var first = firstIn, last = lastIn
        let pivot = a[first]
        repeat { first += 1 } while c(a[first], pivot)
        if begin == first - 1 {
            while first < last {
                last -= 1
                if c(a[last], pivot) { break }
            }
        } else {
            repeat { last -= 1 } while !c(a[last], pivot)
        }
        let alreadyPartitioned = first >= last
        while first < last {
            a.swapAt(first, last)
            repeat { first += 1 } while c(a[first], pivot)
            repeat { last -= 1 } while !c(a[last], pivot)
        }
        let pivotPos = first - 1
        if begin != pivotPos { a[begin] = a[pivotPos] }
        a[pivotPos] = pivot
        return (pivotPos, alreadyPartitioned)
    }

    /// Partitions around the pivot at `first`, equal elements to its left:
    /// the first element after the pivot's place.
    static func partitionWithEqualsOnLeft<T>(_ a: inout [T], _ firstIn: Int, _ lastIn: Int, _ c: (T, T) -> Bool) -> Int {
        let begin = firstIn
        var first = firstIn, last = lastIn
        let pivot = a[first]
        if c(pivot, a[last - 1]) {
            repeat { first += 1 } while !c(pivot, a[first])
        } else {
            first += 1
            while first < last && !c(pivot, a[first]) { first += 1 }
        }
        if first < last {
            repeat { last -= 1 } while c(pivot, a[last])
        }
        while first < last {
            a.swapAt(first, last)
            repeat { first += 1 } while !c(pivot, a[first])
            repeat { last -= 1 } while c(pivot, a[last])
        }
        let pivotPos = first - 1
        if begin != pivotPos { a[begin] = a[pivotPos] }
        a[pivotPos] = pivot
        return first
    }

    static func introsort<T>(_ a: inout [T], _ firstIn: Int, _ lastIn: Int, _ c: (T, T) -> Bool, _ depthIn: Int, _ leftmostIn: Bool) {
        let limit = 24, nintherThreshold = 128
        var first = firstIn, last = lastIn, depth = depthIn, leftmost = leftmostIn
        while true {
            let len = last - first
            switch len {
            case 0, 1: return
            case 2:
                if c(a[last - 1], a[first]) { a.swapAt(first, last - 1) }
                return
            case 3:
                sort3(&a, first, first + 1, last - 1, c)
                return
            case 4:
                sort4(&a, first, first + 1, first + 2, last - 1, c)
                return
            case 5:
                sort5(&a, first, first + 1, first + 2, first + 3, last - 1, c)
                return
            default: break
            }
            if len < limit {
                if leftmost { insertionSort(&a, first, last, c) } else { insertionSortUnguarded(&a, first, last, c) }
                return
            }
            if depth == 0 {
                // Heap sort, as std::__partial_sort(first, last, last).
                makeHeap(&a, first, last, c)
                sortHeap(&a, first, last, c)
                return
            }
            depth -= 1
            let halfLen = len / 2
            if len > nintherThreshold {
                sort3(&a, first, first + halfLen, last - 1, c)
                sort3(&a, first + 1, first + (halfLen - 1), last - 2, c)
                sort3(&a, first + 2, first + (halfLen + 1), last - 3, c)
                sort3(&a, first + (halfLen - 1), first + halfLen, first + (halfLen + 1), c)
                a.swapAt(first, first + halfLen)
            } else {
                sort3(&a, first + halfLen, first, last - 1, c)
            }
            if !leftmost && !c(a[first - 1], a[first]) {
                first = partitionWithEqualsOnLeft(&a, first, last, c)
                continue
            }
            let (pivot, alreadyPartitioned) = partitionWithEqualsOnRight(&a, first, last, c)
            var i = pivot
            if alreadyPartitioned {
                let fs = insertionSortIncomplete(&a, first, i, c)
                if insertionSortIncomplete(&a, i + 1, last, c) {
                    if fs { return }
                    last = i
                    continue
                } else if fs {
                    i += 1
                    first = i
                    continue
                }
            }
            introsort(&a, first, i, c, depth, leftmost)
            leftmost = false
            i += 1
            first = i
        }
    }
}

// MARK: Doubles with the default comparator

extension CxxAlgorithms {
    /// `std::sort` of doubles with `operator<`, as the system's libc++ runs
    /// it (`std::__sort<__less<double>&, double*>`): its arithmetic types
    /// take the branchless sorting networks for two to five elements (each
    /// step a conditional swap, `__cond_swap` and `__partially_sorted_swap`),
    /// then insertion sort below 24, as the generic sort. For doubles that
    /// compare in a total order every sort gives the same values in the same
    /// places; the networks matter for NaN, which compares false with all,
    /// and for zeros of either sign. Arrays of 24 and more, where libc++
    /// partitions with bitsets, are sorted by the generic introsort here
    /// (the same result for doubles without NaN, but for the order of equal
    /// zeros).
    static func sortDoubles(_ a: inout [Double]) {
        let less: (Double, Double) -> Bool = { $0 < $1 }
        switch a.count {
        case 0, 1: return
        case 2: if a[1] < a[0] { a.swapAt(0, 1) }
        case 3: branchlessSort3(&a, 0, 1, 2)
        case 4:
            condSwap(&a, 0, 2); condSwap(&a, 1, 3); condSwap(&a, 0, 1); condSwap(&a, 2, 3); condSwap(&a, 1, 2)
        case 5:
            condSwap(&a, 0, 1); condSwap(&a, 3, 4); partiallySortedSwap(&a, 2, 3, 4)
            condSwap(&a, 1, 4); partiallySortedSwap(&a, 0, 2, 3); partiallySortedSwap(&a, 1, 2, 3)
        case ..<24: insertionSort(&a, 0, a.count, less)
        default: sort(&a, less)
        }
    }

    /// `__cond_swap`: `a[x] < a[y]` made true by a swap where needed.
    static func condSwap(_ a: inout [Double], _ x: Int, _ y: Int) {
        let r = a[x] < a[y]
        let tmp = r ? a[x] : a[y]
        a[y] = r ? a[y] : a[x]
        a[x] = tmp
    }

    /// `__partially_sorted_swap`: the three ordered, `a[y]` and `a[z]` being so.
    static func partiallySortedSwap(_ a: inout [Double], _ x: Int, _ y: Int, _ z: Int) {
        let r1 = a[z] < a[x]
        let tmp = r1 ? a[z] : a[x]
        a[z] = r1 ? a[x] : a[z]
        let r2 = tmp < a[y]
        a[x] = r2 ? a[x] : a[y]
        a[y] = r2 ? a[y] : tmp
    }

    static func branchlessSort3(_ a: inout [Double], _ x: Int, _ y: Int, _ z: Int) {
        condSwap(&a, y, z)
        partiallySortedSwap(&a, x, y, z)
    }
}
