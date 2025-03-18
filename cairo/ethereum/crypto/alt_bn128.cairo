from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384
// BNF12 represents a field element in the BNF12 extension field
// This is a 12-degree extension of the base field used in alt_bn128 curve
struct BNF12Struct {
    c0: UInt384,
    c1: UInt384,
    c2: UInt384,
    c3: UInt384,
    c4: UInt384,
    c5: UInt384,
    c6: UInt384,
    c7: UInt384,
    c8: UInt384,
    c9: UInt384,
    c10: UInt384,
    c11: UInt384,
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

    tempvar frob_coeff_0 = BNF12(
        new BNF12Struct(
            UInt384(1, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_1 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(
                78578536060309107515104581973, 8400990441217749534645805517, 2129232506395746792, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                44235539729515559427878642348, 51435548181543843798942585463, 2623794231377586150, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_2 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                78349051542967260616978669991, 41008965243346889244325114448, 2606301674313511803, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                3554987122848029851499088802, 23410605513395334791406955037, 1642095672556236320, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_3 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                34033322189376251481554474477, 4280726608038811945455405562, 2396879586936032454, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                44452636005823129879501320419, 2172088618007306609220419017, 558513134835401882, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_4 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                34584991903128600703749850251, 30551585780948950581852748505, 3207895186965489429, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                8625418388212319703725211942, 49278841972922804394128691946, 3176267935786044142, 0
            ),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_5 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                25824796045544905201978036136, 6187323640648889100853233532, 1945681021778971854, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                32048825361800970863735745611, 50290947057026719718192499609, 1345717340070545013, 0
            ),
        ),
    );
    tempvar frob_coeff_6 = BNF12(
        new BNF12Struct(
            UInt384(18, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                32324006162389411176778628422, 57042285082623239461879769745, 3486998266802970665, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_7 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(
                20641937728814725449375590170, 24203765336848429100941234658, 2413436878271618679, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                32973632616344641255217996786, 48641294641405489927233964227, 1357765760407223873, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_8 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                20943551402699757736052663606, 8544852239310357649650147702, 241365413500116110, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                33203117133686488153343908768, 16033319839276350217554655296, 880696592489458862, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_9 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                42804809713167380845233239921, 17529656269681834330436670968, 1766952951277271856, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                77518846487277497288768104282, 52761558474584427516424364182, 1090118679866938211, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_10 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                52121014111839700750532454325, 33770943432150980509194768534, 879241820764098843, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                76967176773525148066572728508, 26490699301674288880027021239, 279103079837481236, 0
            ),
            UInt384(0, 0, 0, 0),
        ),
    );
    tempvar frob_coeff_11 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                24546180515706619156045117815, 74248057992238438118561754263, 2404151338884387196, 0
            ),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(
                6499210116844505974800592287, 50854961441974350361026536213, 1541317245023998811, 0
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
    tempvar bnf12_w = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(1, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    return bnf12_w;
}

// BNF12_W_POW_2 returns the value of w^2
func BNF12_W_POW_2() -> BNF12 {
    tempvar bnf12_w_pow_2 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(1, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    return bnf12_w_pow_2;
}

// BNF12_W_POW_3 returns the value of w^3
func BNF12_W_POW_3() -> BNF12 {
    tempvar bnf12_w_pow_3 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(1, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    return bnf12_w_pow_3;
}

// BNF12_I_PLUS_9 returns the value of i + 9, which is w^6 in the field
// This corresponds to BNF12.w**6
func BNF12_I_PLUS_9() -> BNF12 {
    tempvar BNF12_I_PLUS_9 = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(1, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    return BNF12_I_PLUS_9;
}

func BNF12_ZERO() -> BNF12 {
    tempvar bnf12_zero = BNF12(
        new BNF12Struct(
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    return bnf12_zero;
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
    tempvar bnf12_three = BNF12(
        new BNF12Struct(
            UInt384(3, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
            UInt384(0, 0, 0, 0),
        ),
    );
    return bnf12_three;
}
