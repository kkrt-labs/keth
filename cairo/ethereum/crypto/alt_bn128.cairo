from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import (
    UInt384,
    ModBuiltin,
    PoseidonBuiltin,
    BitwiseBuiltin,
)
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.registers import get_label_location

from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.alt_bn128 import alt_bn128
from definitions import G1G2Pair, G1Point as G1PointGaraga, G2Point as G2PointGaraga
from bn254.multi_pairing_1 import multi_pairing_1P

from ethereum.exceptions import Exception, ValueError

from ethereum.utils.numeric import (
    divmod,
    U384_ZERO,
    U384_ONE,
    U384_is_zero,
    get_u384_bits_little,
    U384__eq__,
)
from ethereum_types.numeric import U384, bool

// Field over which the alt_bn128 curve is defined.
// BNF elements are 1-dimensional.
struct BNFStruct {
    c0: U384,
}

struct BNF {
    value: BNFStruct*,
}

func BNF_ZERO() -> BNF {
    let (u384_zero) = get_label_location(U384_ZERO);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    tempvar res = BNF(new BNFStruct(U384(u384_zero_ptr)));
    return res;
}

func BNF__eq__(a: BNF, b: BNF) -> bool {
    let result = U384__eq__(a.value.c0, b.value.c0);
    let res = bool(result.value);
    return res;
}

func bnf_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF, b: BNF
) -> BNF {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    let result = mul(a.value.c0, b.value.c0, modulus);
    tempvar res = BNF(new BNFStruct(result));
    return res;
}

func bnf_div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF, b: BNF
) -> BNF {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local b_inv: BNF;

    %{ bnf_multiplicative_inverse %}

    let res = bnf_mul(b, b_inv);
    let (one) = get_label_location(U384_ONE);
    let uint384_one = cast(one, UInt384*);
    tempvar bnf_one = BNF(new BNFStruct(U384(uint384_one)));
    let is_inv = BNF__eq__(res, bnf_one);
    assert is_inv.value = 1;

    return bnf_mul(a, b_inv);
}

func bnf_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF, b: BNF
) -> BNF {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    let result = sub(a.value.c0, b.value.c0, modulus);
    tempvar res = BNF(new BNFStruct(result));
    return res;
}

func bnf_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF, b: BNF
) -> BNF {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    let result = add(a.value.c0, b.value.c0, modulus);
    tempvar res = BNF(new BNFStruct(result));
    return res;
}

// Quadratic extension field of BNF.
// BNF elements are 2-dimensional.
struct BNF2Struct {
    c0: U384,
    c1: U384,
}

struct BNF2 {
    value: BNF2Struct*,
}

func bnf2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF2, b: BNF2
) -> BNF2 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = add(a.value.c0, b.value.c0, modulus);
    let res_c1 = add(a.value.c1, b.value.c1, modulus);

    tempvar res = BNF2(new BNF2Struct(res_c0, res_c1));
    return res;
}

// Division of a by b is done by computing the modular inverse of b, verify it exists
// and multiply a by this modular inverse.
func bnf2_div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF2, b: BNF2
) -> BNF2 {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local b_inv: BNF2;

    %{ bnf2_multiplicative_inverse %}
    let res = bnf2_mul(b, b_inv);
    let bnf2_one = BNF2_ONE();
    let is_inv = BNF2__eq__(res, bnf2_one);
    assert is_inv.value = 1;

    return bnf2_mul(a, b_inv);
}

func bnf2_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF2, b: BNF2
) -> BNF2 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = sub(a.value.c0, b.value.c0, modulus);
    let res_c1 = sub(a.value.c1, b.value.c1, modulus);

    tempvar res = BNF2(new BNF2Struct(res_c0, res_c1));
    return res;
}

func BNF2_ZERO() -> BNF2 {
    let (u384_zero) = get_label_location(U384_ZERO);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    tempvar res = BNF2(new BNF2Struct(U384(u384_zero_ptr), U384(u384_zero_ptr)));
    return res;
}

