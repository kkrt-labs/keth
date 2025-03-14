from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256
// BNF12 represents a field element in the BNF12 extension field
// This is a 12-degree extension of the base field used in alt_bn128 curve
struct BNF12Struct {
    c0: Uint256,
    c1: Uint256,
    c2: Uint256,
    c3: Uint256,
    c4: Uint256,
    c5: Uint256,
    c6: Uint256,
    c7: Uint256,
    c8: Uint256,
    c9: Uint256,
    c10: Uint256,
    c11: Uint256,
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
            Uint256(1, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_1 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(
                139017943656065613208990680545363384661, 39277407118905477095443604299549150701
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                154821686135121967470747438406652093100, 48400460688297795386460604898710195086
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_2 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                102947392277037628951602483558423536039, 48077779964942055770146595382641348228
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(67365713605005907059226285224129186722, 30291318616190852738686922041744557972),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_3 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                293973771696641353171912708688340112877, 44214624315707654686224703789820068336
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(44531689129308439574035516107637633251, 10302748860113893395241959476386426667),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_4 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(79814584767821372187330971767968367755, 59175221529237036200933234859602622635),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(72473165108602802788256482782704533798, 58591801720974880430714466712276376722),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_5 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                143363362313774665320464135954200645544, 35891479857830394078472720561571300863
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                234612870739144882900862630107452025931, 24824103367834507545473008290225102717
            ),
        ),
    );
    tempvar frob_coeff_6 = BNF12(
        new BNF12Struct(
            Uint256(18, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                201385395114098847380338600778089168198, 64323764613183177041862057485226039389
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_7 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(17388066832188432051993728276056024858, 44520052431529062393686340149845873664),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(62367451458033234171347920232725783538, 25046357494277699946418453185676888688),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_8 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(307824699873406270841538926287262328118, 4452406011081722258139335078843973570),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(98438002837061218428736117219665632160, 16245984648241121271715462102584691161),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_9 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                165385485160042119559755376014728427377, 32594528882497616715333908149797232028
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                247693990338395957671800499521517266778, 20109140297475522355637353695405971052
            ),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_10 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                282709217734188710689538454447439062965, 16219148846537736125937266723940514202
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(121570810346277475193007629010120800444, 5148543083946140840928822625623416754),
            Uint256(0, 0),
        ),
    );
    tempvar frob_coeff_11 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(
                290982412663171555973597794246061603191, 44348764462866453424951293012474223418
            ),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(58022032800324182059874464823888522655, 28432284755352782963389336923654738526),
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
            Uint256(0, 0),
            Uint256(1, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    return bnf12_w;
}

// BNF12_W_POW_2 returns the value of w^2
func BNF12_W_POW_2() -> BNF12 {
    tempvar bnf12_w_pow_2 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(1, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    return bnf12_w_pow_2;
}

// BNF12_W_POW_3 returns the value of w^3
func BNF12_W_POW_3() -> BNF12 {
    tempvar bnf12_w_pow_3 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(1, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    return bnf12_w_pow_3;
}

// BNF12_I_PLUS_9 returns the value of i + 9, which is w^6 in the field
// This corresponds to BNF12.w**6
func BNF12_I_PLUS_9() -> BNF12 {
    tempvar BNF12_I_PLUS_9 = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(1, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    return BNF12_I_PLUS_9;
}

func BNF12_ZERO() -> BNF12 {
    tempvar bnf12_zero = BNF12(
        new BNF12Struct(
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
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

func A() -> BNF12 {
    let bnf12_zero = BNF12_ZERO();
    return bnf12_zero;
}

func B() -> BNF12 {
    tempvar bnf12_three = BNF12(
        new BNF12Struct(
            Uint256(3, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
            Uint256(0, 0),
        ),
    );
    return bnf12_three;
}
