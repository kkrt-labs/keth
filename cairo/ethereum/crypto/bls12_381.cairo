from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.registers import get_label_location

from cairo_ec.circuits.ec_ops_compiled import assert_on_curve
from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.bls12_381 import bls12_381
from cairo_ec.curve.g1_point import G1Point, G1PointStruct

from ethereum.utils.numeric import (
    U384_ZERO,
    U384_ONE,
    U384_is_zero,
    get_u384_bits_little,
    U384__eq__,
)
from ethereum_types.numeric import U384

// Field over which the bls12_381 curve is defined.
// BLSF elements are 1-dimensional.
// The type used in EELS is "optimized_bls12_381_FQ as FQ",
// which has been renamed BLSF for conciseness and coherence with previously introduced BNF.
struct BLSFStruct {
    c0: U384,
}

struct BLSF {
    value: BLSFStruct*,
}

func BLSF_ZERO() -> BLSF {
    let (u384_zero) = get_label_location(U384_ZERO);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    tempvar res = BLSF(new BLSFStruct(U384(u384_zero_ptr)));
    return res;
}

func BLSF_ONE() -> BLSF {
    let (u384_one) = get_label_location(U384_ONE);
    let u384_one_ptr = cast(u384_one, UInt384*);
    tempvar res = BLSF(new BLSFStruct(U384(u384_one_ptr)));
    return res;
}

func BLSF__eq__{range_check96_ptr: felt*}(a: BLSF, b: BLSF) -> felt {
    let result = U384__eq__(a.value.c0, b.value.c0);
    return result.value;
}

func blsf_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF, b: BLSF
) -> BLSF {
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    let result = add(a.value.c0, b.value.c0, modulus);
    tempvar res = BLSF(new BLSFStruct(result));

    return res;
}

func blsf_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF, b: BLSF
) -> BLSF {
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    let result = sub(a.value.c0, b.value.c0, modulus);
    tempvar res = BLSF(new BLSFStruct(result));

    return res;
}

func blsf_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF, b: BLSF
) -> BLSF {
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    let result = mul(a.value.c0, b.value.c0, modulus);
    tempvar res = BLSF(new BLSFStruct(result));

    return res;
}

func blsf_div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF, b: BLSF
) -> BLSF {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local b_inv: BLSF;

    %{ blsf_multiplicative_inverse %}

    let res = blsf_mul(b, b_inv);
    let (one) = get_label_location(U384_ONE);
    let uint384_one = cast(one, UInt384*);
    tempvar blsf_one = BLSF(new BLSFStruct(U384(uint384_one)));
    let is_inv = BLSF__eq__(res, blsf_one);
    assert is_inv = 1;

    return blsf_mul(a, b_inv);
}

// Quadratic extension field of BLSF.
// BLSF2 elements are 2-dimensional.
// The type used in EELS is "optimized_bls12_381_FQ2 as FQ2",
// which has been renamed BLSF2 for conciseness and coherence with previously introduced BNF2.
struct BLSF2Struct {
    c0: U384,
    c1: U384,
}

struct BLSF2 {
    value: BLSF2Struct*,
}

func BLSF2_ZERO() -> BLSF2 {
    let (u384_zero) = get_label_location(U384_ZERO);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    tempvar res = BLSF2(new BLSF2Struct(U384(u384_zero_ptr), U384(u384_zero_ptr)));
    return res;
}

func BLSF2_ONE() -> BLSF2 {
    let (u384_zero) = get_label_location(U384_ZERO);
    let (u384_one) = get_label_location(U384_ONE);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    let u384_one_ptr = cast(u384_one, UInt384*);
    tempvar res = BLSF2(new BLSF2Struct(U384(u384_one_ptr), U384(u384_zero_ptr)));
    return res;
}

func BLSF2__eq__{range_check96_ptr: felt*}(a: BLSF2, b: BLSF2) -> felt {
    alloc_locals;
    let is_c0_equal = U384__eq__(a.value.c0, b.value.c0);
    let is_c1_equal = U384__eq__(a.value.c1, b.value.c1);

    let result = is_c0_equal.value * is_c1_equal.value;

    return result;
}

func blsf2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF2, b: BLSF2
) -> BLSF2 {
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    let res_c0 = add(a.value.c0, b.value.c0, modulus);
    let res_c1 = add(a.value.c1, b.value.c1, modulus);

    tempvar res = BLSF2(new BLSF2Struct(res_c0, res_c1));
    return res;
}