func BNF2_ONE() -> BNF2 {
    let (u384_zero) = get_label_location(U384_ZERO);
    let (u384_one) = get_label_location(U384_ONE);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    let u384_one_ptr = cast(u384_one, UInt384*);
    tempvar res = BNF2(new BNF2Struct(U384(u384_one_ptr), U384(u384_zero_ptr)));
    return res;
}

func BNF2__eq__(a: BNF2, b: BNF2) -> bool {
    alloc_locals;
    let is_c0_equal = U384__eq__(a.value.c0, b.value.c0);
    let is_c1_equal = U384__eq__(a.value.c1, b.value.c1);

    let result = is_c0_equal.value * is_c1_equal.value;
    let res = bool(result);
    return res;
}

// BNF2 multiplication
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
func bnf2_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF2, b: BNF2
) -> BNF2 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

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
    // No reduction needed for res[1] = mul[1] in BNF2 with degree 2
    let res_c1 = mul_1;

    tempvar res = BNF2(new BNF2Struct(res_c0, res_c1));
    return res;
}

// BNP2 represents a point on the BNP2 curve
// BNF2 is the base field of the curve
struct BNP2Struct {
    x: BNF2,
    y: BNF2,
}

struct BNP2 {
    value: BNP2Struct*,
}

func BNP2_B() -> BNF2 {
    tempvar res = BNF2(
        new BNF2Struct(
            U384(
                new UInt384(
                    27810052284636130223308486885,
                    40153378333836448380344387045,
                    3104278944836790958,
                    0,
                ),
            ),
            U384(
                new UInt384(
                    70926583776874220189091304914,
                    63498449372070794915149226116,
                    42524369107353300,
                    0,
                ),
            ),
        ),
    );
    return res;
}

func bnp2_point_at_infinity() -> BNP2 {
    let bnf2_zero = BNF2_ZERO();
    tempvar res = BNP2(new BNP2Struct(bnf2_zero, bnf2_zero));
    return res;
}

func BNP2__eq__(p: BNP2, q: BNP2) -> bool {
    alloc_locals;
    let is_x_equal = BNF2__eq__(p.value.x, q.value.x);
    let is_y_equal = BNF2__eq__(p.value.y, q.value.y);
    let result = is_x_equal.value * is_y_equal.value;
    let res = bool(result);
    return res;
}

func bnp2_init{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: BNF2, y: BNF2
) -> (BNP2, Exception*) {
    alloc_locals;

    // Get curve parameters for alt_bn128 over BNF2
    // A = 0, B = 3
    let bnf2_zero = BNF2_ZERO();
    let bnf2_b = BNP2_B();

    let x_is_zero = BNF2__eq__(x, bnf2_zero);
    let y_is_zero = BNF2__eq__(y, bnf2_zero);
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
        tempvar res = BNP2(new BNP2Struct(x, y));
        let ok = cast(0, Exception*);
        return (res, ok);
    }
    // If the point not the point at infinity, check if it's on the curve
    // Compute y^2
    let y_squared = bnf2_mul(y, y);
    // Compute x^3
    let x_squared = bnf2_mul(x, x);
    let x_cubed = bnf2_mul(x_squared, x);
    // Compute right side of equation: x^3 + A*x + B
    // A = 0, so A*x = 0, and we can skip that term
    let right_side = bnf2_add(x_cubed, bnf2_b);
    // Check if y^2 = x^3 + A*x + B
    let is_on_curve = BNF2__eq__(y_squared, right_side);

    tempvar res = BNP2(new BNP2Struct(x, y));
    if (is_on_curve.value != 0) {
        let ok = cast(0, Exception*);
        return (res, ok);
    }
    tempvar err = new Exception(ValueError);
    return (res, err);
}

