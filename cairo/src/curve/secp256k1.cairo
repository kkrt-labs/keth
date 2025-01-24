from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, PoseidonBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.modulo import run_mod_p_circuit

from src.curve.g1_point import G1Point
from src.curve.ids import CurveID
from src.curve.ec_ops import ec_add
from src.utils.uint384 import felt_to_uint384

namespace secp256k1 {
    const CURVE_ID = CurveID.SECP256K1;
    const P0 = 0xfffffffffffffffefffffc2f;
    const P1 = 0xffffffffffffffffffffffff;
    const P2 = 0xffffffffffffffff;
    const P3 = 0x0;
    const P_LOW_128 = 0xfffffffffffffffffffffffefffffc2f;
    const P_HIGH_128 = 0xffffffffffffffffffffffffffffffff;
    const N0 = 0xaf48a03bbfd25e8cd0364141;
    const N1 = 0xfffffffffffffffebaaedce6;
    const N2 = 0xffffffffffffffff;
    const N3 = 0x0;
    const N_LOW_128 = 0xbaaedce6af48a03bbfd25e8cd0364141;
    const N_HIGH_128 = 0xfffffffffffffffffffffffffffffffe;
    const A0 = 0x0;
    const A1 = 0x0;
    const A2 = 0x0;
    const A3 = 0x0;
    const B0 = 0x7;
    const B1 = 0x0;
    const B2 = 0x0;
    const B3 = 0x0;
    const G0 = 0x3;
    const G1 = 0x0;
    const G2 = 0x0;
    const G3 = 0x0;
    const P_MIN_ONE_D0 = 0xfffffffffffffffefffffc2e;
    const P_MIN_ONE_D1 = 0xffffffffffffffffffffffff;
    const P_MIN_ONE_D2 = 0xffffffffffffffff;
    const P_MIN_ONE_D3 = 0x0;
}

// @notice generator_point = (
//     0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798,
//     0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8
// )
// @dev Split in 96 bits chunks
func get_generator_point() -> G1Point* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let generator_ptr = pc + (generator_label - pc_label);

    return cast(generator_ptr, G1Point*);

    generator_label:
    dw 0x2dce28d959f2815b16f81798;  // x.d0
    dw 0x55a06295ce870b07029bfcdb;  // x.d1
    dw 0x79be667ef9dcbbac;  // x.d2
    dw 0x0;  // x.d3
    dw 0xa68554199c47d08ffb10d4b8;  // y.d0
    dw 0x5da4fbfc0e1108a8fd17b448;  // y.d1
    dw 0x483ada7726a3c465;  // y.d2
    dw 0x0;  // y.d3
}

@known_ap_change
func sign_to_uint384_mod_secp256k1(sign: felt) -> UInt384 {
    if (sign == -1) {
        let res = UInt384(
            secp256k1.P_MIN_ONE_D0,
            secp256k1.P_MIN_ONE_D1,
            secp256k1.P_MIN_ONE_D2,
            secp256k1.P_MIN_ONE_D3,
        );
        return res;
    } else {
        let res = UInt384(1, 0, 0, 0);
        return res;
    }
}
