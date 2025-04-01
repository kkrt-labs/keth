from cairo_core.numeric import U384

// A quadratic extension field of the finite field Fp.
// a = c0 + i * c1
struct Fp2 {
    value: Fp2Struct*,
}

struct Fp2Struct {
    c0: U384,
    c1: U384,
}

// A G2Point is a point on an elliptic curve over a quadratic extension field Fp2.
// Affine coordinates representation.
struct G2Point {
    value: G2PointStruct*,
}

struct G2PointStruct {
    x: Fp2,
    y: Fp2,
}
