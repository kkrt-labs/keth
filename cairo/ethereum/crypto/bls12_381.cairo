from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new

from legacy.utils.dict import default_dict_finalize

from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.bls12_381 import bls12_381

from ethereum.utils.numeric import (
    U384_ZERO,
    U384_ONE,
    U384_is_zero,
    get_u384_bits_little,
    U384__eq__,
)
from ethereum_types.numeric import U384, bool

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

func BLSF__eq__(a: BLSF, b: BLSF) -> bool {
    let result = U384__eq__(a.value.c0, b.value.c0);
    let res = bool(result.value);
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
    assert is_inv.value = 1;

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

func BLSF2__eq__(a: BLSF2, b: BLSF2) -> bool {
    alloc_locals;
    let is_c0_equal = U384__eq__(a.value.c0, b.value.c0);
    let is_c1_equal = U384__eq__(a.value.c1, b.value.c1);

    let result = is_c0_equal.value * is_c1_equal.value;
    let res = bool(result);
    return res;
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
    assert is_inv.value = 1;

    return blsf2_mul(a, b_inv);
}

struct BLSF12Struct {
    c0: U384,
    c1: U384,
    c2: U384,
    c3: U384,
    c4: U384,
    c5: U384,
    c6: U384,
    c7: U384,
    c8: U384,
    c9: U384,
    c10: U384,
    c11: U384,
}

struct BLSF12 {
    value: BLSF12Struct*,
}

func BLSF12_ONE() -> BLSF12 {
    let (zero) = get_label_location(U384_ZERO);
    let uint384_zero = cast(zero, UInt384*);
    let (one) = get_label_location(U384_ONE);
    let uint384_one = cast(one, UInt384*);
    tempvar res = BLSF12(
        new BLSF12Struct(
            U384(uint384_one),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
            U384(uint384_zero),
        ),
    );
    return res;
}

func BLSF12__eq__(a: BLSF12, b: BLSF12) -> bool {
    alloc_locals;
    let is_c0_equal = U384__eq__(a.value.c0, b.value.c0);
    let is_c1_equal = U384__eq__(a.value.c1, b.value.c1);
    let is_c2_equal = U384__eq__(a.value.c2, b.value.c2);
    let is_c3_equal = U384__eq__(a.value.c3, b.value.c3);
    let is_c4_equal = U384__eq__(a.value.c4, b.value.c4);
    let is_c5_equal = U384__eq__(a.value.c5, b.value.c5);
    let is_c6_equal = U384__eq__(a.value.c6, b.value.c6);
    let is_c7_equal = U384__eq__(a.value.c7, b.value.c7);
    let is_c8_equal = U384__eq__(a.value.c8, b.value.c8);
    let is_c9_equal = U384__eq__(a.value.c9, b.value.c9);
    let is_c10_equal = U384__eq__(a.value.c10, b.value.c10);
    let is_c11_equal = U384__eq__(a.value.c11, b.value.c11);

    let result = is_c0_equal.value * is_c1_equal.value * is_c2_equal.value * is_c3_equal.value *
        is_c4_equal.value * is_c5_equal.value * is_c6_equal.value * is_c7_equal.value *
        is_c8_equal.value * is_c9_equal.value * is_c10_equal.value * is_c11_equal.value;

    let res = bool(result);
    return res;
}

// BLSF12_mul implements multiplication for BLSF12 elements
// using dictionaries for intermediate calculations
func blsf12_mul{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(a: BLSF12, b: BLSF12) -> BLSF12 {
    alloc_locals;

    tempvar modulus = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));

    // Step 1: Create a dictionary for polynomial multiplication intermediate value and result
    let (zero) = get_label_location(U384_ZERO);
    let zero_u384 = cast(zero, UInt384*);
    let (mul_dict) = default_dict_new(cast(zero_u384, felt));
    tempvar dict_ptr = mul_dict;
    tempvar name = 'blsf12_mul';
    %{ attach_name %}
    let mul_dict_start = mul_dict;

    // Step 2: Perform polynomial multiplication
    // Compute each product a[i] * b[j] and add it to the appropriate position
    compute_polynomial_product{dict_ptr=mul_dict}(a, b, modulus, 0, 0);

    // Step 3: Apply reduction for coefficients 22 down to 12 (in descending order like Python)
    reduce_polynomial{mul_dict=mul_dict}(modulus);

    // Step 4: Create the result BNF12 element from the reduced coefficients
    let bnf12_result = create_blsf12_from_dict{mul_dict=mul_dict}();

    // Step 5: Finalize the dictionary
    default_dict_finalize(mul_dict_start, mul_dict, cast(zero, felt));

    return bnf12_result;
}

