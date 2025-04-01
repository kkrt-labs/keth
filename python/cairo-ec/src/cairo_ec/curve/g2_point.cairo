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
