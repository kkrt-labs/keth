from starkware.cairo.common.cairo_builtins import UInt384
from starkware.cairo.common.uint256 import Uint256

from cairo_ec.curve.secp256k1 import get_generator_point, secp256k1

func test__get_P() -> UInt384* {
    tempvar p_ptr = new UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
    return p_ptr;
}

func test__get_P_256() -> Uint256* {
    tempvar p_ptr = new Uint256(secp256k1.P_LOW_128, secp256k1.P_HIGH_128);
    return p_ptr;
}

func test__get_N() -> UInt384* {
    tempvar n_ptr = new UInt384(secp256k1.N0, secp256k1.N1, secp256k1.N2, secp256k1.N3);
    return n_ptr;
}

func test__get_N_256() -> Uint256* {
    tempvar n_ptr = new Uint256(secp256k1.N_LOW_128, secp256k1.N_HIGH_128);
    return n_ptr;
}

func test__get_A() -> UInt384* {
    tempvar a_ptr = new UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);
    return a_ptr;
}

func test__get_B() -> UInt384* {
    tempvar b_ptr = new UInt384(secp256k1.B0, secp256k1.B1, secp256k1.B2, secp256k1.B3);
    return b_ptr;
}

func test__get_G() -> UInt384* {
    tempvar g_ptr = new UInt384(secp256k1.G0, secp256k1.G1, secp256k1.G2, secp256k1.G3);
    return g_ptr;
}

func test__get_P_MIN_ONE() -> UInt384* {
    tempvar p_min_one_ptr = new UInt384(
        secp256k1.P_MIN_ONE_D0,
        secp256k1.P_MIN_ONE_D1,
        secp256k1.P_MIN_ONE_D2,
        secp256k1.P_MIN_ONE_D3,
    );
    return p_min_one_ptr;
}

func test__get_generator_point() {
    let generator = get_generator_point();

    assert generator.value.x.value.d0 = 0x2dce28d959f2815b16f81798;
    assert generator.value.x.value.d1 = 0x55a06295ce870b07029bfcdb;
    assert generator.value.x.value.d2 = 0x79be667ef9dcbbac;
    assert generator.value.x.value.d3 = 0x0;
    assert generator.value.y.value.d0 = 0xa68554199c47d08ffb10d4b8;
    assert generator.value.y.value.d1 = 0x5da4fbfc0e1108a8fd17b448;
    assert generator.value.y.value.d2 = 0x483ada7726a3c465;
    assert generator.value.y.value.d3 = 0x0;

    return ();
}
