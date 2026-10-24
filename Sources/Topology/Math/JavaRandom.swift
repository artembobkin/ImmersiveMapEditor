/// Java's `java.util.Random`, the 48-bit linear congruential generator, for
/// the shuffles JTS seeds (`HotPixelIndex` with seed 13).
struct JavaRandom {
    private var seed: Int64
    private static let multiplier: Int64 = 0x5DEECE66D
    private static let mask: Int64 = (1 << 48) - 1

    init(seed: Int64) { self.seed = (seed ^ JavaRandom.multiplier) & JavaRandom.mask }

    mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* JavaRandom.multiplier &+ 0xB) & JavaRandom.mask
        return Int32(truncatingIfNeeded: seed >> (48 - bits))
    }

    /// A uniform integer in `0..<bound`.
    mutating func nextInt(_ bound: Int32) -> Int32 {
        precondition(bound > 0)
        if bound & -bound == bound {
            return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(next(31))) >> 31)
        }
        var bits: Int32, val: Int32
        repeat {
            bits = next(31)
            val = bits % bound
        } while bits &- val &+ (bound &- 1) < 0
        return val
    }
}
