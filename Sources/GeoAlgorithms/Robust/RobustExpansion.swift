/// The floating point expansion arithmetic of the robust crate (Shewchuk's two-sum, two-product
/// and expansion sums), operation for operation, for `Robust.orient2d`.

extension Robust {
    static func twoProduct(_ a: Double, _ b: Double) -> (Double, Double) {
        let x = a * b
        return (x, twoProductTail(a, b, x))
    }

    static func twoProductTail(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let (ahi, alo) = split(a)
        let (bhi, blo) = split(b)
        let err1 = x - (ahi * bhi)
        let err2 = err1 - (alo * bhi)
        let err3 = err2 - (ahi * blo)
        return (alo * blo) - err3
    }

    static func split(_ a: Double) -> (Double, Double) {
        let c = splitter * a
        let abig = c - a
        let ahi = c - abig
        let alo = a - ahi
        return (ahi, alo)
    }

    static func twoTwoDiff(
        _ a1: Double, _ a0: Double, _ b1: Double, _ b0: Double
    ) -> (Double, Double, Double, Double) {
        let (j, r0, x0) = twoOneDiff(a1, a0, b0)
        let (x3, x2, x1) = twoOneDiff(j, r0, b1)
        return (x3, x2, x1, x0)
    }

    static func twoOneDiff(_ a1: Double, _ a0: Double, _ b: Double) -> (Double, Double, Double) {
        let (i, x0) = twoDiff(a0, b)
        let (x2, x1) = twoSum(a1, i)
        return (x2, x1, x0)
    }

    static func twoDiff(_ a: Double, _ b: Double) -> (Double, Double) {
        let x = a - b
        return (x, twoDiffTail(a, b, x))
    }

    static func twoDiffTail(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let bvirt = a - x
        let avirt = x + bvirt
        let bround = bvirt - b
        let around = a - avirt
        return around + bround
    }

    static func twoSum(_ a: Double, _ b: Double) -> (Double, Double) {
        let x = a + b
        return (x, twoSumTail(a, b, x))
    }

    static func twoSumTail(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let bvirt = x - a
        let avirt = x - bvirt
        let bround = b - bvirt
        let around = a - avirt
        return around + bround
    }

    static func fastTwoSum(_ a: Double, _ b: Double) -> (Double, Double) {
        let x = a + b
        return (x, fastTwoSumTail(a, b, x))
    }

    static func fastTwoSumTail(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let bvirt = x - a
        return b - bvirt
    }

    static func estimate(_ e: [Double]) -> Double {
        var q = e[0]
        for cur in e[1...] {
            q += cur
        }
        return q
    }

    /// Sums the expansions `e` and `f` into `h`, eliminating zero components, and returns the
    /// length of the result.
    static func fastExpansionSumZeroElim(
        _ e: ArraySlice<Double>, _ f: ArraySlice<Double>, _ h: inout [Double]
    ) -> Int {
        let e = Array(e)
        let f = Array(f)
        var enow = e[0]
        var fnow = f[0]
        var eindex = 0
        var findex = 0
        var qNew: Double
        var hh: Double
        var q: Double
        if (fnow > enow) == (fnow > -enow) {
            q = enow
            eindex += 1
        } else {
            q = fnow
            findex += 1
        }

        var hindex = 0
        if eindex < e.count && findex < f.count {
            enow = e[eindex]
            fnow = f[findex]
            if (fnow > enow) == (fnow > -enow) {
                (qNew, hh) = fastTwoSum(enow, q)
                eindex += 1
            } else {
                (qNew, hh) = fastTwoSum(fnow, q)
                findex += 1
            }
            q = qNew
            if hh != 0.0 {
                h[hindex] = hh
                hindex += 1
            }

            while eindex < e.count && findex < f.count {
                enow = e[eindex]
                fnow = f[findex]
                if (fnow > enow) == (fnow > -enow) {
                    (qNew, hh) = twoSum(q, enow)
                    eindex += 1
                } else {
                    (qNew, hh) = twoSum(q, fnow)
                    findex += 1
                }
                q = qNew
                if hh != 0.0 {
                    h[hindex] = hh
                    hindex += 1
                }
            }
        }

        while eindex < e.count {
            enow = e[eindex]
            (qNew, hh) = twoSum(q, enow)
            q = qNew
            eindex += 1
            if hh != 0.0 {
                h[hindex] = hh
                hindex += 1
            }
        }

        while findex < f.count {
            fnow = f[findex]
            (qNew, hh) = twoSum(q, fnow)
            q = qNew
            findex += 1
            if hh != 0.0 {
                h[hindex] = hh
                hindex += 1
            }
        }

        if q != 0.0 || hindex == 0 {
            h[hindex] = q
            hindex += 1
        }
        return hindex
    }
}