func compute_polynomial_product{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    dict_ptr: DictAccess*,
}(a: BLSF12, b: BLSF12, modulus: U384, i: felt, j: felt) {
    alloc_locals;

    // Base case: we've processed all terms
    if (i == 12) {
        return ();
    }
    // If we've processed all j for current i, move to next i
    if (j == 12) {
        return compute_polynomial_product(a, b, modulus, i + 1, 0);
    }

    // Get coefficients, BNF12 can be seen as a U384* list
    let a_segment = cast(a.value, U384*);
    let b_segment = cast(b.value, U384*);
    let a_coeff = a_segment[i];
    let b_coeff = b_segment[j];

    // Compute product using modular multiplication
    let product = mul(a_coeff, b_coeff, modulus);

    // Position in result
    let pos = i + j;

    // Read current value at this position (default to zero if not present)
    let (current_ptr) = dict_read{dict_ptr=dict_ptr}(pos);
    let current = cast(current_ptr, UInt384*);
    // Add product to current value using modular addition
    let new_value = add(U384(current), product, modulus);

    // Write the new value to the dictionary
    dict_write{dict_ptr=dict_ptr}(pos, cast(new_value.value, felt));

    // Continue with next term
    return compute_polynomial_product(a, b, modulus, i, j + 1);
}

// Apply reductions in descending order (from 22 down to 12)
func reduce_polynomial{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    mul_dict: DictAccess*,
}(modulus: U384) {
    alloc_locals;

    _reduce_single_coefficient(modulus, 22);
    _reduce_single_coefficient(modulus, 21);
    _reduce_single_coefficient(modulus, 20);
    _reduce_single_coefficient(modulus, 19);
    _reduce_single_coefficient(modulus, 18);
    _reduce_single_coefficient(modulus, 17);
    _reduce_single_coefficient(modulus, 16);
    _reduce_single_coefficient(modulus, 15);
    _reduce_single_coefficient(modulus, 14);
    _reduce_single_coefficient(modulus, 13);
    _reduce_single_coefficient(modulus, 12);

    return ();
}

// Replicate the following python code:
// mul[i - 6] -= mul[i] * (-18)
// mul[i - 12] -= mul[i] * 82
//
// It is equivalent to:
// mul[i - 6] += mul[i] * 18
// mul[i - 12] -= mul[i] * 82
//
// In cairo it translates to:
// intermediate_mul = mul[i] * 18
// mul[i - 6] = mul[i - 6] + intermediate_mul
// intermediate_mul = mul[i] * 82
// mul[i - 12] = mul[i - 12] - intermediate_mul
func _reduce_single_coefficient{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    mul_dict: DictAccess*,
}(modulus: U384, idx: felt) {
    alloc_locals;

    // Get the coefficient
    let (coeff_i_ptr) = dict_read{dict_ptr=mul_dict}(idx);
    let coeff_i = cast(coeff_i_ptr, UInt384*);

    // Constants for reduction
    tempvar modulus_coeff_0 = U384(new UInt384(2, 0, 0, 0));
    tempvar modulus_coeff_6 = U384(new UInt384(2, 0, 0, 0));

    // Compute mul[i] * 2
    let intermediate_mul = mul(U384(coeff_i), modulus_coeff_6, modulus);
    // Update position idx - 6
    let pos1 = idx - 6;
    let (current1_ptr) = dict_read{dict_ptr=mul_dict}(pos1);

    tempvar current1 = U384(cast(current1_ptr, UInt384*));
    // Add intermediate_mul to current value
    let new_value1 = add(current1, intermediate_mul, modulus);
    // Write the new value to the dictionary
    dict_write{dict_ptr=mul_dict}(pos1, cast(new_value1.value, felt));

    // Compute mul[i] * 2
    let intermediate_mul = mul(U384(coeff_i), modulus_coeff_0, modulus);
    // Update position idx - 12
    let pos2 = idx - 12;
    let (current2_ptr) = dict_read{dict_ptr=mul_dict}(pos2);
    tempvar current2 = U384(cast(current2_ptr, UInt384*));
    // Subtract intermediate_mul from current value
    let new_value2 = sub(current2, intermediate_mul, modulus);
    // Write the new value to the dictionary
    dict_write{dict_ptr=mul_dict}(pos2, cast(new_value2.value, felt));

    return ();
}