func blsf2_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF2, b: BLSF2
) -> BLSF2 {
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    let res_c0 = sub(a.value.c0, b.value.c0, modulus);
    let res_c1 = sub(a.value.c1, b.value.c1, modulus);

    tempvar res = BLSF2(new BLSF2Struct(res_c0, res_c1));
    return res;
}

// BLSF2 multiplication
// Flatten loops from EELS:
// https://github.com/ethereum/execution-specs/blob/9c58cc8553ec3a59e732e81d5044c35aa480fbbb/src/ethereum/crypto/finite_field.py#L270-L287
// First nested loop unrolled
// mul[0] = a[0] * b[0]
// mul[1] = a[0] * b[1] + a[1] * b[0]
// mul[2] = a[1] * b[1]
// mul[3] = 0
//
// Second nested loop knowing that modulus[1] = 0
// When i=3 nothing is changed as mul[3] = 0
// When i=2:
// reduction_term = (mul[2] * modulus[0]) % prime
// mul[0] = mul[0] - reduction_term
func blsf2_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF2, b: BLSF2
) -> BLSF2 {
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    // Step 1: Compute the products for polynomial multiplication
    // mul[0] = a[0] * b[0]
    let mul_0 = mul(a.value.c0, b.value.c0, modulus);
    // mul[1] = a[0] * b[1] + a[1] * b[0]
    let term_1 = mul(a.value.c0, b.value.c1, modulus);
    let term_2 = mul(a.value.c1, b.value.c0, modulus);
    let mul_1 = add(term_1, term_2, modulus);
    // mul[2] = a[1] * b[1]
    let mul_2 = mul(a.value.c1, b.value.c1, modulus);

    // Step 2: Apply the reduction using the modulus polynomial
    // mul[2] * modulus[0]
    tempvar modulus_coeff = U384(new UInt384(1, 0, 0, 0));
    let reduction_term = mul(mul_2, modulus_coeff, modulus);
    // Compute res[0] = mul[0] - reduction_term
    let res_c0 = sub(mul_0, reduction_term, modulus);
    // No reduction needed for res[1] = mul[1] in BLSF2 with degree 2
    let res_c1 = mul_1;

    tempvar res = BLSF2(new BLSF2Struct(res_c0, res_c1));
    return res;
}

func blsf2_div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BLSF2, b: BLSF2
) -> BLSF2 {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local b_inv: BLSF2;

    %{ blsf2_multiplicative_inverse %}

    let res = blsf2_mul(b, b_inv);
    let blsf2_one = BLSF2_ONE();
    let is_inv = BLSF2__eq__(res, blsf2_one);
    assert is_inv = 1;

    return blsf2_mul(a, b_inv);
}

// bls12-381 curve defined over BLSF (Fq)
// BLSP represents a point on the curve.
struct BLSPStruct {
    x: BLSF,
    y: BLSF,
}

using G1Compressed = U384;
using G1Uncompressed = BLSP;

struct BLSP {
    value: BLSPStruct*,
}

func BLSP__eq__{range_check96_ptr: felt*}(p: BLSP, q: BLSP) -> felt {
    alloc_locals;
    let is_x_equal = BLSF__eq__(p.value.x, q.value.x);
    let is_y_equal = BLSF__eq__(p.value.y, q.value.y);
    let result = is_x_equal * is_y_equal;
    return result;
}

func blsp_point_at_infinity() -> BLSP {
    alloc_locals;

    let blsf_zero = BLSF_ZERO();
    tempvar res = BLSP(new BLSPStruct(blsf_zero, blsf_zero));
    return res;
}

// Returns a BLSP, a point that is verified to be on the bls12-381 curve over Fq.
func blsp_init{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: BLSF, y: BLSF
) -> BLSP {
    alloc_locals;

    let blsf_zero = BLSF_ZERO();
    let y_is_zero = BLSF__eq__(y, blsf_zero);
    let x_is_zero = BLSF__eq__(x, blsf_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        tempvar res = BLSP(new BLSPStruct(x, y));
        return res;
    }

    tempvar a = U384(new UInt384(bls12_381.A0, bls12_381.A1, bls12_381.A2, bls12_381.A3));
    tempvar b = U384(new UInt384(bls12_381.B0, bls12_381.B1, bls12_381.B2, bls12_381.B3));
    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    tempvar point = G1Point(new G1PointStruct(x.value.c0, y.value.c0));
    assert_on_curve(point.value, a, b, modulus);

    tempvar res = BLSP(new BLSPStruct(x, y));
    return res;
}

