from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.registers import get_label_location

from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.bls12_381 import bls12_381

from ethereum.utils.numeric import U384_ZERO, U384_ONE, U384__eq__
from ethereum_types.numeric import U384

// Field over which the bls12_381 curve is defined.
// BLSF elements are 1-dimensional.
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
// BLSF elements are 2-dimensional.
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