func bnp2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP2, q: BNP2
) -> BNP2 {
    alloc_locals;

    let bnf2_zero = BNF2_ZERO();
    let x_is_zero = BNF2__eq__(p.value.x, bnf2_zero);
    let y_is_zero = BNF2__eq__(p.value.y, bnf2_zero);
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
        return q;
    }

    let x_is_zero_q = BNF2__eq__(q.value.x, bnf2_zero);
    let y_is_zero_q = BNF2__eq__(q.value.y, bnf2_zero);
    if (x_is_zero_q.value != 0 and y_is_zero_q.value != 0) {
        return p;
    }

    let x_equal = BNF2__eq__(p.value.x, q.value.x);
    if (x_equal.value != 0) {
        let y_equal = BNF2__eq__(p.value.y, q.value.y);
        if (y_equal.value != 0) {
            return bnp2_double(p);
        }
        let res = bnp2_point_at_infinity();
        return res;
    }

    // Standard case: compute point addition using the formula:
    // λ = (q.y - p.y) / (q.x - p.x)
    // x_r = λ^2 - p.x - q.x
    // y_r = λ(p.x - x_r) - p.y

    // Calculate λ = (q.y - p.y) / (q.x - p.x)
    let y_diff = bnf2_sub(q.value.y, p.value.y);
    let x_diff = bnf2_sub(q.value.x, p.value.x);
    let lambda = bnf2_div(y_diff, x_diff);

    // Calculate x_r = λ^2 - p.x - q.x
    let lambda_squared = bnf2_mul(lambda, lambda);
    let x_sum = bnf2_add(p.value.x, q.value.x);
    let x_r = bnf2_sub(lambda_squared, x_sum);

    // Calculate y_r = λ(p.x - x_r) - p.y
    let x_diff_r = bnf2_sub(p.value.x, x_r);
    let lambda_times_x_diff = bnf2_mul(lambda, x_diff_r);
    let y_r = bnf2_sub(lambda_times_x_diff, p.value.y);

    // Return the new point
    tempvar result = BNP2(new BNP2Struct(x_r, y_r));
    return result;
}

func bnp2_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP2
) -> BNP2 {
    alloc_locals;

    let bnf2_zero = BNF2_ZERO();
    let is_x_zero = BNF2__eq__(p.value.x, bnf2_zero);
    let is_y_zero = BNF2__eq__(p.value.y, bnf2_zero);
    if (is_x_zero.value != 0 and is_y_zero.value != 0) {
        return p;
    }

    // Point doubling formula:
    // λ = (3x^2 + a) / (2y)  [a = 0 for alt_bn128]
    // x' = λ^2 - 2x
    // y' = λ(x - x') - y
    // Calculate 3x^2
    let (u384_zero) = get_label_location(U384_ZERO);
    let uint384_zero = cast(u384_zero, UInt384*);
    tempvar three = BNF2(new BNF2Struct(U384(new UInt384(3, 0, 0, 0)), U384(uint384_zero)));
    let x_squared = bnf2_mul(p.value.x, p.value.x);
    let three_x_squared = bnf2_mul(three, x_squared);

    // Calculate 2y
    tempvar two = BNF2(new BNF2Struct(U384(new UInt384(2, 0, 0, 0)), U384(uint384_zero)));
    let two_y = bnf2_mul(two, p.value.y);
    // Calculate λ = 3x^2 / 2y
    let lambda = bnf2_div(three_x_squared, two_y);
    // Calculate λ^2
    let lambda_squared = bnf2_mul(lambda, lambda);
    // Calculate 2x
    let two_x = bnf2_mul(two, p.value.x);
    // Calculate x' = λ^2 - 2x
    let new_x = bnf2_sub(lambda_squared, two_x);
    // Calculate x - x'
    let x_minus_new_x = bnf2_sub(p.value.x, new_x);
    // Calculate λ(x - x')
    let lambda_times_x_diff = bnf2_mul(lambda, x_minus_new_x);
    // Calculate y' = λ(x - x') - y
    let new_y = bnf2_sub(lambda_times_x_diff, p.value.y);
    tempvar result = BNP2(new BNP2Struct(new_x, new_y));
    return result;
}