func blsp_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BLSP
) -> BLSP {
    alloc_locals;

    let infinity = blsp_point_at_infinity();
    let p_inf = BLSP__eq__(p, infinity);
    if (p_inf != 0) {
        return infinity;
    }

    // Point doubling formula for BLS12-381 (a = 0):
    // λ = (3x²) / (2y)
    // x' = λ² - 2x
    // y' = λ(x - x') - y

    // Calculate λ = (3x²) / (2y)
    let x_squared = blsf_mul(p.value.x, p.value.x);
    tempvar three = BLSF(new BLSFStruct(U384(new UInt384(3, 0, 0, 0))));
    let three_x_squared = blsf_mul(three, x_squared);
    tempvar two = BLSF(new BLSFStruct(U384(new UInt384(2, 0, 0, 0))));
    let two_y = blsf_mul(two, p.value.y);
    let lambda = blsf_div(three_x_squared, two_y);

    // Calculate x' = λ² - 2x
    let lambda_squared = blsf_mul(lambda, lambda);
    let two_x = blsf_mul(two, p.value.x);
    let new_x = blsf_sub(lambda_squared, two_x);

    // Calculate y' = λ(x - x') - y
    let x_diff = blsf_sub(p.value.x, new_x);
    let lambda_x_diff = blsf_mul(lambda, x_diff);
    let new_y = blsf_sub(lambda_x_diff, p.value.y);

    // Return the resulting point
    tempvar res = BLSP(new BLSPStruct(new_x, new_y));
    return res;
}

// Add two points on the base curve
func blsp_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BLSP, q: BLSP
) -> BLSP {
    alloc_locals;

    let infinity = blsp_point_at_infinity();
    let p_inf = BLSP__eq__(p, infinity);
    if (p_inf != 0) {
        return q;
    }

    let q_inf = BLSP__eq__(q, infinity);
    if (q_inf != 0) {
        return p;
    }

    let x_equal = BLSF__eq__(p.value.x, q.value.x);
    if (x_equal != 0) {
        let y_equal = BLSF__eq__(p.value.y, q.value.y);
        if (y_equal != 0) {
            return blsp_double(p);
        }
        let res = blsp_point_at_infinity();
        return res;
    }

    // Standard case: compute point addition using the formula:
    // λ = (q.y - p.y) / (q.x - p.x)
    // x_r = λ^2 - p.x - q.x
    // y_r = λ(p.x - x_r) - p.y

    // Calculate λ = (q.y - p.y) / (q.x - p.x)
    let y_diff = blsf_sub(q.value.y, p.value.y);
    let x_diff = blsf_sub(q.value.x, p.value.x);
    let lambda = blsf_div(y_diff, x_diff);

    // Calculate x_r = λ^2 - p.x - q.x
    let lambda_squared = blsf_mul(lambda, lambda);
    let x_sub = blsf_sub(lambda_squared, p.value.x);
    let x_r = blsf_sub(x_sub, q.value.x);

    // Calculate y_r = λ(p.x - x_r) - p.y
    let x_diff_r = blsf_sub(p.value.x, x_r);
    let lambda_times_x_diff = blsf_mul(lambda, x_diff_r);
    let y_r = blsf_sub(lambda_times_x_diff, p.value.y);

    // Return the new point
    tempvar result = BLSP(new BLSPStruct(x_r, y_r));
    return result;
}

