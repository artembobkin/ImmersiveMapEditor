/// Ports of the slice algorithms of Rust's standard library (Rust 1.98) that the sweep relies on:
/// `binary_search_by` with its fixed iteration count (which decides the index returned among
/// equal elements), `partition_point`, and the insertion sort `sort_unstable_by` runs on slices of
/// up to 20 elements.

/// Rust's `slice::binary_search_by`. `compare(element)` is `element.cmp(target)`. Returns
/// `.found(index)` for Rust's `Ok(index)` and `.notFound(index)` for `Err(index)`.
enum RustSearchResult: Equatable {
    case found(Int)
    case notFound(Int)

    /// The index of either variant, as `Ok(i) | Err(i) => i`.
    var index: Int {
        switch self {
        case .found(let i), .notFound(let i): return i
        }
    }
}

func rustBinarySearch<T, E: Error>(
    _ data: [T],
    _ compare: (T) throws(E) -> RustOrdering
) throws(E) -> RustSearchResult {
    var size = data.count
    if size == 0 {
        return .notFound(0)
    }
    var base = 0
    while size > 1 {
        let half = size / 2
        let mid = base + half
        let cmp = try compare(data[mid])
        base = cmp == .greater ? base : mid
        size -= half
    }
    let cmp = try compare(data[base])
    if cmp == .equal {
        return .found(base)
    }
    return .notFound(base + (cmp == .less ? 1 : 0))
}

/// Rust's `slice::partition_point`.
func rustPartitionPoint<T, E: Error>(
    _ data: [T],
    _ pred: (T) throws(E) -> Bool
) throws(E) -> Int {
    try rustBinarySearch(data) { (x: T) throws(E) -> RustOrdering in try pred(x) ? .less : .greater }.index
}

/// Rust's `slice::sort_unstable_by`. For up to 20 elements Rust runs `insertion_sort_shift_left`,
/// which this reproduces exactly. Longer slices are sorted by the same insertion sort here:
/// Rust's pattern-defeating quicksort orders them identically whenever `compare` is a strict
/// total order, which holds for every caller in this module (ties are broken by identity).
func rustSortUnstable<T, E: Error>(
    _ v: inout [T],
    _ compare: (T, T) throws(E) -> RustOrdering
) throws(E) {
    let len = v.count
    if len < 2 {
        return
    }
    var tail = 1
    while tail < len {
        // `insert_tail(v_base, tail, is_less)`.
        var sift = tail - 1
        if try compare(v[tail], v[sift]) == .less {
            let tmp = v[tail]
            var dst = tail
            while true {
                v[dst] = v[sift]
                dst = sift
                if sift == 0 {
                    break
                }
                sift -= 1
                if try compare(tmp, v[sift]) != .less {
                    break
                }
            }
            v[dst] = tmp
        }
        tail += 1
    }
}
