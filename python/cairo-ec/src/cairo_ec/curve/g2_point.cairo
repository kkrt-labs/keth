from starkware.cairo.common.cairo_builtins import ModBuiltin

from cairo_core.numeric import U384
from cairo_ec.circuits.mod_ops_compiled import add, sub, mul

// A quadratic extension field of the finite field Fp.
// a = c0 + i * c1
struct Fq2 {
    value: Fq2Struct*,
}

struct Fq2Struct {
    c0: U384,
    c1: U384,
}

func fp2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq2, b: Fq2, modulus: U384
) -> Fq2 {
    let res_c0 = add(a.value.c0, b.value.c0, modulus);
    let res_c1 = add(a.value.c1, b.value.c1, modulus);

    tempvar res = Fq2(new Fq2Struct(res_c0, res_c1));
    return res;
}

// A G2Point is a point on an elliptic curve over a quadratic extension field Fq2.
// Affine coordinates representation.
struct G2Point {
    value: G2PointStruct*,
}

struct G2PointStruct {
    x: Fq2,
    y: Fq2,
}
