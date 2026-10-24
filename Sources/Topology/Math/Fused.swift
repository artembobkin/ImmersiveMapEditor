/// Fused multiply-add where GEOS has one.
///
/// The GEOS this port must match (3.13, from the `GEOSwift/geos` package) is
/// compiled by Apple clang with its default `-ffp-contract=on`: inside one
/// expression, a product added to or subtracted from something is fused into
/// one `fmadd` (one rounding instead of two). Clang fuses the left operand
/// when it is a product, else the right one, and never across statements.
/// JTS on the JVM never fuses. Each place where GEOS's expression (the same
/// as JTS's) is fused is written with these, so the arithmetic is GEOS's;
/// each is checked against GEOS in the tests.

/// `a * b + c` rounded once.
@inline(__always) func fusedAdd(_ a: Double, _ b: Double, _ c: Double) -> Double {
    c.addingProduct(a, b)
}

/// `a * b - c` rounded once.
@inline(__always) func fusedSub(_ a: Double, _ b: Double, _ c: Double) -> Double {
    (-c).addingProduct(a, b)
}

/// `c - a * b` rounded once.
@inline(__always) func fusedSubProduct(_ c: Double, _ a: Double, _ b: Double) -> Double {
    c.addingProduct(-a, b)
}
