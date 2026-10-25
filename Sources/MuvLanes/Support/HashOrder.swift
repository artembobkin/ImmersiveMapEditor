/// The iteration order of Muv's tag maps. A `Tag`'s subtags are a Rust
/// `HashMap` with rustc-hash's `FxBuildHasher`, so the order in which Muv
/// iterates them is fixed by the keys' hashes and the table's history, and
/// it reaches the output wherever two keys mean the same thing (`bus:lanes`
/// against `hgv:lanes` of another lane count, `tricycle` against
/// `auto_rickshaw`, two lifecycle prefixes). This file reproduces it:
/// rustc-hash 2.1's `FxHasher` over a `str` (its bytes, then `0xff`), and
/// the bucket layout of the SwissTable behind Rust's `HashMap` (hashbrown,
/// with the 8-byte control groups of aarch64), which iterates its buckets in
/// index order. Only insertion is modelled: Muv never removes a subtag.
///
/// rustc-hash and hashbrown are MIT or Apache-2.0 (see this folder's
/// LICENSE). This translation is part of this MPL-2.0 file.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// rustc-hash 2.1's `FxHasher`, 64-bit, for one `str` key: `write(bytes)`
/// then `write_u8(0xff)` (Rust's default `write_str`), then `finish`.
func fxHashStr(_ key: String) -> UInt64 {
    let k: UInt64 = 0xf135_7aea_2e62_a9c5
    var hash: UInt64 = 0
    hash = (hash &+ fxHashBytes(Array(key.utf8))) &* k
    hash = (hash &+ 0xff) &* k
    return (hash << 26) | (hash >> 38)
}

private func fxMultiplyMix(_ x: UInt64, _ y: UInt64) -> UInt64 {
    let full = x.multipliedFullWidth(by: y)
    return full.low ^ full.high
}

private func fxLoad64(_ b: [UInt8], _ at: Int) -> UInt64 {
    var v: UInt64 = 0
    for i in 0..<8 { v |= UInt64(b[at + i]) << (8 * UInt64(i)) }
    return v
}

private func fxLoad32(_ b: [UInt8], _ at: Int) -> UInt64 {
    var v: UInt64 = 0
    for i in 0..<4 { v |= UInt64(b[at + i]) << (8 * UInt64(i)) }
    return v
}

/// rustc-hash's `hash_bytes`.
private func fxHashBytes(_ bytes: [UInt8]) -> UInt64 {
    let seed1: UInt64 = 0x243f_6a88_85a3_08d3
    let seed2: UInt64 = 0x1319_8a2e_0370_7344
    let preventTrivialZeroCollapse: UInt64 = 0xa409_3822_299f_31d0
    let len = bytes.count
    var s0 = seed1
    var s1 = seed2
    if len <= 16 {
        if len >= 8 {
            s0 ^= fxLoad64(bytes, 0)
            s1 ^= fxLoad64(bytes, len - 8)
        } else if len >= 4 {
            s0 ^= fxLoad32(bytes, 0)
            s1 ^= fxLoad32(bytes, len - 4)
        } else if len > 0 {
            let lo = bytes[0], mid = bytes[len / 2], hi = bytes[len - 1]
            s0 ^= UInt64(lo)
            s1 ^= (UInt64(hi) << 8) | UInt64(mid)
        }
    } else {
        var off = 0
        while off < len - 16 {
            let x = fxLoad64(bytes, off)
            let y = fxLoad64(bytes, off + 8)
            let t = fxMultiplyMix(s0 ^ x, preventTrivialZeroCollapse ^ y)
            s0 = s1
            s1 = t
            off += 16
        }
        s0 ^= fxLoad64(bytes, len - 16)
        s1 ^= fxLoad64(bytes, len - 8)
    }
    return fxMultiplyMix(s0, s1) ^ UInt64(len)
}

/// Where hashbrown puts each entry of a map that only grows: the bucket of
/// every entry, so that iterating the buckets in index order gives Rust's
/// iteration order. Entries are named by their index of insertion.
struct HashOrder {
    private static let groupWidth = 8

    private var bucketMask = 0
    /// Per bucket, the entry in it, or -1.
    private var slots: [Int] = []
    private var growthLeft = 0
    private var hashes: [UInt64] = []

    /// `HashMap::with_capacity_and_hasher(capacity, _)`.
    init(capacity: Int = 0) {
        if capacity > 0 { allocate(buckets: Self.capacityToBuckets(capacity)) }
    }

    var count: Int { hashes.count }

    /// Inserts the next entry (index `count`), a key not yet in the map,
    /// as `HashMap::entry(key).or_default()` does: reserve one, then take
    /// the first free slot of the probe sequence.
    mutating func insert(hash: UInt64) {
        if growthLeft == 0 { reserveRehash() }
        let slot = findInsertSlot(hash)
        slots[slot] = hashes.count
        hashes.append(hash)
        growthLeft -= 1
    }

    /// The entries in iteration order.
    func order() -> [Int] { slots.filter { $0 >= 0 } }

    private static func capacityToBuckets(_ cap: Int) -> Int {
        if cap < 15 {
            // The entries are larger than a byte, so the smallest table holds 3.
            let c = max(3, cap)
            return c < 4 ? 4 : (c < 8 ? 8 : 16)
        }
        let adjusted = cap * 8 / 7
        var p = 1
        while p < adjusted { p <<= 1 }
        return p
    }

    private static func bucketMaskToCapacity(_ mask: Int) -> Int {
        mask < 8 ? mask : ((mask + 1) / 8) * 7
    }

    private mutating func allocate(buckets: Int) {
        bucketMask = buckets - 1
        slots = Array(repeating: -1, count: buckets)
        growthLeft = Self.bucketMaskToCapacity(bucketMask)
    }

    /// `reserve_rehash(1)` with no deleted entries: always a resize to at
    /// least the next capacity, re-inserting the entries in bucket order.
    private mutating func reserveRehash() {
        let items = hashes.count
        let fullCapacity = slots.isEmpty ? 0 : Self.bucketMaskToCapacity(bucketMask)
        let old = slots
        allocate(buckets: Self.capacityToBuckets(max(items + 1, fullCapacity + 1)))
        for entry in old where entry >= 0 {
            slots[findInsertSlot(hashes[entry])] = entry
        }
        growthLeft -= items
    }

    /// The control byte at `i` of the array hashbrown reads groups from: the
    /// buckets, then a copy of the first group's bytes (empty past a table
    /// smaller than a group).
    private func isFull(ctrl i: Int) -> Bool {
        let buckets = bucketMask + 1
        if i < buckets { return slots[i] >= 0 }
        let mirrored = i - Self.groupWidth
        if buckets < Self.groupWidth {
            return mirrored >= 0 && mirrored < buckets && slots[mirrored] >= 0
        }
        return slots[i - buckets] >= 0
    }

    /// `find_insert_slot`: the triangular probe over groups of 8 control
    /// bytes, the lowest empty byte of the first group that has one, fixed
    /// up for tables smaller than a group.
    private func findInsertSlot(_ hash: UInt64) -> Int {
        var pos = Int(truncatingIfNeeded: hash) & bucketMask
        var stride = 0
        while true {
            for bit in 0..<Self.groupWidth where !isFull(ctrl: pos + bit) {
                var index = (pos + bit) & bucketMask
                if slots[index] >= 0 {
                    // `fix_insert_slot`: rescan the first group.
                    index = (0..<Self.groupWidth).first { !isFull(ctrl: $0) }!
                }
                return index
            }
            stride += Self.groupWidth
            pos = (pos + stride) & bucketMask
        }
    }
}