func create_blsf12_from_dict{range_check_ptr, mul_dict: DictAccess*}() -> BLSF12 {
    alloc_locals;

    let (result_struct: BLSF12Struct*) = alloc();

    let (c0_ptr) = dict_read{dict_ptr=mul_dict}(0);
    let (c1_ptr) = dict_read{dict_ptr=mul_dict}(1);
    let (c2_ptr) = dict_read{dict_ptr=mul_dict}(2);
    let (c3_ptr) = dict_read{dict_ptr=mul_dict}(3);
    let (c4_ptr) = dict_read{dict_ptr=mul_dict}(4);
    let (c5_ptr) = dict_read{dict_ptr=mul_dict}(5);
    let (c6_ptr) = dict_read{dict_ptr=mul_dict}(6);
    let (c7_ptr) = dict_read{dict_ptr=mul_dict}(7);
    let (c8_ptr) = dict_read{dict_ptr=mul_dict}(8);
    let (c9_ptr) = dict_read{dict_ptr=mul_dict}(9);
    let (c10_ptr) = dict_read{dict_ptr=mul_dict}(10);
    let (c11_ptr) = dict_read{dict_ptr=mul_dict}(11);

    let coeff_ptr = U384(cast(c0_ptr, UInt384*));
    assert result_struct.c0 = coeff_ptr;

    let coeff_ptr = U384(cast(c1_ptr, UInt384*));
    assert result_struct.c1 = coeff_ptr;

    let coeff_ptr = U384(cast(c2_ptr, UInt384*));
    assert result_struct.c2 = coeff_ptr;

    let coeff_ptr = U384(cast(c3_ptr, UInt384*));
    assert result_struct.c3 = coeff_ptr;

    let coeff_ptr = U384(cast(c4_ptr, UInt384*));
    assert result_struct.c4 = coeff_ptr;

    let coeff_ptr = U384(cast(c5_ptr, UInt384*));
    assert result_struct.c5 = coeff_ptr;

    let coeff_ptr = U384(cast(c6_ptr, UInt384*));
    assert result_struct.c6 = coeff_ptr;

    let coeff_ptr = U384(cast(c7_ptr, UInt384*));
    assert result_struct.c7 = coeff_ptr;

    let coeff_ptr = U384(cast(c8_ptr, UInt384*));
    assert result_struct.c8 = coeff_ptr;

    let coeff_ptr = U384(cast(c9_ptr, UInt384*));
    assert result_struct.c9 = coeff_ptr;

    let coeff_ptr = U384(cast(c10_ptr, UInt384*));
    assert result_struct.c10 = coeff_ptr;

    let coeff_ptr = U384(cast(c11_ptr, UInt384*));
    assert result_struct.c11 = coeff_ptr;

    tempvar blsf12_result = BLSF12(result_struct);
    return blsf12_result;
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

// https://github.com/ethereum/py_ecc/blob/36f5ef87ef0d8f5647af66ad8273fb059656fc8a/py_ecc/bls12_381/bls12_381_curve.py#L36
func BLSP_G() -> BLSP {
    tempvar g1 = BLSP(
        new BLSPStruct(
            BLSF(
                new BLSFStruct(
                    U384(
                        new UInt384(
                            0xf97a1aeffb3af00adb22c6bb,
                            0xa14e3a3f171bac586c55e83f,
                            0x4fa9ac0fc3688c4f9774b905,
                            0x17f1d3a73197d7942695638c,
                        ),
                    ),
                ),
            ),
            BLSF(
                new BLSFStruct(
                    U384(
                        new UInt384(
                            0xa2888ae40caa232946c5e7e1,
                            0xdb18cb2c04b3edd03cc744,
                            0x741d8ae4fcf5e095d5d00af6,
                            0x8b3f481e3aaa0f1a09e30ed,
                        ),
                    ),
                ),
            ),
        ),
    );
    return g1;
}

func BLSP__eq__(p: BLSP, q: BLSP) -> bool {
    alloc_locals;
    let is_x_equal = BLSF__eq__(p.value.x, q.value.x);
    let is_y_equal = BLSF__eq__(p.value.y, q.value.y);
    let result = is_x_equal.value * is_y_equal.value;
    let res = bool(result);
    return res;
}

func blsp_point_at_infinity() -> BLSP {
    alloc_locals;

    let blsf_zero = BLSF_ZERO();
    tempvar res = BLSP(new BLSPStruct(blsf_zero, blsf_zero));
    return res;
}

func blsp_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BLSP
) -> BLSP {
    alloc_locals;

    let infinity = blsp_point_at_infinity();
    let is_infinity = BLSP__eq__(p, infinity);
    if (is_infinity.value != 0) {
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
    let is_p_infinity = BLSP__eq__(p, infinity);
    if (is_p_infinity.value != 0) {
        return q;
    }

    let is_q_infinity = BLSP__eq__(q, infinity);
    if (is_q_infinity.value != 0) {
        return p;
    }

    let x_equal = BLSF__eq__(p.value.x, q.value.x);
    if (x_equal.value != 0) {
        let y_equal = BLSF__eq__(p.value.y, q.value.y);
        if (y_equal.value != 0) {
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
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
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

// https://github.com/ethereum/py_ecc/blob/36f5ef87ef0d8f5647af66ad8273fb059656fc8a/py_ecc/bls12_381/bls12_381_curve.py#L45
func BLSP2_G() -> BLSP2 {
    tempvar g2 = BLSP2(
        new BLSP2Struct(
            BLSF2(
                new BLSF2Struct(
                    U384(
                        new UInt384(
                            0xa805bbefd48056c8c121bdb8,
                            0xb4510b647ae3d1770bac0326,
                            0x2dc51051c6e47ad4fa403b02,
                            0x24aa2b2f08f0a9126080527,
                        ),
                    ),
                    U384(
                        new UInt384(
                            0x13945d57e5ac7d055d042b7e,
                            0xb5da61bbdc7f5049334cf112,
                            0x88274f65596bd0d09920b61a,
                            0x13e02b6052719f607dacd3a0,
                        ),
                    ),
                ),
            ),
            BLSF2(
                new BLSF2Struct(
                    U384(
                        new UInt384(
                            0x3baca289e193548608b82801,
                            0x6d429a695160d12c923ac9cc,
                            0xda2e351aadfd9baa8cbdd3a7,
                            0xce5d527727d6e118cc9cdc6,
                        ),
                    ),
                    U384(
                        new UInt384(
                            0x5cec1da1aaa9075ff05f79be,
                            0x267492ab572e99ab3f370d27,
                            0x2bc28b99cb3e287e85a763af,
                            0x606c4a02ea734cc32acd2b0,
                        ),
                    ),
                ),
            ),
        ),
    );

    return g2;
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

func BLSP2__eq__(p: BLSP2, q: BLSP2) -> bool {
    alloc_locals;
    let is_x_equal = BLSF2__eq__(p.value.x, q.value.x);
    let is_y_equal = BLSF2__eq__(p.value.y, q.value.y);
    let result = is_x_equal.value * is_y_equal.value;
    let res = bool(result);
    return res;
}

func blsp2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BLSP2, q: BLSP2
) -> BLSP2 {
    alloc_locals;

    let blsf2_zero = BLSF2_ZERO();
    let x_is_zero = BLSF2__eq__(p.value.x, blsf2_zero);
    let y_is_zero = BLSF2__eq__(p.value.y, blsf2_zero);
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
        return q;
    }

    let x_is_zero_q = BLSF2__eq__(q.value.x, blsf2_zero);
    let y_is_zero_q = BLSF2__eq__(q.value.y, blsf2_zero);
    if (x_is_zero_q.value != 0 and y_is_zero_q.value != 0) {
        return p;
    }

    let x_equal = BLSF2__eq__(p.value.x, q.value.x);
    if (x_equal.value != 0) {
        let y_equal = BLSF2__eq__(p.value.y, q.value.y);
        if (y_equal.value != 0) {
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
    if (is_x_zero.value != 0 and is_y_zero.value != 0) {
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
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
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

struct TupleBLSPBLSP2Struct {
    blsp: BLSP,
    blsp2: BLSP2,
}

struct TupleBLSPBLSP2 {
    value: TupleBLSPBLSP2Struct*,
}

struct TupleTupleBLSPBLSP2Struct {
    pair1: TupleBLSPBLSP2,
    pair2: TupleBLSPBLSP2,
}

struct TupleTupleBLSPBLSP2 {
    value: TupleTupleBLSPBLSP2Struct*,
}
