from starkware.cairo.common.cairo_builtins import UInt384

// A G2Point is a point on an elliptic curve over the quadratic extension field Fp2,
// when Fp is the base field of that elliptic curve.
// A G2Point P = (x, y) where x = a0 * i + b0 and y = a1 * i + b1.
// Affine coordinates representation.
struct G2Point {
    a0: UInt384,
    b0: UInt384,
    a1: UInt384,
    b1: UInt384,
}