// Implementation of scalar multiplication for BLSP
// Uses the double-and-add algorithm
func blsp_mul_by{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(p: BLSP, n: U384) -> BLSP {
    alloc_locals;
    let n_is_zero = U384_is_zero(n);
    if (n_is_zero != 0) {
        let res = blsp_point_at_infinity();
        return res;
    }

    let blsf_zero = BLSF_ZERO();
    let x_is_zero = BLSF__eq__(p.value.x, blsf_zero);
    let y_is_zero = BLSF__eq__(p.value.y, blsf_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = blsp_point_at_infinity();

    // Implement the double-and-add algorithm
    let res = blsp_mul_by_bits(p, bits_ptr, bits_len, 0, result);
    return res;
}

func blsp_mul_by_bits{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BLSP, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: BLSP) -> BLSP {
    alloc_locals;

    if (current_bit == bits_len) {
        return result;
    }
    let bit_value = bits_ptr[current_bit];

    // If the bit is 1, add p to the result
    if (bit_value != 0) {
        let new_result = blsp_add(result, p);
        tempvar new_result = new_result;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        tempvar new_result = result;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }
    let new_result = new_result;

    // Double the point for the next iteration
    let doubled_p = blsp_double(p);

    return blsp_mul_by_bits(doubled_p, bits_ptr, bits_len, current_bit + 1, new_result);
}

// BLSP2 represents a point on the BLSP2 curve
// BLSF2 is the base field of the curve
struct BLSP2Struct {
    x: BLSF2,
    y: BLSF2,
}

struct BLSP2 {
    value: BLSP2Struct*,
}

func BLSP2_B() -> BLSF2 {
    tempvar res = BLSF2(
        new BLSF2Struct(U384(new UInt384(4, 0, 0, 0)), U384(new UInt384(4, 0, 0, 0)))
    );
    return res;
}

func blsp2_point_at_infinity() -> BLSP2 {
    let blsf2_zero = BLSF2_ZERO();
    tempvar res = BLSP2(new BLSP2Struct(blsf2_zero, blsf2_zero));
    return res;
}

func BLSP2__eq__{range_check96_ptr: felt*}(p: BLSP2, q: BLSP2) -> felt {
    alloc_locals;
    let is_x_equal = BLSF2__eq__(p.value.x, q.value.x);
    let is_y_equal = BLSF2__eq__(p.value.y, q.value.y);
    let result = is_x_equal * is_y_equal;
    return result;
}

func blsp2_init{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: BLSF2, y: BLSF2
) -> BLSP2 {
    alloc_locals;

    // Get curve parameters for bls12_381 over BLSF2
    // A = 0, B = 4
    let blsf2_zero = BLSF2_ZERO();
    let blsf2_b = BLSP2_B();

    let x_is_zero = BLSF2__eq__(x, blsf2_zero);
    let y_is_zero = BLSF2__eq__(y, blsf2_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        tempvar res = BLSP2(new BLSP2Struct(x, y));
        return res;
    }
    // If the point not the point at infinity, check if it's on the curve
    // Compute y^2
    let y_squared = blsf2_mul(y, y);
    // Compute x^3
    let x_squared = blsf2_mul(x, x);
    let x_cubed = blsf2_mul(x_squared, x);
    // Compute right side of equation: x^3 + A*x + B
    // A = 0, so A*x = 0, and we can skip that term
    let right_side = blsf2_add(x_cubed, blsf2_b);
    // Check if y^2 = x^3 + A*x + B
    let is_on_curve = BLSF2__eq__(y_squared, right_side);
    assert is_on_curve = 1;

    tempvar res = BLSP2(new BLSP2Struct(x, y));
    return res;
}

func blsp2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BLSP2, q: BLSP2
) -> BLSP2 {
    alloc_locals;

    let blsf2_zero = BLSF2_ZERO();
    let x_is_zero = BLSF2__eq__(p.value.x, blsf2_zero);
    let y_is_zero = BLSF2__eq__(p.value.y, blsf2_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        return q;
    }

    let x_is_zero_q = BLSF2__eq__(q.value.x, blsf2_zero);
    let y_is_zero_q = BLSF2__eq__(q.value.y, blsf2_zero);
    if (x_is_zero_q != 0 and y_is_zero_q != 0) {
        return p;
    }

    let x_equal = BLSF2__eq__(p.value.x, q.value.x);
    if (x_equal != 0) {
        let y_equal = BLSF2__eq__(p.value.y, q.value.y);
        if (y_equal != 0) {
            return blsp2_double(p);
        }
        let res = blsp2_point_at_infinity();
        return res;
    }

    // Standard case: compute point addition using the formula:
    // λ = (q.y - p.y) / (q.x - p.x)
    // x_r = λ^2 - p.x - q.x
    // y_r = λ(p.x - x_r) - p.y

    // Calculate λ = (q.y - p.y) / (q.x - p.x)
    let y_diff = blsf2_sub(q.value.y, p.value.y);
    let x_diff = blsf2_sub(q.value.x, p.value.x);
    let lambda = blsf2_div(y_diff, x_diff);

    // Calculate x_r = λ^2 - p.x - q.x
    let lambda_squared = blsf2_mul(lambda, lambda);
    let x_sum = blsf2_add(p.value.x, q.value.x);
    let x_r = blsf2_sub(lambda_squared, x_sum);

    // Calculate y_r = λ(p.x - x_r) - p.y
    let x_diff_r = blsf2_sub(p.value.x, x_r);
    let lambda_times_x_diff = blsf2_mul(lambda, x_diff_r);
    let y_r = blsf2_sub(lambda_times_x_diff, p.value.y);

    // Return the new point
    tempvar result = BLSP2(new BLSP2Struct(x_r, y_r));
    return result;
}

func blsp2_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BLSP2
) -> BLSP2 {
    alloc_locals;

    let blsf2_zero = BLSF2_ZERO();
    let is_x_zero = BLSF2__eq__(p.value.x, blsf2_zero);
    let is_y_zero = BLSF2__eq__(p.value.y, blsf2_zero);
    if (is_x_zero != 0 and is_y_zero != 0) {
        return p;
    }

    // Point doubling formula:
    // λ = (3x^2 + a) / (2y)  [a = 0 for bls12-381]
    // x' = λ^2 - 2x
    // y' = λ(x - x') - y
    // Calculate 3x^2
    let (u384_zero) = get_label_location(U384_ZERO);
    let uint384_zero = cast(u384_zero, UInt384*);
    tempvar three = BLSF2(new BLSF2Struct(U384(new UInt384(3, 0, 0, 0)), U384(uint384_zero)));
    let x_squared = blsf2_mul(p.value.x, p.value.x);
    let three_x_squared = blsf2_mul(three, x_squared);

    // Calculate 2y
    tempvar two = BLSF2(new BLSF2Struct(U384(new UInt384(2, 0, 0, 0)), U384(uint384_zero)));
    let two_y = blsf2_mul(two, p.value.y);
    // Calculate λ = 3x^2 / 2y
    let lambda = blsf2_div(three_x_squared, two_y);
    // Calculate λ^2
    let lambda_squared = blsf2_mul(lambda, lambda);
    // Calculate 2x
    let two_x = blsf2_mul(two, p.value.x);
    // Calculate x' = λ^2 - 2x
    let new_x = blsf2_sub(lambda_squared, two_x);
    // Calculate x - x'
    let x_minus_new_x = blsf2_sub(p.value.x, new_x);
    // Calculate λ(x - x')
    let lambda_times_x_diff = blsf2_mul(lambda, x_minus_new_x);
    // Calculate y' = λ(x - x') - y
    let new_y = blsf2_sub(lambda_times_x_diff, p.value.y);
    tempvar result = BLSP2(new BLSP2Struct(new_x, new_y));
    return result;
}

