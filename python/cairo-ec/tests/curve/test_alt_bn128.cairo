from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384
from starkware.cairo.common.uint256 import Uint256

from cairo_ec.curve.alt_bn128 import alt_bn128, sign_to_uint384_mod_alt_bn128
from cairo_ec.curve.ids import CurveID
from cairo_core.numeric import U384, U256

func test__get_CURVE_ID() -> felt {
    return alt_bn128.CURVE_ID;
}

func test__get_P() -> U384 {
    tempvar p = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    return p;
}

func test__get_P_256() -> U256 {
    tempvar p = U256(new Uint256(alt_bn128.P_LOW_128, alt_bn128.P_HIGH_128));
    return p;
}

func test__get_N() -> U384 {
    tempvar n = U384(new UInt384(alt_bn128.N0, alt_bn128.N1, alt_bn128.N2, alt_bn128.N3));
    return n;
}

func test__get_N_256() -> U256 {
    tempvar n = U256(new Uint256(alt_bn128.N_LOW_128, alt_bn128.N_HIGH_128));
    return n;
}

func test__get_A() -> U384 {
    tempvar a = U384(new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3));
    return a;
}

func test__get_B() -> U384 {
    tempvar b = U384(new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3));
    return b;
}

func test__get_G() -> U384 {
    tempvar g = U384(new UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3));
    return g;
}

func test__get_P_MIN_ONE() -> U384 {
    tempvar p_min_one = U384(
        new UInt384(
            alt_bn128.P_MIN_ONE_D0,
            alt_bn128.P_MIN_ONE_D1,
            alt_bn128.P_MIN_ONE_D2,
            alt_bn128.P_MIN_ONE_D3,
        ),
    );
    return p_min_one;
}

func test__sign_to_uint384_mod_alt_bn128(sign: felt) -> U384 {
    alloc_locals;
    let res_ = sign_to_uint384_mod_alt_bn128(sign);
    tempvar res = U384(new res_);
    return res;
}
