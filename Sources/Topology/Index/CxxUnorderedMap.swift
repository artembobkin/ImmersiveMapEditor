/// The order of libc++'s `std::unordered_map` with unique keys (LLVM,
/// Apache License 2.0 with LLVM Exceptions, the version of the macOS SDK this
/// package builds with), translated to Swift: a map whose iteration order is
/// libc++'s, for the places where GEOS iterates such a map and its order
/// reaches a result (the nodes of OverlayNG's graph).
///
/// libc++ keeps the elements in one singly linked list and an array of
/// buckets, each pointing at the element before the bucket's first. A new
/// key goes first in its bucket, or first in the list when its bucket is
/// empty. The table grows before an insertion would pass a load factor of
/// 1: to `2n + 1` buckets rounded up to a prime (`n` the count, 2 at first),
/// relinking the list bucket by bucket. A hash is constrained to a bucket
/// by a mask for a power of two, else by the remainder.
/// A class: its one user keeps it in a graph, and reading a struct of
/// arrays out of a class property copies it.
final class CxxUnorderedMap<Key, Value> {
    @exclusivity(unchecked) private(set) var keys: [Key] = []
    @exclusivity(unchecked) private(set) var values: [Value] = []
    @exclusivity(unchecked) private var hashes: [UInt64] = []
    /// The next element of the list, -1 at its end.
    @exclusivity(unchecked) private var next: [Int] = []
    /// The first element of the list, -1 when empty.
    @exclusivity(unchecked) private var head = -1
    /// For each bucket, the element before its first: -2 for the list's
    /// head, -1 for an empty bucket.
    @exclusivity(unchecked) private var buckets: [Int] = []
    private let hash: (Key) -> UInt64
    private let equal: (Key, Key) -> Bool

    init(hash: @escaping (Key) -> UInt64, equal: @escaping (Key, Key) -> Bool) {
        self.hash = hash
        self.equal = equal
    }

    var count: Int { keys.count }

    /// Room for `n` elements in the element arrays (not the buckets, which
    /// grow as libc++'s do, so the order is unchanged).
    func reserveCapacity(_ n: Int) {
        keys.reserveCapacity(n)
        values.reserveCapacity(n)
        hashes.reserveCapacity(n)
        next.reserveCapacity(n)
    }

    private func nextOf(_ p: Int) -> Int { p == -2 ? head : next[p] }

    private func setNext(_ p: Int, _ n: Int) {
        if p == -2 { head = n } else { next[p] = n }
    }

    private static func constrain(_ h: UInt64, _ bc: Int) -> Int {
        let b = UInt64(bc)
        if b & (b &- 1) == 0 { return Int(h & (b &- 1)) }
        return Int(h < b ? h : h % b)
    }

    private static func isHashPower2(_ bc: Int) -> Bool { bc > 2 && bc & (bc - 1) == 0 }

    /// The least prime not below `n`.
    private static func nextPrime(_ n: Int) -> Int {
        func isPrime(_ p: Int) -> Bool {
            if p < 2 { return false }
            if p < 4 { return true }
            if p % 2 == 0 { return false }
            var d = 3
            while d * d <= p {
                if p % d == 0 { return false }
                d += 2
            }
            return true
        }
        var p = n
        while !isPrime(p) { p += 1 }
        return p
    }

    /// The index of the element of a key.
    func find(_ k: Key) -> Int? {
        let bc = buckets.count
        if bc == 0 || keys.isEmpty { return nil }
        let h = hash(k)
        let chash = CxxUnorderedMap.constrain(h, bc)
        let before = buckets[chash]
        if before == -1 { return nil }
        var nd = nextOf(before)
        while nd != -1 && (hashes[nd] == h || CxxUnorderedMap.constrain(hashes[nd], bc) == chash) {
            if hashes[nd] == h && equal(keys[nd], k) { return nd }
            nd = next[nd]
        }
        return nil
    }

    func value(_ k: Key) -> Value? {
        guard let i = find(k) else { return nil }
        return values[i]
    }

    /// Inserts the key with its value unless the key is there:
    /// `emplace` of libc++ (`__emplace_unique_key_args`).
    @discardableResult
    func insert(_ k: Key, _ v: Value) -> Bool {
        if find(k) != nil { return false }
        let h = hash(k)
        var bc = buckets.count
        if Float(keys.count + 1) > Float(bc) * 1.0 || bc == 0 {
            rehash(max(2 * bc + (CxxUnorderedMap.isHashPower2(bc) ? 0 : 1), Int((Float(keys.count + 1) / 1.0).rounded(.up))))
            bc = buckets.count
        }
        let chash = CxxUnorderedMap.constrain(h, bc)
        let n = keys.count
        keys.append(k)
        values.append(v)
        hashes.append(h)
        next.append(-1)
        let pn = buckets[chash]
        if pn == -1 {
            next[n] = head
            head = n
            buckets[chash] = -2
            if next[n] != -1 { buckets[CxxUnorderedMap.constrain(hashes[next[n]], bc)] = n }
        } else {
            next[n] = nextOf(pn)
            setNext(pn, n)
        }
        return true
    }

    private func rehash(_ nIn: Int) {
        var n = nIn
        if n == 1 { n = 2 } else if n & (n - 1) != 0 { n = CxxUnorderedMap.nextPrime(n) }
        if n > buckets.count { doRehash(n) }
    }

    private func doRehash(_ nbc: Int) {
        buckets = [Int](repeating: -1, count: nbc)
        var pp = -2
        var cp = head
        guard cp != -1 else { return }
        var chash = CxxUnorderedMap.constrain(hashes[cp], nbc)
        buckets[chash] = pp
        var phash = chash
        pp = cp
        cp = next[cp]
        while cp != -1 {
            chash = CxxUnorderedMap.constrain(hashes[cp], nbc)
            if chash == phash {
                pp = cp
            } else if buckets[chash] == -1 {
                buckets[chash] = pp
                pp = cp
                phash = chash
            } else {
                // Moves the element after the bucket's first one.
                setNext(pp, next[cp])
                next[cp] = nextOf(buckets[chash])
                setNext(buckets[chash], cp)
            }
            cp = nextOf(pp)
        }
    }

    /// The indices of the elements in the map's iteration order.
    var orderedIndices: [Int] {
        var r: [Int] = []
        r.reserveCapacity(keys.count)
        var i = head
        while i != -1 {
            r.append(i)
            i = next[i]
        }
        return r
    }
}

extension Coordinate {
    /// GEOS's `Coordinate::HashCode` over libc++'s hash of a double (its
    /// bits, 0 for both zeros): the hash of x, xor the hash of y shifted left.
    var geosHashCode: UInt64 {
        func h(_ v: Double) -> UInt64 { v == 0 ? 0 : v.bitPattern }
        return h(x) ^ (h(y) << 1)
    }
}
