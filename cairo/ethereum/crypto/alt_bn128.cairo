from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, PoseidonBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math_cmp import is_le

from cairo_core.control_flow import raise
from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.alt_bn128 import alt_bn128
from cairo_ec.curve.g1_point import G1Point, G1PointStruct
from cairo_ec.circuits.ec_ops_compiled import assert_on_curve
from bn254.final_exp import final_exponentiation
from definitions import E12D

from ethereum.utils.numeric import (
    divmod,
    U384_ZERO,
    U384_ONE,
    U384_is_zero,
    get_u384_bits_little,
    U384__eq__,
)
from ethereum_types.numeric import U384

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

func BNF__eq__{range_check96_ptr: felt*}(a: BNF, b: BNF) -> felt {
    let result = U384__eq__(a.value.c0, b.value.c0);
    return result.value;
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
    assert is_inv = 1;

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
    assert is_inv = 1;

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

func BNF2__eq__{range_check96_ptr: felt*}(a: BNF2, b: BNF2) -> felt {
    alloc_locals;
    let is_c0_equal = U384__eq__(a.value.c0, b.value.c0);
    let is_c1_equal = U384__eq__(a.value.c1, b.value.c1);

    let result = is_c0_equal.value * is_c1_equal.value;

    return result;
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

func BNP2__eq__{range_check96_ptr: felt*}(p: BNP2, q: BNP2) -> felt {
    alloc_locals;
    let is_x_equal = BNF2__eq__(p.value.x, q.value.x);
    let is_y_equal = BNF2__eq__(p.value.y, q.value.y);
    let result = is_x_equal * is_y_equal;
    return result;
}

func bnp2_init{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: BNF2, y: BNF2
) -> BNP2 {
    alloc_locals;

    // Get curve parameters for alt_bn128 over BNF2
    // A = 0, B = 3
    let bnf2_zero = BNF2_ZERO();
    let bnf2_b = BNP2_B();

    let x_is_zero = BNF2__eq__(x, bnf2_zero);
    let y_is_zero = BNF2__eq__(y, bnf2_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        tempvar res = BNP2(new BNP2Struct(x, y));
        return res;
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
    assert is_on_curve = 1;

    tempvar res = BNP2(new BNP2Struct(x, y));
    return res;
}

func bnp2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP2, q: BNP2
) -> BNP2 {
    alloc_locals;

    let bnf2_zero = BNF2_ZERO();
    let x_is_zero = BNF2__eq__(p.value.x, bnf2_zero);
    let y_is_zero = BNF2__eq__(p.value.y, bnf2_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        return q;
    }

    let x_is_zero_q = BNF2__eq__(q.value.x, bnf2_zero);
    let y_is_zero_q = BNF2__eq__(q.value.y, bnf2_zero);
    if (x_is_zero_q != 0 and y_is_zero_q != 0) {
        return p;
    }

    let x_equal = BNF2__eq__(p.value.x, q.value.x);
    if (x_equal != 0) {
        let y_equal = BNF2__eq__(p.value.y, q.value.y);
        if (y_equal != 0) {
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
    if (is_x_zero != 0 and is_y_zero != 0) {
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
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
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
    if (x_is_zero != 0 and y_is_zero != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = bnp2_point_at_infinity();

    // Implement the double-and-add algorithm
    return bnp2_mul_by_bits(p, bits_ptr, bits_len, 0, result);
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

struct TupleBNF12Struct {
    data: BNF12*,
    len: felt,
}

struct TupleBNF12 {
    value: TupleBNF12Struct*,
}

// Pre-calculated Frobenius coefficients for BNF12
// Taken from EELS: BNF12.FROBENIUS_COEFFICIENTS
// but directly converted to a BNF12 element.
// Used in the frobenius function
func FROBENIUS_COEFFICIENTS() -> TupleBNF12 {
    let (data: BNF12*) = alloc();

    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar frob_coeff_0 = BNF12(
        new BNF12Struct(
            U384(new UInt384(1, 0, 0, 0)),
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
    tempvar frob_coeff_1 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    78578536060309107515104581973,
                    8400990441217749534645805517,
                    2129232506395746792,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    44235539729515559427878642348,
                    51435548181543843798942585463,
                    2623794231377586150,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_2 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    78349051542967260616978669991,
                    41008965243346889244325114448,
                    2606301674313511803,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    3554987122848029851499088802,
                    23410605513395334791406955037,
                    1642095672556236320,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_3 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    34033322189376251481554474477,
                    4280726608038811945455405562,
                    2396879586936032454,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    44452636005823129879501320419,
                    2172088618007306609220419017,
                    558513134835401882,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_4 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    34584991903128600703749850251,
                    30551585780948950581852748505,
                    3207895186965489429,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    8625418388212319703725211942,
                    49278841972922804394128691946,
                    3176267935786044142,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_5 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    25824796045544905201978036136,
                    6187323640648889100853233532,
                    1945681021778971854,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    32048825361800970863735745611,
                    50290947057026719718192499609,
                    1345717340070545013,
                    0,
                ),
            ),
        ),
    );
    tempvar frob_coeff_6 = BNF12(
        new BNF12Struct(
            U384(new UInt384(18, 0, 0, 0)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    32324006162389411176778628422,
                    57042285082623239461879769745,
                    3486998266802970665,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_7 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    20641937728814725449375590170,
                    24203765336848429100941234658,
                    2413436878271618679,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    32973632616344641255217996786,
                    48641294641405489927233964227,
                    1357765760407223873,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_8 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    20943551402699757736052663606,
                    8544852239310357649650147702,
                    241365413500116110,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    33203117133686488153343908768,
                    16033319839276350217554655296,
                    880696592489458862,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_9 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    42804809713167380845233239921,
                    17529656269681834330436670968,
                    1766952951277271856,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    77518846487277497288768104282,
                    52761558474584427516424364182,
                    1090118679866938211,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_10 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    52121014111839700750532454325,
                    33770943432150980509194768534,
                    879241820764098843,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    76967176773525148066572728508,
                    26490699301674288880027021239,
                    279103079837481236,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    tempvar frob_coeff_11 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    24546180515706619156045117815,
                    74248057992238438118561754263,
                    2404151338884387196,
                    0,
                ),
            ),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(
                new UInt384(
                    6499210116844505974800592287,
                    50854961441974350361026536213,
                    1541317245023998811,
                    0,
                ),
            ),
        ),
    );

    assert [data] = frob_coeff_0;
    assert [data + 1] = frob_coeff_1;
    assert [data + 2] = frob_coeff_2;
    assert [data + 3] = frob_coeff_3;
    assert [data + 4] = frob_coeff_4;
    assert [data + 5] = frob_coeff_5;
    assert [data + 6] = frob_coeff_6;
    assert [data + 7] = frob_coeff_7;
    assert [data + 8] = frob_coeff_8;
    assert [data + 9] = frob_coeff_9;
    assert [data + 10] = frob_coeff_10;
    assert [data + 11] = frob_coeff_11;
    tempvar frob_coeffs = TupleBNF12(new TupleBNF12Struct(data, 12));
    return frob_coeffs;
}

// BNF12_W returns the value of w (omega), which is a 6th root of 9 + i
func BNF12_W() -> BNF12 {
    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar bnf12_w = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(new UInt384(1, 0, 0, 0)),
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
    return bnf12_w;
}

// BNF12_W_POW_2 returns the value of w^2
func BNF12_W_POW_2() -> BNF12 {
    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar bnf12_w_pow_2 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(new UInt384(1, 0, 0, 0)),
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
    return bnf12_w_pow_2;
}

// BNF12_W_POW_3 returns the value of w^3
func BNF12_W_POW_3() -> BNF12 {
    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar bnf12_w_pow_3 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(new UInt384(1, 0, 0, 0)),
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
    return bnf12_w_pow_3;
}

// BNF12_I_PLUS_9 returns the value of i + 9, which is w^6 in the field
// This corresponds to BNF12.w**6
func BNF12_I_PLUS_9() -> BNF12 {
    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar BNF12_I_PLUS_9 = BNF12(
        new BNF12Struct(
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(new UInt384(1, 0, 0, 0)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
            U384(cast(u384_zero, UInt384*)),
        ),
    );
    return BNF12_I_PLUS_9;
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

// Int limited to 384 bits
func bnf12_from_int{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384
) -> BNF12 {
    tempvar one_uint384 = U384(new UInt384(1, 0, 0, 0));
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    let x_reduced = mul(x, one_uint384, modulus);
    let (u384_zero) = get_label_location(U384_ZERO);
    let uint384_zero = cast(u384_zero, UInt384*);
    tempvar bnf12_from_uint = BNF12(
        new BNF12Struct(
            x_reduced,
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
    return bnf12_from_uint;
}

// Addition between two BNF12 elements.
func bnf12_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF12, b: BNF12
) -> BNF12 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = add(a.value.c0, b.value.c0, modulus);
    let res_c1 = add(a.value.c1, b.value.c1, modulus);
    let res_c2 = add(a.value.c2, b.value.c2, modulus);
    let res_c3 = add(a.value.c3, b.value.c3, modulus);
    let res_c4 = add(a.value.c4, b.value.c4, modulus);
    let res_c5 = add(a.value.c5, b.value.c5, modulus);
    let res_c6 = add(a.value.c6, b.value.c6, modulus);
    let res_c7 = add(a.value.c7, b.value.c7, modulus);
    let res_c8 = add(a.value.c8, b.value.c8, modulus);
    let res_c9 = add(a.value.c9, b.value.c9, modulus);
    let res_c10 = add(a.value.c10, b.value.c10, modulus);
    let res_c11 = add(a.value.c11, b.value.c11, modulus);

    tempvar res = BNF12(
        new BNF12Struct(
            res_c0,
            res_c1,
            res_c2,
            res_c3,
            res_c4,
            res_c5,
            res_c6,
            res_c7,
            res_c8,
            res_c9,
            res_c10,
            res_c11,
        ),
    );
    return res;
}

// Subtraction between two BNF12 elements.
func bnf12_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF12, b: BNF12
) -> BNF12 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = sub(a.value.c0, b.value.c0, modulus);
    let res_c1 = sub(a.value.c1, b.value.c1, modulus);
    let res_c2 = sub(a.value.c2, b.value.c2, modulus);
    let res_c3 = sub(a.value.c3, b.value.c3, modulus);
    let res_c4 = sub(a.value.c4, b.value.c4, modulus);
    let res_c5 = sub(a.value.c5, b.value.c5, modulus);
    let res_c6 = sub(a.value.c6, b.value.c6, modulus);
    let res_c7 = sub(a.value.c7, b.value.c7, modulus);
    let res_c8 = sub(a.value.c8, b.value.c8, modulus);
    let res_c9 = sub(a.value.c9, b.value.c9, modulus);
    let res_c10 = sub(a.value.c10, b.value.c10, modulus);
    let res_c11 = sub(a.value.c11, b.value.c11, modulus);

    tempvar res = BNF12(
        new BNF12Struct(
            res_c0,
            res_c1,
            res_c2,
            res_c3,
            res_c4,
            res_c5,
            res_c6,
            res_c7,
            res_c8,
            res_c9,
            res_c10,
            res_c11,
        ),
    );
    return res;
}

// Scalar multiplication of one BNF12 element.
func bnf12_scalar_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: BNF12, x: U384
) -> BNF12 {
    let (__fp__, _) = get_fp_and_pc();
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = mul(a.value.c0, x, modulus);
    let res_c1 = mul(a.value.c1, x, modulus);
    let res_c2 = mul(a.value.c2, x, modulus);
    let res_c3 = mul(a.value.c3, x, modulus);
    let res_c4 = mul(a.value.c4, x, modulus);
    let res_c5 = mul(a.value.c5, x, modulus);
    let res_c6 = mul(a.value.c6, x, modulus);
    let res_c7 = mul(a.value.c7, x, modulus);
    let res_c8 = mul(a.value.c8, x, modulus);
    let res_c9 = mul(a.value.c9, x, modulus);
    let res_c10 = mul(a.value.c10, x, modulus);
    let res_c11 = mul(a.value.c11, x, modulus);

    tempvar res = BNF12(
        new BNF12Struct(
            res_c0,
            res_c1,
            res_c2,
            res_c3,
            res_c4,
            res_c5,
            res_c6,
            res_c7,
            res_c8,
            res_c9,
            res_c10,
            res_c11,
        ),
    );
    return res;
}

// Division of a by b is done by computing the modular inverse of b, verify it exists
// and multiply a by this modular inverse.
func bnf12_div{
    range_check_ptr: felt,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(a: BNF12, b: BNF12) -> BNF12 {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local b_inv: BNF12;

    %{ bnf12_multiplicative_inverse %}
    let res = bnf12_mul(b, b_inv);
    let bnf12_one = BNF12_ONE();
    let is_inv = BNF12__eq__(res, bnf12_one);
    assert is_inv = 1;

    return bnf12_mul(a, b_inv);
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

// Pow function for BNF12 elements using square-and-multiply algorithm
func bnf12_pow{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(base: BNF12, exponent: U384) -> BNF12 {
    alloc_locals;

    // Return 1 for exponent = 0
    let exponent_is_zero = U384_is_zero(exponent);
    if (exponent_is_zero != 0) {
        let one = BNF12_ONE();
        return one;
    }

    // Extract bits from exponent, initialize result with 1
    // and perform square-and-multiply algorithm
    let (bits_ptr, bits_len) = get_u384_bits_little(exponent);
    let res = BNF12_ONE();
    return bnf12_pow_recursive(base, bits_ptr, bits_len, 0, res);
}

func bnf12_pow_recursive{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(base: BNF12, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: BNF12) -> BNF12 {
    alloc_locals;

    // Base case: if we've processed all bits, return the result
    if (current_bit == bits_len) {
        return result;
    }
    // Get current bit value
    let bit_value = bits_ptr[current_bit];
    // Calculate new result and new base for this iteration
    let (new_result, new_base) = bnf12_pow_inner_loop(bit_value, base, result);
    // Continue with next bit
    return bnf12_pow_recursive(new_base, bits_ptr, bits_len, current_bit + 1, new_result);
}

func bnf12_pow_inner_loop{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(bit: felt, base: BNF12, res: BNF12) -> (BNF12, BNF12) {
    alloc_locals;

    // If bit is set, multiply result by base
    if (bit != 0) {
        let new_res = bnf12_mul(res, base);
        tempvar new_res = new_res;
        tempvar range_check_ptr = range_check_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        tempvar new_res = res;
        tempvar range_check_ptr = range_check_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }
    tempvar new_res = new_res;
    // Square the base for next iteration
    let base_squared = bnf12_mul(base, base);
    return (new_res, base_squared);
}

func BNF12__eq__{range_check96_ptr: felt*}(a: BNF12, b: BNF12) -> felt {
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

    return result;
}

// Frobenius endomorphism for BNF12 elements
func bnf12_frobenius{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: BNF12
) -> BNF12 {
    alloc_locals;

    // Get the Frobenius coefficients and initialize the result as zero
    let frob_coeffs = FROBENIUS_COEFFICIENTS();
    let result = BNF12_ZERO();

    // For each coefficient of x, multiply by the corresponding Frobenius coefficient
    // and add to the result
    let frob_coeff_0 = frob_coeffs.value.data[0];
    let term0 = bnf12_scalar_mul(frob_coeff_0, x.value.c0);
    let result = bnf12_add(result, term0);

    let frob_coeff_1 = frob_coeffs.value.data[1];
    let term1 = bnf12_scalar_mul(frob_coeff_1, x.value.c1);
    let result = bnf12_add(result, term1);

    let frob_coeff_2 = frob_coeffs.value.data[2];
    let term2 = bnf12_scalar_mul(frob_coeff_2, x.value.c2);
    let result = bnf12_add(result, term2);

    let frob_coeff_3 = frob_coeffs.value.data[3];
    let term3 = bnf12_scalar_mul(frob_coeff_3, x.value.c3);
    let result = bnf12_add(result, term3);

    let frob_coeff_4 = frob_coeffs.value.data[4];
    let term4 = bnf12_scalar_mul(frob_coeff_4, x.value.c4);
    let result = bnf12_add(result, term4);

    let frob_coeff_5 = frob_coeffs.value.data[5];
    let term5 = bnf12_scalar_mul(frob_coeff_5, x.value.c5);
    let result = bnf12_add(result, term5);

    let frob_coeff_6 = frob_coeffs.value.data[6];
    let term6 = bnf12_scalar_mul(frob_coeff_6, x.value.c6);
    let result = bnf12_add(result, term6);

    let frob_coeff_7 = frob_coeffs.value.data[7];
    let term7 = bnf12_scalar_mul(frob_coeff_7, x.value.c7);
    let result = bnf12_add(result, term7);

    let frob_coeff_8 = frob_coeffs.value.data[8];
    let term8 = bnf12_scalar_mul(frob_coeff_8, x.value.c8);
    let result = bnf12_add(result, term8);

    let frob_coeff_9 = frob_coeffs.value.data[9];
    let term9 = bnf12_scalar_mul(frob_coeff_9, x.value.c9);
    let result = bnf12_add(result, term9);

    let frob_coeff_10 = frob_coeffs.value.data[10];
    let term10 = bnf12_scalar_mul(frob_coeff_10, x.value.c10);
    let result = bnf12_add(result, term10);

    let frob_coeff_11 = frob_coeffs.value.data[11];
    let term11 = bnf12_scalar_mul(frob_coeff_11, x.value.c11);
    let result = bnf12_add(result, term11);

    return result;
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

func BNP__eq__{range_check96_ptr: felt*}(p: BNP, q: BNP) -> felt {
    alloc_locals;
    let is_x_equal = BNF__eq__(p.value.x, q.value.x);
    let is_y_equal = BNF__eq__(p.value.y, q.value.y);
    let result = is_x_equal * is_y_equal;
    return result;
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
) -> BNP {
    tempvar a = U384(new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3));
    tempvar b = U384(new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3));
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    tempvar point = G1Point(new G1PointStruct(x.value.c0, y.value.c0));
    assert_on_curve(point.value, a, b, modulus);

    tempvar res = BNP(new BNPStruct(x, y));
    return res;
}

func bnp_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP
) -> BNP {
    alloc_locals;

    let infinity = bnp_point_at_infinity();
    let p_inf = BNP__eq__(p, infinity);
    if (p_inf != 0) {
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
    if (p_inf != 0) {
        return q;
    }

    let q_inf = BNP__eq__(q, infinity);
    if (q_inf != 0) {
        return p;
    }

    let x_equal = BNF__eq__(p.value.x, q.value.x);
    if (x_equal != 0) {
        let y_equal = BNF__eq__(p.value.y, q.value.y);
        if (y_equal != 0) {
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
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
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
    if (x_is_zero != 0 and y_is_zero != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = bnp_point_at_infinity();

    // Implement the double-and-add algorithm
    return bnp_mul_by_bits(p, bits_ptr, bits_len, 0, result);
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

// alt_bn128 curve defined over BNF12
// BNP12 represents a point on the curve
struct BNP12Struct {
    x: BNF12,
    y: BNF12,
}

struct BNP12 {
    value: BNP12Struct*,
}

// @dev: Coefficient B of the short Weierstrass equation: y^2 = x^3 + Ax + B
// for alt_bn128: A = 0 and B = 3
func BNP12_B() -> BNF12 {
    let (u384_zero) = get_label_location(U384_ZERO);
    tempvar bnf12_three = BNF12(
        new BNF12Struct(
            U384(new UInt384(3, 0, 0, 0)),
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
    return bnf12_three;
}

func bnp12_point_at_infinity() -> BNP12 {
    let bnf12_zero = BNF12_ZERO();
    tempvar res = BNP12(new BNP12Struct(bnf12_zero, bnf12_zero));
    return res;
}

func bnp12_init{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: BNF12, y: BNF12) -> BNP12 {
    alloc_locals;

    let bnf12_zero = BNF12_ZERO();
    let bnf12_b = BNP12_B();

    // Check if the point is at infinity (0,0)
    let x_is_zero = BNF12__eq__(x, bnf12_zero);
    let y_is_zero = BNF12__eq__(y, bnf12_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        tempvar res = BNP12(new BNP12Struct(x, y));
        return res;
    }

    // For non-infinity points, verify the curve equation y² = x³ + B
    // Compute y²
    let y_squared = bnf12_mul(y, y);
    // Compute x³
    let x_squared = bnf12_mul(x, x);
    let x_cubed = bnf12_mul(x_squared, x);
    // Compute right side of equation: x³ + B
    let right_side = bnf12_add(x_cubed, bnf12_b);
    // Check if y² = x³ + B
    let is_on_curve = BNF12__eq__(y_squared, right_side);
    assert is_on_curve = 1;

    tempvar res = BNP12(new BNP12Struct(x, y));
    return res;
}

func BNP12__eq__{range_check96_ptr: felt*}(a: BNP12, b: BNP12) -> felt {
    alloc_locals;
    let x_equal = BNF12__eq__(a.value.x, b.value.x);
    let y_equal = BNF12__eq__(a.value.y, b.value.y);
    return x_equal * y_equal;
}

func bnp12_double{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP12) -> BNP12 {
    alloc_locals;

    // Check if p is the point at infinity
    let bnf12_zero = BNF12_ZERO();
    let is_x_zero = BNF12__eq__(p.value.x, bnf12_zero);
    let is_y_zero = BNF12__eq__(p.value.y, bnf12_zero);
    if (is_x_zero != 0 and is_y_zero != 0) {
        return p;
    }

    // Point doubling formula:
    // λ = (3x^2 + a) / (2y)  [a = 0 for alt_bn128]
    // x' = λ^2 - 2x
    // y' = λ(x - x') - y
    // Calculate 3x^2
    let (u384_zero) = get_label_location(U384_ZERO);
    let uint384_zero = cast(u384_zero, UInt384*);
    tempvar three = BNF12(
        new BNF12Struct(
            U384(new UInt384(3, 0, 0, 0)),
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
    let x_squared = bnf12_mul(p.value.x, p.value.x);
    let three_x_squared = bnf12_mul(three, x_squared);

    // Calculate 2y
    tempvar two = BNF12(
        new BNF12Struct(
            U384(new UInt384(2, 0, 0, 0)),
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
    let two_y = bnf12_mul(two, p.value.y);
    // Calculate λ = 3x^2 / 2y
    let lambda = bnf12_div(three_x_squared, two_y);
    // Calculate λ^2
    let lambda_squared = bnf12_mul(lambda, lambda);
    // Calculate 2x
    let two_x = bnf12_mul(two, p.value.x);
    // Calculate x' = λ^2 - 2x
    let new_x = bnf12_sub(lambda_squared, two_x);
    // Calculate x - x'
    let x_minus_new_x = bnf12_sub(p.value.x, new_x);
    // Calculate λ(x - x')
    let lambda_times_x_diff = bnf12_mul(lambda, x_minus_new_x);
    // Calculate y' = λ(x - x') - y
    let new_y = bnf12_sub(lambda_times_x_diff, p.value.y);
    tempvar result = BNP12(new BNP12Struct(new_x, new_y));
    return result;
}

func bnp12_add{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP12, q: BNP12) -> BNP12 {
    alloc_locals;

    let bnf12_zero = BNF12_ZERO();
    let x_is_zero = BNF12__eq__(p.value.x, bnf12_zero);
    let y_is_zero = BNF12__eq__(p.value.y, bnf12_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        return q;
    }

    let x_is_zero_q = BNF12__eq__(q.value.x, bnf12_zero);
    let y_is_zero_q = BNF12__eq__(q.value.y, bnf12_zero);
    if (x_is_zero_q != 0 and y_is_zero_q != 0) {
        return p;
    }

    let x_equal = BNF12__eq__(p.value.x, q.value.x);
    if (x_equal != 0) {
        let y_equal = BNF12__eq__(p.value.y, q.value.y);
        if (y_equal != 0) {
            return bnp12_double(p);
        }
        let res = bnp12_point_at_infinity();
        return res;
    }

    // Standard case: compute point addition using the formula:
    // λ = (q.y - p.y) / (q.x - p.x)
    // x_r = λ^2 - p.x - q.x
    // y_r = λ(p.x - x_r) - p.y

    // Calculate λ = (q.y - p.y) / (q.x - p.x)
    let y_diff = bnf12_sub(q.value.y, p.value.y);
    let x_diff = bnf12_sub(q.value.x, p.value.x);
    let lambda = bnf12_div(y_diff, x_diff);

    // Calculate x_r = λ^2 - p.x - q.x
    let lambda_squared = bnf12_mul(lambda, lambda);
    let x_sum = bnf12_add(p.value.x, q.value.x);
    let x_r = bnf12_sub(lambda_squared, x_sum);

    // Calculate y_r = λ(p.x - x_r) - p.y
    let x_diff_r = bnf12_sub(p.value.x, x_r);
    let lambda_times_x_diff = bnf12_mul(lambda, x_diff_r);
    let y_r = bnf12_sub(lambda_times_x_diff, p.value.y);

    // Return the new point
    tempvar result = BNP12(new BNP12Struct(x_r, y_r));
    return result;
}

// Implementation of scalar multiplication for BNP12
// Uses the double-and-add algorithm
func bnp12_mul_by{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP12, n: U384) -> BNP12 {
    alloc_locals;
    let n_is_zero = U384_is_zero(n);
    if (n_is_zero != 0) {
        let res = bnp12_point_at_infinity();
        return res;
    }

    let bnf12_zero = BNF12_ZERO();
    let x_is_zero = BNF12__eq__(p.value.x, bnf12_zero);
    let y_is_zero = BNF12__eq__(p.value.y, bnf12_zero);
    if (x_is_zero != 0 and y_is_zero != 0) {
        return p;
    }

    // Extract the bits of n
    let (bits_ptr, bits_len) = get_u384_bits_little(n);

    // Initialize result as the point at infinity
    let result = bnp12_point_at_infinity();

    // Implement the double-and-add algorithm
    return bnp12_mul_by_bits(p, bits_ptr, bits_len, 0, result);
}

func bnp12_mul_by_bits{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP12, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: BNP12) -> BNP12 {
    alloc_locals;

    if (current_bit == bits_len) {
        return result;
    }
    let bit_value = bits_ptr[current_bit];

    // If the bit is 1, add p to the result
    if (bit_value != 0) {
        let new_result = bnp12_add(result, p);
        tempvar new_result = new_result;
        tempvar range_check_ptr = range_check_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        tempvar new_result = result;
        tempvar range_check_ptr = range_check_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }
    let new_result = new_result;

    // Double the point for the next iteration
    let doubled_p = bnp12_double(p);

    return bnp12_mul_by_bits(doubled_p, bits_ptr, bits_len, current_bit + 1, new_result);
}

func bnf12_final_exponentiation{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(p: BNF12) -> BNF12 {
    alloc_locals;

    let p_e12 = E12D(
        w0=[p.value.c0.value],
        w1=[p.value.c1.value],
        w2=[p.value.c2.value],
        w3=[p.value.c3.value],
        w4=[p.value.c4.value],
        w5=[p.value.c5.value],
        w6=[p.value.c6.value],
        w7=[p.value.c7.value],
        w8=[p.value.c8.value],
        w9=[p.value.c9.value],
        w10=[p.value.c10.value],
        w11=[p.value.c11.value],
    );
    let (result) = final_exponentiation(new p_e12);
    tempvar result_bnf12 = BNF12(
        new BNF12Struct(
            U384(new result.w0),
            U384(new result.w1),
            U384(new result.w2),
            U384(new result.w3),
            U384(new result.w4),
            U384(new result.w5),
            U384(new result.w6),
            U384(new result.w7),
            U384(new result.w8),
            U384(new result.w9),
            U384(new result.w10),
            U384(new result.w11),
        ),
    );
    return result_bnf12;
}

func bnp_to_bnp12{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: BNP
) -> BNP12 {
    let x_bnf12 = bnf12_from_int(p.value.x.value.c0);
    let y_bnf12 = bnf12_from_int(p.value.y.value.c0);
    tempvar result = BNP12(new BNP12Struct(x_bnf12, y_bnf12));
    return result;
}

func bnf2_to_bnf12{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: BNF2) -> BNF12 {
    alloc_locals;
    // Convert x[0] to BNF12
    let x0_bnf12 = bnf12_from_int(x.value.c0);

    // Get (BNF12.i_plus_9 - BNF12.from_int(9))
    // This is equivalent to the complex number i in the extension field
    tempvar u384_nine = U384(new UInt384(9, 0, 0, 0));
    let nine = bnf12_from_int(u384_nine);
    let i_plus_9 = BNF12_I_PLUS_9();
    let i_complex = bnf12_sub(i_plus_9, nine);

    // Multiply x[1] by the complex number i
    let x1_bnf12 = bnf12_from_int(x.value.c1);
    let x1_mul_i = bnf12_mul(x1_bnf12, i_complex);

    // Return x[0] + x[1] * i
    let result = bnf12_add(x0_bnf12, x1_mul_i);
    return result;
}

func twist{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p: BNP2) -> BNP12 {
    alloc_locals;

    let x_bnf12 = bnf2_to_bnf12(p.value.x);
    let y_bnf12 = bnf2_to_bnf12(p.value.y);

    let w_pow_2 = BNF12_W_POW_2();
    let w_pow_3 = BNF12_W_POW_3();

    let twisted_x = bnf12_mul(x_bnf12, w_pow_2);
    let twisted_y = bnf12_mul(y_bnf12, w_pow_3);

    tempvar result = BNP12(new BNP12Struct(twisted_x, twisted_y));
    return result;
}

func linefunc{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(p1: BNP12, p2: BNP12, t: BNP12) -> BNF12 {
    alloc_locals;

    // Check if p1.x != p2.x
    let p1_x_equal_p2_x = BNF12__eq__(p1.value.x, p2.value.x);
    if (p1_x_equal_p2_x == 0) {
        // lam = (p2.y - p1.y) / (p2.x - p1.x)
        let p2_y_minus_p1_y = bnf12_sub(p2.value.y, p1.value.y);
        let p2_x_minus_p1_x = bnf12_sub(p2.value.x, p1.value.x);
        let lam = bnf12_div(p2_y_minus_p1_y, p2_x_minus_p1_x);
        // (t.x - p1.x)
        let t_x_minus_p1_x = bnf12_sub(t.value.x, p1.value.x);
        // lam * (t.x - p1.x)
        let lam_mul_tx_p1x = bnf12_mul(lam, t_x_minus_p1_x);
        // (t.y - p1.y)
        let t_y_minus_p1_y = bnf12_sub(t.value.y, p1.value.y);
        // lam * (t.x - p1.x) - (t.y - p1.y)
        let result = bnf12_sub(lam_mul_tx_p1x, t_y_minus_p1_y);
        return result;
    }

    // Check if p1.y == p2.y
    let p1_y_equal_p2_y = BNF12__eq__(p1.value.y, p2.value.y);
    if (p1_y_equal_p2_y != 0) {
        // lam = 3 * p1.x^2 / (2 * p1.y)
        tempvar u384_three = U384(new UInt384(3, 0, 0, 0));
        let three = bnf12_from_int(u384_three);
        let p1_x_squared = bnf12_mul(p1.value.x, p1.value.x);
        let three_mul_p1x2 = bnf12_mul(three, p1_x_squared);
        tempvar u384_two = U384(new UInt384(2, 0, 0, 0));
        let two = bnf12_from_int(u384_two);
        let two_mul_p1y = bnf12_mul(two, p1.value.y);
        let lam = bnf12_div(three_mul_p1x2, two_mul_p1y);

        // (t.x - p1.x)
        let t_x_minus_p1_x = bnf12_sub(t.value.x, p1.value.x);
        // lam * (t.x - p1.x)
        let lam_mul_tx_p1x = bnf12_mul(lam, t_x_minus_p1_x);
        // (t.y - p1.y)
        let t_y_minus_p1_y = bnf12_sub(t.value.y, p1.value.y);
        // lam * (t.x - p1.x) - (t.y - p1.y)
        let result = bnf12_sub(lam_mul_tx_p1x, t_y_minus_p1_y);
        return result;
    }
    // Third case: p1.x == p2.x but p1.y != p2.y
    // t.x - p1.x
    let result = bnf12_sub(t.value.x, p1.value.x);
    return result;
}

func miller_loop{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(q: BNP12, p: BNP12) -> BNF12 {
    alloc_locals;

    let point_at_infinity = bnp12_point_at_infinity();
    let is_p_point_at_infinity = BNP12__eq__(p, point_at_infinity);
    if (is_p_point_at_infinity != 0) {
        let bnf12_one = BNF12_ONE();
        return bnf12_one;
    }

    let is_q_point_at_infinity = BNP12__eq__(q, point_at_infinity);
    if (is_q_point_at_infinity != 0) {
        let bnf12_one = BNF12_ONE();
        return bnf12_one;
    }

    // Initialize the results.
    let r = q;
    let f = BNF12_ONE();

    // Get bits of ATE_PAIRING_COUNT - 1
    tempvar ate_minus_one = U384(new UInt384(29793968203157093288, 0, 0, 0));
    let ate_pairing_count_bits = 63;
    let (bits_ptr, bits_len) = get_u384_bits_little(ate_minus_one);
    assert bits_len = 65;

    // Call recursive helper for the main loop
    let (f, r) = miller_loop_inner(f, r, q, p, bits_ptr, ate_pairing_count_bits);

    // q1 = BNP12(q.x.frobenius(), q.y.frobenius())
    let q_x_frob = bnf12_frobenius(q.value.x);
    let q_y_frob = bnf12_frobenius(q.value.y);
    tempvar q1 = BNP12(new BNP12Struct(q_x_frob, q_y_frob));

    // f = f * linefunc(r, q1, p)
    let line_r_q1_p = linefunc(r, q1, p);
    let f = bnf12_mul(f, line_r_q1_p);
    // r = r + q1
    let r = bnp12_add(r, q1);

    // nq2 = BNP12(q1.x.frobenius(), -q1.y.frobenius())
    let bnf12_zero = BNF12_ZERO();
    let q1_x_frob = bnf12_frobenius(q1.value.x);
    let q1_y_frob = bnf12_frobenius(q1.value.y);
    let neg_q1_y_frob = bnf12_sub(bnf12_zero, q1_y_frob);
    tempvar nq2 = BNP12(new BNP12Struct(q1_x_frob, neg_q1_y_frob));
    // f = f * linefunc(r, nq2, p)
    let line_r_nq2_p = linefunc(r, nq2, p);
    let f = bnf12_mul(f, line_r_nq2_p);

    let res = bnf12_final_exponentiation(f);

    return res;
}

func miller_loop_inner{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(f: BNF12, r: BNP12, q: BNP12, p: BNP12, bits_ptr: felt*, current_bit: felt) -> (BNF12, BNP12) {
    alloc_locals;

    // Base case: we've processed all bits
    if (current_bit == -1) {
        return (f, r);
    }

    // f = f * f linefunc(r, r, p);
    let f_squared = bnf12_mul(f, f);
    let line_p = linefunc(r, r, p);
    let f_2_line_p = bnf12_mul(f_squared, line_p);
    // r = r.double()
    let r_double = bnp12_double(r);

    // Check if current bit is set
    let bit = bits_ptr[current_bit];
    if (bit != 0) {
        // f = f * linefunc(r, q, p)
        let line_q = linefunc(r_double, q, p);
        let f_2_line_p_q = bnf12_mul(f_2_line_p, line_q);
        // r = r + q
        let r_2_q = bnp12_add(r_double, q);
        return miller_loop_inner(f_2_line_p_q, r_2_q, q, p, bits_ptr, current_bit - 1);
    }

    return miller_loop_inner(f_2_line_p, r_double, q, p, bits_ptr, current_bit - 1);
}

func pairing{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(q: BNP2, p: BNP) -> BNF12 {
    // return miller_loop(twist(q), bnp_to_bnp12(p))
    let q_twist = twist(q);
    let p_bnp12 = bnp_to_bnp12(p);

    let res = miller_loop(q_twist, p_bnp12);
    return res;
}
