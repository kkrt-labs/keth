from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.registers import get_label_location

from cairo_core.control_flow import raise
from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.alt_bn128 import alt_bn128

from ethereum.utils.numeric import divmod, U384_ZERO
from ethereum_types.numeric import U384
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

// Addition between two BNF12 elements.
func bnf12_add{
    range_check_ptr: felt,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(a: BNF12, b: BNF12) -> BNF12 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = add(a.value.c0.value, b.value.c0.value, modulus.value);
    let res_c1 = add(a.value.c1.value, b.value.c1.value, modulus.value);
    let res_c2 = add(a.value.c2.value, b.value.c2.value, modulus.value);
    let res_c3 = add(a.value.c3.value, b.value.c3.value, modulus.value);
    let res_c4 = add(a.value.c4.value, b.value.c4.value, modulus.value);
    let res_c5 = add(a.value.c5.value, b.value.c5.value, modulus.value);
    let res_c6 = add(a.value.c6.value, b.value.c6.value, modulus.value);
    let res_c7 = add(a.value.c7.value, b.value.c7.value, modulus.value);
    let res_c8 = add(a.value.c8.value, b.value.c8.value, modulus.value);
    let res_c9 = add(a.value.c9.value, b.value.c9.value, modulus.value);
    let res_c10 = add(a.value.c10.value, b.value.c10.value, modulus.value);
    let res_c11 = add(a.value.c11.value, b.value.c11.value, modulus.value);

    tempvar res = BNF12(
        new BNF12Struct(
            U384(res_c0),
            U384(res_c1),
            U384(res_c2),
            U384(res_c3),
            U384(res_c4),
            U384(res_c5),
            U384(res_c6),
            U384(res_c7),
            U384(res_c8),
            U384(res_c9),
            U384(res_c10),
            U384(res_c11),
        ),
    );
    return res;
}

