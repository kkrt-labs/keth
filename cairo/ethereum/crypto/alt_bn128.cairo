from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
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

from ethereum.utils.numeric import divmod, U384_ZERO
from ethereum_types.numeric import U384

// Field over which the alt_bn128 curve is defined.
// BNF elements are 1-dimensional.
struct BNFStruct {
    c0: U384,
}

struct BNF {
    value: BNFStruct*,
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

func BNF2_ZERO() -> BNF2 {
    let (u384_zero) = get_label_location(U384_ZERO);
    let u384_zero_ptr = cast(u384_zero, UInt384*);
    tempvar res = BNF2(new BNF2Struct(U384(u384_zero_ptr), U384(u384_zero_ptr)));
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

func bnp2_point_at_infinity() -> BNP2 {
    let bnf2_zero = BNF2_ZERO();
    tempvar res = BNP2(new BNP2Struct(bnf2_zero, bnf2_zero));
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

// alt_bn128 curve defined over BNF (Fp)
// BNP represents a point on the curve.
struct BNPStruct {
    x: BNF,
    y: BNF,
}

struct BNP {
    value: BNPStruct*,
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

// alt_bn128 curve defined over BNF12
// BNP12 represents a point on the curve
struct BNP12Struct {
    x: BNF12,
    y: BNF12,
}

struct BNP12 {
    value: BNP12Struct*,
}

// @dev: Coefficient A of the short Weierstrass equation: y^2 = x^3 + Ax + B
// for alt_bn128: A = 0 and B = 3
func A() -> BNF12 {
    let bnf12_zero = BNF12_ZERO();
    return bnf12_zero;
}

// @dev: Coefficient B of the short Weierstrass equation: y^2 = x^3 + Ax + B
// for alt_bn128: A = 0 and B = 3
func B() -> BNF12 {
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
