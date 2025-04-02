from cairo_ec.curve.ids import CurveID
from starkware.cairo.common.cairo_builtins import UInt384

namespace bls12_381 {
    const CURVE_ID = CurveID.BLS12_381;
    const P0 = 0xb153ffffb9feffffffffaaab;
    const P1 = 0x6730d2a0f6b0f6241eabfffe;
    const P2 = 0x434bacd764774b84f38512bf;
    const P3 = 0x1a0111ea397fe69a4b1ba7b6;
    const N0 = 0xfffe5bfeffffffff00000001;
    const N1 = 0x3339d80809a1d80553bda402;
    const N2 = 0x73eda753299d7d48;
    const N3 = 0x0;
    const N_LOW_128 = 0x53bda402fffe5bfeffffffff00000001;
    const N_HIGH_128 = 0x73eda753299d7d483339d80809a1d805;
    const A0 = 0x0;
    const A1 = 0x0;
    const A2 = 0x0;
    const A3 = 0x0;
    const B0 = 0x4;
    const B1 = 0x0;
    const B2 = 0x0;
    const B3 = 0x0;
    const G0 = 0x3;
    const G1 = 0x0;
    const G2 = 0x0;
    const G3 = 0x0;
    const P_MIN_ONE_D0 = 0xb153ffffb9feffffffffaaaa;
    const P_MIN_ONE_D1 = 0x6730d2a0f6b0f6241eabfffe;
    const P_MIN_ONE_D2 = 0x434bacd764774b84f38512bf;
    const P_MIN_ONE_D3 = 0x1a0111ea397fe69a4b1ba7b6;
}

@known_ap_change
func sign_to_uint384_mod_bls12_381(sign: felt) -> UInt384 {
    if (sign == -1) {
        let res = UInt384(
            bls12_381.P_MIN_ONE_D0,
            bls12_381.P_MIN_ONE_D1,
            bls12_381.P_MIN_ONE_D2,
            bls12_381.P_MIN_ONE_D3,
        );
        return res;
    } else {
        let res = UInt384(1, 0, 0, 0);
        return res;
    }
}
