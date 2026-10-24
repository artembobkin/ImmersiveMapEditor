/// The `f64` tests of the Rust crate float_next_after 1.0.0.

@testable import GeoAlgorithms
import Testing

@Suite struct NextAfterTests {
    let posZero = 0.0
    let negZero = -0.0
    let smallestPos = 5e-324
    let largestNeg = -5e-324
    let largestPos = Double.greatestFiniteMagnitude
    let smallestNeg = -Double.greatestFiniteMagnitude
    let posOne = 1.0
    let negOne = -1.0
    let nextLargerThanOne = 1.0 + Double.ulpOfOne
    let nextSmallerThanOne = 0.999_999_999_999_999_9
    let sequentialLargeNumbers = (16_237_485_966.000_004, 16_237_485_966.000_006)

    private func isPositiveZero(_ x: Double) -> Bool { x.bitPattern == 0.0.bitPattern }
    private func isNegativeZero(_ x: Double) -> Bool { x.bitPattern == (-0.0).bitPattern }

    @Test func nextLargerThan0() {
        #expect(posZero.nextAfter(.infinity) == smallestPos)
        #expect(negZero.nextAfter(.infinity) == smallestPos)
    }

    @Test func nextSmallerThan0() {
        #expect(posZero.nextAfter(-.infinity) == largestNeg)
        #expect(negZero.nextAfter(-.infinity) == largestNeg)
    }

    @Test func stepTowardsZero() {
        #expect(isPositiveZero(smallestPos.nextAfter(posZero)))
        #expect(isPositiveZero(smallestPos.nextAfter(negZero)))
        #expect(isPositiveZero(smallestPos.nextAfter(-.infinity)))
        #expect(isNegativeZero(largestNeg.nextAfter(negZero)))
        #expect(isNegativeZero(largestNeg.nextAfter(posZero)))
        #expect(isNegativeZero(largestNeg.nextAfter(.infinity)))
    }

    @Test func specialCaseSignedZeros() {
        #expect(isNegativeZero(posZero.nextAfter(negZero)))
        #expect(isPositiveZero(negZero.nextAfter(posZero)))
    }

    @Test func nextafterAroundOne() {
        #expect(posOne.nextAfter(.infinity) == nextLargerThanOne)
        #expect(posOne.nextAfter(-.infinity) == nextSmallerThanOne)
        #expect(negOne.nextAfter(-.infinity) == -nextLargerThanOne)
        #expect(negOne.nextAfter(.infinity) == -nextSmallerThanOne)
    }

    @Test func nextafterForBigPositiveNumber() {
        let (lo, hi) = sequentialLargeNumbers
        #expect(lo.nextAfter(.infinity) == hi)
        #expect(hi.nextAfter(-.infinity) == lo)
        #expect(lo.nextAfter(hi) == hi)
        #expect(hi.nextAfter(lo) == lo)
    }

    @Test func nextafterForSmallNegativeNumber() {
        let (lo, hi) = (-sequentialLargeNumbers.0, -sequentialLargeNumbers.1)
        #expect(lo.nextAfter(-.infinity) == hi)
        #expect(hi.nextAfter(.infinity) == lo)
        #expect(lo.nextAfter(hi) == hi)
        #expect(hi.nextAfter(lo) == lo)
    }

    @Test func stepToLargestIsPossible() {
        let smaller = largestPos.nextAfter(-.infinity)
        #expect(smaller.nextAfter(.infinity) == largestPos)
        let smallerNeg = smallestNeg.nextAfter(.infinity)
        #expect(smallerNeg.nextAfter(-.infinity) == smallestNeg)
    }

    @Test func jumpToInfinity() {
        #expect(largestPos.nextAfter(.infinity) == .infinity)
        #expect(smallestNeg.nextAfter(-.infinity) == -.infinity)
    }

    @Test func staysAtInfinity() {
        #expect(Double.infinity.nextAfter(-.infinity) == .infinity)
        #expect((-Double.infinity).nextAfter(.infinity) == -.infinity)
    }

    @Test func returnsNanForAnyNanInvolved() {
        #expect(Double.nan.nextAfter(posOne).isNaN)
        #expect(posOne.nextAfter(.nan).isNaN)
        #expect(Double.nan.nextAfter(.nan).isNaN)
    }

    @Test func returnsIdentityForEqualDest() {
        let values = [posZero, negZero, posOne, negOne, sequentialLargeNumbers.0, sequentialLargeNumbers.1,
                      .infinity, -.infinity, smallestPos, largestNeg, largestPos, smallestNeg]
        for x in values {
            #expect(x.nextAfter(x) == x)
        }
    }

    @Test func canSuccessfullyRoundtrip() {
        let values = [posOne, negOne, sequentialLargeNumbers.0, sequentialLargeNumbers.1, smallestPos, largestNeg]
        for orig in values {
            #expect(orig.nextAfter(.infinity).nextAfter(-.infinity) == orig)
            #expect(orig.nextAfter(-.infinity).nextAfter(.infinity) == orig)
            let upper = orig.nextAfter(.infinity)
            let lower = orig.nextAfter(-.infinity)
            #expect(orig.nextAfter(upper).nextAfter(lower) == orig)
            #expect(orig.nextAfter(lower).nextAfter(upper) == orig)
        }
    }
}
