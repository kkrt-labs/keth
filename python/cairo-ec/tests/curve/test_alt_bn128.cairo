from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import UInt384
from starkware.cairo.common.uint256 import Uint256

from cairo_ec.curve.alt_bn128 import alt_bn128, sign_to_uint384_mod_alt_bn128

func test__get_P() -> UInt384* {
    tempvar p_ptr = new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3);
    return p_ptr;
}

func test__get_P_256() -> Uint256* {
    tempvar p_ptr = new Uint256(alt_bn128.P_LOW_128, alt_bn128.P_HIGH_128);
    return p_ptr;
}

func test__get_N() -> UInt384* {
    tempvar n_ptr = new UInt384(alt_bn128.N0, alt_bn128.N1, alt_bn128.N2, alt_bn128.N3);
    return n_ptr;
}

func test__get_N_256() -> Uint256* {
    tempvar n_ptr = new Uint256(alt_bn128.N_LOW_128, alt_bn128.N_HIGH_128);
    return n_ptr;
}

func test__get_A() -> UInt384* {
    tempvar a_ptr = new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3);
    return a_ptr;
}

func test__get_B() -> UInt384* {
    tempvar b_ptr = new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3);
    return b_ptr;
}

func test__get_G() -> UInt384* {
    tempvar g_ptr = new UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3);
    return g_ptr;
}

func test__get_P_MIN_ONE() -> UInt384* {
    tempvar p_min_one_ptr = new UInt384(
        alt_bn128.P_MIN_ONE_D0,
        alt_bn128.P_MIN_ONE_D1,
        alt_bn128.P_MIN_ONE_D2,
        alt_bn128.P_MIN_ONE_D3,
    );
    return p_min_one_ptr;
}

func test__sign_to_uint384_mod_alt_bn128() -> UInt384* {
    alloc_locals;
    tempvar sign;
    %{ ids.sign = program_input["sign"] %}
    let res = sign_to_uint384_mod_alt_bn128(sign);
    tempvar res_ptr = new res;

    return res_ptr;
}