// Implementation of scalar multiplication for BNP2
// Uses the double-and-add algorithm
func bnp2_mul_by{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(p: BNP2, n: U384) -> BNP2 {
    alloc_locals;
    let n_is_zero = U384_is_zero(n);
    if (n_is_zero != 0) {
        let res = bnp2_point_at_infinity();
        return res;
    }

    let bnf2_zero = BNF2_ZERO();
    let x_is_zero = BNF2__eq__(p.value.x, bnf2_zero);
    let y_is_zero = BNF2__eq__(p.value.y, bnf2_zero);
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = bnp2_point_at_infinity();

    // Implement the double-and-add algorithm
    let res = bnp2_mul_by_bits(p, bits_ptr, bits_len, 0, result);
    return res;
}

func bnp2_mul_by_bits{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP2, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: BNP2) -> BNP2 {
    alloc_locals;

    if (current_bit == bits_len) {
        return result;
    }
    let bit_value = bits_ptr[current_bit];

    // If the bit is 1, add p to the result
    if (bit_value != 0) {
        let new_result = bnp2_add(result, p);
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
    let doubled_p = bnp2_double(p);

    return bnp2_mul_by_bits(doubled_p, bits_ptr, bits_len, current_bit + 1, new_result);
}

// BNF12 represents a field element in the BNF12 extension field
// This is a 12-degree extension of the base field used in alt_bn128 curve
struct BNF12Struct {
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

struct BNF12 {
    value: BNF12Struct*,
}

func BNF12_ZERO() -> BNF12 {
    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar bnf12_zero = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    return bnf12_zero;
}

func BNF12_ONE() -> BNF12 {
    let (zero) = get_label_location(U384_ZERO);
    let uint384_zero = cast(zero, UInt384*);
    let (one) = get_label_location(U384_ONE);
    let uint384_one = cast(one, UInt384*);
    tempvar bnf12_one = BNF12(
        new BNF12Struct(
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
    return bnf12_one;
}

// BNF12_mul implements multiplication for BNF12 elements
// using dictionaries for intermediate calculations
func bnf12_mul{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(a: BNF12, b: BNF12) -> BNF12 {
    alloc_locals;

    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    // Step 1: Create a dictionary for polynomial multiplication intermediate value and result
    let (zero) = get_label_location(U384_ZERO);
    let zero_u384 = cast(zero, UInt384*);
    let (mul_dict) = default_dict_new(cast(zero_u384, felt));
    tempvar dict_ptr = mul_dict;
    tempvar name = 'bnf12_mul';
    %{ attach_name %}
    let mul_dict_start = mul_dict;

    // Step 2: Perform polynomial multiplication
    // Compute each product a[i] * b[j] and add it to the appropriate position
    compute_polynomial_product{dict_ptr=mul_dict}(a, b, modulus, 0, 0);

    // Step 3: Apply reduction for coefficients 22 down to 12 (in descending order like Python)
    reduce_polynomial{mul_dict=mul_dict}(modulus);

    // Step 4: Create the result BNF12 element from the reduced coefficients
    let bnf12_result = create_bnf12_from_dict{mul_dict=mul_dict}();

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
}(a: BNF12, b: BNF12, modulus: U384, i: felt, j: felt) {
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
    tempvar modulus_coeff_0 = U384(new UInt384(82, 0, 0, 0));
    tempvar modulus_coeff_6 = U384(new UInt384(18, 0, 0, 0));

    // Compute mul[i] * 18
    let intermediate_mul = mul(U384(coeff_i), modulus_coeff_6, modulus);
    // Update position idx - 6
    let pos1 = idx - 6;
    let (current1_ptr) = dict_read{dict_ptr=mul_dict}(pos1);

    tempvar current1 = U384(cast(current1_ptr, UInt384*));
    // Add intermediate_mul to current value
    let new_value1 = add(current1, intermediate_mul, modulus);
    // Write the new value to the dictionary
    dict_write{dict_ptr=mul_dict}(pos1, cast(new_value1.value, felt));

    // Compute mul[i] * 82
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

func create_bnf12_from_dict{range_check_ptr, mul_dict: DictAccess*}() -> BNF12 {
    alloc_locals;

    let (result_struct: BNF12Struct*) = alloc();

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

    tempvar bnf12_result = BNF12(result_struct);
    return bnf12_result;
}

func BNF12__eq__(a: BNF12, b: BNF12) -> bool {
    alloc_locals;
    // Check equality for each component
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

    // All coefficients must be equal for the BNF12 elements to be equal
    let result = is_c0_equal.value * is_c1_equal.value * is_c2_equal.value * is_c3_equal.value *
        is_c4_equal.value * is_c5_equal.value * is_c6_equal.value * is_c7_equal.value *
        is_c8_equal.value * is_c9_equal.value * is_c10_equal.value * is_c11_equal.value;

    let res = bool(result);
    return res;
}

// alt_bn128 curve defined over BNF (Fp)
// BNP represents a point on the curve.
struct BNPStruct {
    x: BNF,
    y: BNF,
}

struct BNP {
    value: BNPStruct*,
}

func BNP__eq__(p: BNP, q: BNP) -> bool {
    alloc_locals;
    let is_x_equal = BNF__eq__(p.value.x, q.value.x);
    let is_y_equal = BNF__eq__(p.value.y, q.value.y);
    let result = is_x_equal.value * is_y_equal.value;
    let res = bool(result);
    return res;
}

func bnp_point_at_infinity() -> BNP {
    alloc_locals;

    let bnf_zero = BNF_ZERO();
    tempvar res = BNP(new BNPStruct(bnf_zero, bnf_zero));
    return res;
}

// Returns a BNP, a point that is verified to be on the alt_bn128 curve over Fp.
func bnp_init{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: BNF, y: BNF
) -> (BNP, Exception*) {
    alloc_locals;

    let infinity = bnp_point_at_infinity();
    let is_infinity = BNP__eq__(BNP(new BNPStruct(x, y)), infinity);
    if (is_infinity.value != 0) {
        let ok = cast(0, Exception*);
        return (infinity, ok);
    }

    tempvar b = U384(new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3));
    tempvar b_bnf = BNF(new BNFStruct(b));

    // Check if y^2 = x^3 + B
    let y_squared = bnf_mul(y, y);
    let x_squared = bnf_mul(x, x);
    let x_cubed = bnf_mul(x_squared, x);
    let right_side = bnf_add(x_cubed, b_bnf);
    let is_on_curve = BNF__eq__(y_squared, right_side);

    tempvar res = BNP(new BNPStruct(x, y));
    if (is_on_curve.value != 0) {
        let ok = cast(0, Exception*);
        return (res, ok);
    }
    tempvar err = new Exception(ValueError);
    return (res, err);
}

func bnp_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP
) -> BNP {
    alloc_locals;

    let infinity = bnp_point_at_infinity();
    let p_inf = BNP__eq__(p, infinity);
    if (p_inf.value != 0) {
        return infinity;
    }

    // Point doubling formula for Alt-BN128 (a = 0):
    // λ = (3x²) / (2y)
    // x' = λ² - 2x
    // y' = λ(x - x') - y

    // Calculate λ = (3x²) / (2y)
    let x_squared = bnf_mul(p.value.x, p.value.x);
    tempvar three = BNF(new BNFStruct(U384(new UInt384(3, 0, 0, 0))));
    let three_x_squared = bnf_mul(three, x_squared);
    tempvar two = BNF(new BNFStruct(U384(new UInt384(2, 0, 0, 0))));
    let two_y = bnf_mul(two, p.value.y);
    let lambda = bnf_div(three_x_squared, two_y);

    // Calculate x' = λ² - 2x
    let lambda_squared = bnf_mul(lambda, lambda);
    let two_x = bnf_mul(two, p.value.x);
    let new_x = bnf_sub(lambda_squared, two_x);

    // Calculate y' = λ(x - x') - y
    let x_diff = bnf_sub(p.value.x, new_x);
    let lambda_x_diff = bnf_mul(lambda, x_diff);
    let new_y = bnf_sub(lambda_x_diff, p.value.y);

    // Return the resulting point
    tempvar res = BNP(new BNPStruct(new_x, new_y));
    return res;
}

// Add two points on the base curve
func bnp_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP, q: BNP
) -> BNP {
    alloc_locals;

    let infinity = bnp_point_at_infinity();
    let p_inf = BNP__eq__(p, infinity);
    if (p_inf.value != 0) {
        return q;
    }

    let q_inf = BNP__eq__(q, infinity);
    if (q_inf.value != 0) {
        return p;
    }

    let x_equal = BNF__eq__(p.value.x, q.value.x);
    if (x_equal.value != 0) {
        let y_equal = BNF__eq__(p.value.y, q.value.y);
        if (y_equal.value != 0) {
            return bnp_double(p);
        }
        let res = bnp_point_at_infinity();
        return res;
    }

    // Standard case: compute point addition using the formula:
    // λ = (q.y - p.y) / (q.x - p.x)
    // x_r = λ^2 - p.x - q.x
    // y_r = λ(p.x - x_r) - p.y

    // Calculate λ = (q.y - p.y) / (q.x - p.x)
    let y_diff = bnf_sub(q.value.y, p.value.y);
    let x_diff = bnf_sub(q.value.x, p.value.x);
    let lambda = bnf_div(y_diff, x_diff);

    // Calculate x_r = λ^2 - p.x - q.x
    let lambda_squared = bnf_mul(lambda, lambda);
    let x_sub = bnf_sub(lambda_squared, p.value.x);
    let x_r = bnf_sub(x_sub, q.value.x);

    // Calculate y_r = λ(p.x - x_r) - p.y
    let x_diff_r = bnf_sub(p.value.x, x_r);
    let lambda_times_x_diff = bnf_mul(lambda, x_diff_r);
    let y_r = bnf_sub(lambda_times_x_diff, p.value.y);

    // Return the new point
    tempvar result = BNP(new BNPStruct(x_r, y_r));
    return result;
}

// Implementation of scalar multiplication for BNP
// Uses the double-and-add algorithm
func bnp_mul_by{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(p: BNP, n: U384) -> BNP {
    alloc_locals;
    let n_is_zero = U384_is_zero(n);
    if (n_is_zero != 0) {
        let res = bnp_point_at_infinity();
        return res;
    }

    let bnf_zero = BNF_ZERO();
    let x_is_zero = BNF__eq__(p.value.x, bnf_zero);
    let y_is_zero = BNF__eq__(p.value.y, bnf_zero);
    if (x_is_zero.value != 0 and y_is_zero.value != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = bnp_point_at_infinity();

    // Implement the double-and-add algorithm
    let res = bnp_mul_by_bits(p, bits_ptr, bits_len, 0, result);
    return res;
}

func bnp_mul_by_bits{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: BNP) -> BNP {
    alloc_locals;

    if (current_bit == bits_len) {
        return result;
    }
    let bit_value = bits_ptr[current_bit];

    // If the bit is 1, add p to the result
    if (bit_value != 0) {
        let new_result = bnp_add(result, p);
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
    let doubled_p = bnp_double(p);

    return bnp_mul_by_bits(doubled_p, bits_ptr, bits_len, current_bit + 1, new_result);
}

func pairing{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(q: BNP2, p: BNP) -> BNF12 {
    alloc_locals;
    let infinity_p = bnp_point_at_infinity();
    let is_infinity_p = BNP__eq__(p, infinity_p);
    let infinity_q = bnp2_point_at_infinity();
    let is_infinity_q = BNP2__eq__(q, infinity_q);
    let is_infinity = is_infinity_p.value + is_infinity_q.value;

    if (is_infinity != 0) {
        let res = BNF12_ONE();
        return res;
    }

    let p_garaga = G1PointGaraga([p.value.x.value.c0.value], [p.value.y.value.c0.value]);
    let q_garaga = G2PointGaraga(
        [q.value.x.value.c0.value],
        [q.value.x.value.c1.value],
        [q.value.y.value.c0.value],
        [q.value.y.value.c1.value],
    );
    tempvar pair = new G1G2Pair(p_garaga, q_garaga);
    let (res_garaga) = multi_pairing_1P(pair);

    tempvar res = BNF12(
        new BNF12Struct(
            U384(new res_garaga.w0),
            U384(new res_garaga.w1),
            U384(new res_garaga.w2),
            U384(new res_garaga.w3),
            U384(new res_garaga.w4),
            U384(new res_garaga.w5),
            U384(new res_garaga.w6),
            U384(new res_garaga.w7),
            U384(new res_garaga.w8),
            U384(new res_garaga.w9),
            U384(new res_garaga.w10),
            U384(new res_garaga.w11),
        ),
    );
    return res;
}
