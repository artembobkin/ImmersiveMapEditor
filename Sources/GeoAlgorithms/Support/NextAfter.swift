/// A port of `next_after` from the Rust crate float_next_after 1.0.0, which the sweep uses to
/// nudge an intersection point one ulp to the right of a segment's start.

extension Double {
    /// The next representable value after `self` in the direction of `y`, computed on the bit
    /// pattern exactly as float_next_after does.
    func nextAfter(_ y: Double) -> Double {
        // `short_circuit_operands`.
        if y == self {
            return y
        }
        if self.isNaN || y.isNaN {
            return .nan
        }
        if self.isInfinite {
            return self
        }
        if self == 0.0 {
            return copySign(5e-324, y)
        }

        let returnValue: Double
        if (y > self) == (self > 0.0) {
            returnValue = Double(bitPattern: self.bitPattern + 1)
        } else {
            returnValue = Double(bitPattern: self.bitPattern - 1)
        }
        if returnValue != 0.0 {
            return returnValue
        }
        return copySign(returnValue, self)
    }
}

/// `copy_sign` of float_next_after: `x` with the sign of `y`, by `is_sign_positive`.
private func copySign(_ x: Double, _ y: Double) -> Double {
    if (x.sign == .plus) == (y.sign == .plus) {
        return x
    }
    return -x
}