// Implementation of scalar multiplication for BLSP2
// Uses the double-and-add algorithm
func blsp2_mul_by{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(p: BLSP2, n: U384) -> BLSP2 {
    alloc_locals;
    let n_is_zero = U384_is_zero(n);
    if (n_is_zero != 0) {
        let res = blsp2_point_at_infinity();
        return res;
    }

    let blsf2_zero = BLSF2_ZERO();
    let x_is_zero = BLSF2__eq__(p.value.x, blsf2_zero);
    let y_is_zero = BLSF2__eq__(p.value.y, blsf2_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = blsp2_point_at_infinity();

    // Implement the double-and-add algorithm
    let res = blsp2_mul_by_bits(p, bits_ptr, bits_len, 0, result);
    return res;
}

func blsp2_mul_by_bits{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BLSP2, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: BLSP2) -> BLSP2 {
    alloc_locals;

    if (current_bit == bits_len) {
        return result;
    }
    let bit_value = bits_ptr[current_bit];

    // If the bit is 1, add p to the result
    if (bit_value != 0) {
        let new_result = blsp2_add(result, p);
        tempvar new_result = new_result;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        tempvar new_result = result;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }
    let new_result = new_result;

    // Double the point for the next iteration
    let doubled_p = blsp2_double(p);

    return blsp2_mul_by_bits(doubled_p, bits_ptr, bits_len, current_bit + 1, new_result);
}