// Subtraction between two BNF12 elements.
func bnf12_sub{
    range_check_ptr: felt,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(a: BNF12, b: BNF12) -> BNF12 {
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = sub(a.value.c0.value, b.value.c0.value, modulus.value);
    let res_c1 = sub(a.value.c1.value, b.value.c1.value, modulus.value);
    let res_c2 = sub(a.value.c2.value, b.value.c2.value, modulus.value);
    let res_c3 = sub(a.value.c3.value, b.value.c3.value, modulus.value);
    let res_c4 = sub(a.value.c4.value, b.value.c4.value, modulus.value);
    let res_c5 = sub(a.value.c5.value, b.value.c5.value, modulus.value);
    let res_c6 = sub(a.value.c6.value, b.value.c6.value, modulus.value);
    let res_c7 = sub(a.value.c7.value, b.value.c7.value, modulus.value);
    let res_c8 = sub(a.value.c8.value, b.value.c8.value, modulus.value);
    let res_c9 = sub(a.value.c9.value, b.value.c9.value, modulus.value);
    let res_c10 = sub(a.value.c10.value, b.value.c10.value, modulus.value);
    let res_c11 = sub(a.value.c11.value, b.value.c11.value, modulus.value);

    tempvar res = BNF12(
        new BNF12Struct(
            U384(res_c0),
            U384(res_c1),
            U384(res_c2),
            U384(res_c3),
            U384(res_c4),
            U384(res_c5),
            U384(res_c6),
            U384(res_c7),
            U384(res_c8),
            U384(res_c9),
            U384(res_c10),
            U384(res_c11),
        ),
    );
    return res;
}

// Scalar multiplication of one BNF12 element.
func bnf12_scalar_mul{
    range_check_ptr: felt,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(a: BNF12, x: U384) -> BNF12 {
    let (__fp__, _) = get_fp_and_pc();
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));

    let res_c0 = mul(a.value.c0.value, x.value, modulus.value);
    let res_c1 = mul(a.value.c1.value, x.value, modulus.value);
    let res_c2 = mul(a.value.c2.value, x.value, modulus.value);
    let res_c3 = mul(a.value.c3.value, x.value, modulus.value);
    let res_c4 = mul(a.value.c4.value, x.value, modulus.value);
    let res_c5 = mul(a.value.c5.value, x.value, modulus.value);
    let res_c6 = mul(a.value.c6.value, x.value, modulus.value);
    let res_c7 = mul(a.value.c7.value, x.value, modulus.value);
    let res_c8 = mul(a.value.c8.value, x.value, modulus.value);
    let res_c9 = mul(a.value.c9.value, x.value, modulus.value);
    let res_c10 = mul(a.value.c10.value, x.value, modulus.value);
    let res_c11 = mul(a.value.c11.value, x.value, modulus.value);

    tempvar res = BNF12(
        new BNF12Struct(
            U384(res_c0),
            U384(res_c1),
            U384(res_c2),
            U384(res_c3),
            U384(res_c4),
            U384(res_c5),
            U384(res_c6),
            U384(res_c7),
            U384(res_c8),
            U384(res_c9),
            U384(res_c10),
            U384(res_c11),
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

    tempvar modulus = new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3);

    // Step 1: Create a dictionary for polynomial multiplication intermediate value and result
    let (mul_dict) = default_dict_new(0);
    let mul_dict_start = mul_dict;

    // Step 2: Perform polynomial multiplication
    // Compute each product a[i] * b[j] and add it to the appropriate position
    compute_polynomial_product{dict_ptr=mul_dict}(a, b, modulus, 0, 0);

    // Step 3: Apply reduction for coefficients 22 down to 12 (in descending order like Python)
    reduce_polynomial{mul_dict=mul_dict}(modulus);

    // Step 4: Create the result BNF12 element from the reduced coefficients
    let bnf12_result = create_bnf12_from_dict{mul_dict=mul_dict}();

    // Step 5: Finalize the dictionary
    default_dict_finalize(mul_dict_start, mul_dict, 0);

    return bnf12_result;
}

func compute_polynomial_product{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    dict_ptr: DictAccess*,
}(a: BNF12, b: BNF12, modulus: UInt384*, i: felt, j: felt) {
    alloc_locals;

    // Base case: we've processed all terms
    if (i == 12) {
        return ();
    }
    // If we've processed all j for current i, move to next i
    if (j == 12) {
        return compute_polynomial_product(a, b, modulus, i + 1, 0);
    }

    // Get coefficients as UInt384
    let a_coeff = _get_bnf12_coeff(a, i);
    let b_coeff = _get_bnf12_coeff(b, j);

    // Compute product using modular multiplication
    let product = mul(new a_coeff, new b_coeff, modulus);

    // Position in result
    let pos = i + j;

    // Read current value at this position (default to zero if not present)
    let (current_ptr) = dict_read{dict_ptr=dict_ptr}(pos);
    let current = cast(current_ptr, UInt384*);

    // If current is null, use zero
    tempvar zero = new UInt384(0, 0, 0, 0);
    if (current == 0) {
        tempvar current_value = zero;
    } else {
        tempvar current_value = current;
    }

    // Add product to current value using modular addition
    let new_value = add(current_value, product, modulus);

    // Write the new value to the dictionary
    dict_write{dict_ptr=dict_ptr}(pos, cast(new_value, felt));

    // Continue with next term
    return compute_polynomial_product(a, b, modulus, i, j + 1);
}

func _get_bnf12_coeff(a: BNF12, i: felt) -> UInt384 {
    if (i == 0) {
        return a.value.c0;
    }
    if (i == 1) {
        return a.value.c1;
    }
    if (i == 2) {
        return a.value.c2;
    }
    if (i == 3) {
        return a.value.c3;
    }
    if (i == 4) {
        return a.value.c4;
    }
    if (i == 5) {
        return a.value.c5;
    }
    if (i == 6) {
        return a.value.c6;
    }
    if (i == 7) {
        return a.value.c7;
    }
    if (i == 8) {
        return a.value.c8;
    }
    if (i == 9) {
        return a.value.c9;
    }
    if (i == 10) {
        return a.value.c10;
    }
    if (i == 11) {
        return a.value.c11;
    }

    // Should never reach here
    raise('AssertionError');
    tempvar zero = UInt384(0, 0, 0, 0);
    return zero;
}

// Apply reductions in descending order (from 22 down to 12)
func reduce_polynomial{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    mul_dict: DictAccess*,
}(modulus: UInt384*) {
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
}(modulus: UInt384*, idx: felt) {
    alloc_locals;

    // Get the coefficient
    let (coeff_i_ptr) = dict_read{dict_ptr=mul_dict}(idx);
    let coeff_i = cast(coeff_i_ptr, UInt384*);

    // Constants for reduction
    tempvar modulus_coeff_0 = new UInt384(82, 0, 0, 0);
    tempvar modulus_coeff_6 = new UInt384(18, 0, 0, 0);

    // Compute mul[i] * 18
    let intermediate_mul = mul(coeff_i, modulus_coeff_6, modulus);
    // Update position idx - 6
    let pos1 = idx - 6;
    let (current1_ptr) = dict_read{dict_ptr=mul_dict}(pos1);
    // If current value is not present, use zero
    tempvar zero = new UInt384(0, 0, 0, 0);
    if (current1_ptr == 0) {
        tempvar current1 = zero;
    } else {
        tempvar current1 = cast(current1_ptr, UInt384*);
    }
    // Add intermediate_mul to current value
    let new_value1 = add(current1, intermediate_mul, modulus);
    // Write the new value to the dictionary
    dict_write{dict_ptr=mul_dict}(pos1, cast(new_value1, felt));

    // Compute mul[i] * 82
    let intermediate_mul = mul(coeff_i, modulus_coeff_0, modulus);
    // Update position idx - 12
    let pos2 = idx - 12;
    let (current2_ptr) = dict_read{dict_ptr=mul_dict}(pos2);
    // If current value is not present, use zero
    if (current2_ptr == 0) {
        tempvar current2 = zero;
    } else {
        tempvar current2 = cast(current2_ptr, UInt384*);
    }
    // Subtract intermediate_mul from current value
    let new_value2 = sub(current2, intermediate_mul, modulus);
    // Write the new value to the dictionary
    dict_write{dict_ptr=mul_dict}(pos2, cast(new_value2, felt));

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

    tempvar zero = new UInt384(0, 0, 0, 0);
    let coeff_ptr = cast(c0_ptr, UInt384*);
    let c0 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c0 = c0;

    let coeff_ptr = cast(c1_ptr, UInt384*);
    let c1 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c1 = c1;

    let coeff_ptr = cast(c2_ptr, UInt384*);
    let c2 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c2 = c2;

    let coeff_ptr = cast(c3_ptr, UInt384*);
    let c3 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c3 = c3;

    let coeff_ptr = cast(c4_ptr, UInt384*);
    let c4 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c4 = c4;

    let coeff_ptr = cast(c5_ptr, UInt384*);
    let c5 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c5 = c5;

    let coeff_ptr = cast(c6_ptr, UInt384*);
    let c6 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c6 = c6;

    let coeff_ptr = cast(c7_ptr, UInt384*);
    let c7 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c7 = c7;

    let coeff_ptr = cast(c8_ptr, UInt384*);
    let c8 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c8 = c8;

    let coeff_ptr = cast(c9_ptr, UInt384*);
    let c9 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c9 = c9;

    let coeff_ptr = cast(c10_ptr, UInt384*);
    let c10 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c10 = c10;

    let coeff_ptr = cast(c11_ptr, UInt384*);
    let c11 = _process_coefficient(coeff_ptr, zero);
    assert result_struct.c11 = c11;

    tempvar bnf12_result = BNF12(result_struct);
    return bnf12_result;
}

func _process_coefficient(coeff_ptr: UInt384*, zero: UInt384*) -> UInt384 {
    if (coeff_ptr == 0) {
        tempvar coeff = [zero];
    } else {
        let coeff = [cast(coeff_ptr, UInt384*)];
        tempvar coeff = coeff;
    }
    return coeff;
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
