from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

from cairo_ec.curve.g1_point import G1Point
from cairo_ec.circuits.ec_ops_compiled import ec_add as ec_add_unchecked, ec_double
from cairo_ec.uint384 import uint384_is_neg_mod_p, uint384_eq_mod_p, felt_to_uint384
from cairo_ec.circuits.ec_ops_compiled import assert_is_on_curve_or_fallback

// @notice Attempts to derive a y-coordinate for a given x on an elliptic curve.
// @return y A candidate y-coordinate; if is_on_curve = 1, (x, y) is on the curve; if 0, y is a fallback value.
// @return is_on_curve 1 if (x, y) lies on the curve, 0 if not.
// @dev Given x, computes y such that y^2 = x^3 + ax + b mod p when is_on_curve = 1, confirming (x, y) is on the curve.
//      If is_on_curve = 0, y^2 = g * (x^3 + ax + b) mod p, where g is a scalar tweak (not a point),
//      s.t it satisfies assert_is_on_curve_or_fallback. This y is a fallback and may not be used directly;
//      e.g., get_random_point retries with a new seed instead, but is used to ensure the operation is sound.
// @param x The x-coordinate to test (UInt384)
// @param v Unused flag (TODO: clarify purpose)
// @param a Curve coefficient a (UInt384)
// @param b Curve coefficient b (UInt384)
// @param g Scalar tweak applied when is_on_curve = 0
// @param p Modulus of the field (UInt384)
// @return (y: UInt384*, is_on_curve: felt) The derived y and success flag
func try_get_point_from_x{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384*, v: felt, a: UInt384*, b: UInt384*, g: UInt384*, p: UInt384*) -> (
    y: UInt384*, is_on_curve: felt
) {
    alloc_locals;
    let (__fp__, __pc__) = get_fp_and_pc();
    local is_on_curve: UInt384;
    local y_try: UInt384;
    %{ compute_y_from_x_hint %}

    assert_is_on_curve_or_fallback(x=x, y=&y_try, a=a, b=b, g=g, is_on_curve=&is_on_curve, p=p);
    assert is_on_curve.d3 = 0;
    assert is_on_curve.d2 = 0;
    assert is_on_curve.d1 = 0;
    // TODO: Add a check for v

    return (y=&y_try, is_on_curve=is_on_curve.d0);
}

// @notice Get a random point from x
func get_random_point{
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(seed: felt, a: UInt384*, b: UInt384*, g: UInt384*, p: UInt384*) -> G1Point {
    alloc_locals;
    let (__fp__, __pc__) = get_fp_and_pc();
    let x_384 = felt_to_uint384(seed);
    tempvar x = new x_384;
    let (y, is_on_curve) = try_get_point_from_x(x=x, v=0, a=a, b=b, g=g, p=p);

    if (is_on_curve != 0) {
        let point = G1Point(x=x_384, y=[y]);
        return point;
    }

    assert poseidon_ptr[0].input.s0 = seed;
    assert poseidon_ptr[0].input.s1 = y.d0;  // salt
    assert poseidon_ptr[0].input.s2 = 2;
    let seed = poseidon_ptr[0].output.s0;
    tempvar poseidon_ptr = poseidon_ptr + PoseidonBuiltin.SIZE;

    return get_random_point(seed=seed, a=a, b=b, g=g, p=p);
}

// Add two EC points. Doesn't check if the inputs are on curve nor if they are the point at infinity.
func ec_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, q: G1Point, a: UInt384, modulus: UInt384
) -> G1Point {
    alloc_locals;
    let same_x = uint384_eq_mod_p(p.x, q.x, modulus);
    let (__fp__, __pc__) = get_fp_and_pc();
    if (same_x != 0) {
        let opposite_y = uint384_is_neg_mod_p(p.y, q.y, modulus);
        if (opposite_y != 0) {
            // p + (-p) = O (point at infinity)
            let res = G1Point(UInt384(0, 0, 0, 0), UInt384(0, 0, 0, 0));
            return res;
        }

        let (res_x, res_y) = ec_double(&p.x, &p.y, &a, &modulus);
        let res = G1Point(x=[res_x], y=[res_y]);
        return res;
    }

    let (res_x, res_y) = ec_add_unchecked(&p.x, &p.y, &q.x, &q.y, &modulus);
    let res = G1Point(x=[res_x], y=[res_y]);
    return res;
}

// Multiply an EC point by a scalar. Doesn't check if the input is on curve nor if it's the point at infinity.
func ec_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, scalar: UInt384, g: UInt384, a: UInt384, modulus: UInt384
) -> G1Point {
    // TODO: Implement this function.
    let res = G1Point(UInt384(0, 0, 0, 0), UInt384(0, 0, 0, 0));
    return res;
}
