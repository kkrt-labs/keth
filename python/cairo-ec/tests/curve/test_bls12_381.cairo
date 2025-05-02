from starkware.cairo.common.cairo_builtins import UInt384
from starkware.cairo.common.uint256 import Uint256

from cairo_ec.curve.bls12_381 import bls12_381, sign_to_uint384_mod_bls12_381
from cairo_core.numeric import U384, U256

func test__get_CURVE_ID() -> felt {
    return bls12_381.CURVE_ID;
}

func test__get_P() -> U384 {
    tempvar p = U384(new UInt384(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));
    return p;
}

func test__get_N() -> U384 {
    tempvar n = U384(new UInt384(bls12_381.N0, bls12_381.N1, bls12_381.N2, bls12_381.N3));
    return n;
}

func test__get_N_256() -> U256 {
    tempvar n = U256(new Uint256(bls12_381.N_LOW_128, bls12_381.N_HIGH_128));
    return n;
}

func test__get_A() -> U384 {
    tempvar a = U384(new UInt384(bls12_381.A0, bls12_381.A1, bls12_381.A2, bls12_381.A3));
    return a;
}

func test__get_B() -> U384 {
    tempvar b = U384(new UInt384(bls12_381.B0, bls12_381.B1, bls12_381.B2, bls12_381.B3));
    return b;
}

func test__get_G() -> U384 {
    tempvar g = U384(new UInt384(bls12_381.G0, bls12_381.G1, bls12_381.G2, bls12_381.G3));
    return g;
}

func test__get_P_MIN_ONE() -> U384 {
    tempvar p_min_one = U384(
        new UInt384(
            bls12_381.P_MIN_ONE_D0,
            bls12_381.P_MIN_ONE_D1,
            bls12_381.P_MIN_ONE_D2,
            bls12_381.P_MIN_ONE_D3,
        ),
    );
    return p_min_one;
}

func test__sign_to_uint384_mod_bls12_381(sign: felt) -> U384 {
    alloc_locals;
    let res_ = sign_to_uint384_mod_bls12_381(sign);
    tempvar res = U384(new res_);
    return res;
}
