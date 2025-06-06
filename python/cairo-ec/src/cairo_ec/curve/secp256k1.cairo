from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import (
    UInt384,
    ModBuiltin,
    PoseidonBuiltin,
    BitwiseBuiltin,
)
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.poseidon_state import PoseidonBuiltinState
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

from cairo_core.bytes import Bytes32, Bytes32Struct
from cairo_core.maths import assert_uint256_le
from cairo_core.numeric import U384, U384Struct
from cairo_ec.circuit_utils import N_LIMBS, hash_full_transcript
from cairo_ec.circuits.ec_ops_compiled import ecip_2p
from cairo_ec.curve_utils import scalar_to_epns
from cairo_ec.curve.g1_point import G1Point, G1PointStruct
from cairo_ec.curve.ids import CurveID
from cairo_ec.ec_ops import ec_add, try_get_point_from_x, get_random_point
from cairo_ec.circuits.mod_ops_compiled import div, neg
from cairo_ec.uint384 import uint384_to_uint256, felt_to_uint384
from starkware.cairo.common.registers import get_label_location
from ethereum.utils.numeric import U384__eq__, U384_ZERO
from starkware.cairo.common.memcpy import memcpy

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
    // Used in <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/prague/transactions.py#L263>
    const N_DIVIDED_BY_2_LOW_128 = 0x5d576e7357a4501ddfe92f46681b20a0;
    const N_DIVIDED_BY_2_HIGH_128 = 0x7fffffffffffffffffffffffffffffff;
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
func get_generator_point() -> G1Point {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let generator_ptr = pc + (generator_label - pc_label);

    tempvar res = G1Point(
        new G1PointStruct(
            x=U384(cast(generator_ptr, U384Struct*)), y=U384(cast(generator_ptr + 4, U384Struct*))
        ),
    );
    return res;

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
    }
    let res = UInt384(1, 0, 0, 0);
    return res;
}

// @notice Similar to `recover_public_key`, but handles the case where 'x' does not correspond to a point on the
// curve gracefully.
// @param msg_hash The signed message hash, big-endian.
// @param r The r value of the signature.
// @param s The s value of the signature.
// @param y_parity The y parity value of the signature. true if odd, false if even.
// @return The public key associated with the signer, represented as a point on the curve, and `true` if valid.
// @return The point (0, 0) and `false` otherwise.
// @dev Prover assumptions:
// @dev * r is the x coordinate of some nonzero point on the curve.
// @dev * All the limbs of s and msg_hash are in the range (-2 ** 210.99, 2 ** 210.99).
// @dev * All the limbs of r are in the range (-2 ** 124.99, 2 ** 124.99).
func try_recover_public_key{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(msg_hash: UInt384, r: UInt384, s: UInt384, y_parity: felt) -> (
    public_key_x: Bytes32, public_key_y: Bytes32, success: felt
) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    tempvar a = U384(new UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3));
    tempvar b = U384(new UInt384(secp256k1.B0, secp256k1.B1, secp256k1.B2, secp256k1.B3));
    tempvar g = U384(new UInt384(secp256k1.G0, secp256k1.G1, secp256k1.G2, secp256k1.G3));
    tempvar modulus = U384(new UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3));

    let (y, is_on_curve) = try_get_point_from_x(
        x=U384(&r), v=y_parity, a=a, b=b, g=g, modulus=modulus
    );
    if (is_on_curve == 0) {
        tempvar public_key_x = Bytes32(new Bytes32Struct(0, 0));
        tempvar public_key_y = Bytes32(new Bytes32Struct(0, 0));
        return (public_key_x=public_key_x, public_key_y=public_key_y, success=0);
    }

    tempvar r_point = G1Point(new G1PointStruct(x=U384(&r), y=y));

    // The result is given by
    //   -(msg_hash / r) * gen + (s / r) * r_point
    // where the division by r is modulo N.

    let N = UInt384(secp256k1.N0, secp256k1.N1, secp256k1.N2, secp256k1.N3);
    let N_min_one = Uint256(secp256k1.N_LOW_128 - 1, secp256k1.N_HIGH_128);

    let _u1 = div(U384(&msg_hash), U384(&r), U384(new N));
    let _u1 = neg(_u1, U384(new N));
    let _u2 = div(U384(&s), U384(&r), U384(new N));

    let u1 = uint384_to_uint256([_u1.value]);
    assert_uint256_le(u1, N_min_one);
    let u2 = uint384_to_uint256([_u2.value]);
    assert_uint256_le(u2, N_min_one);

    let (ep1_low, en1_low, sp1_low, sn1_low) = scalar_to_epns(u1.low);
    let ep1_low_u384 = felt_to_uint384(ep1_low);
    let en1_low_u384 = felt_to_uint384(en1_low);
    let sp1_low_u384 = sign_to_uint384_mod_secp256k1(sp1_low);
    let sn1_low_u384 = sign_to_uint384_mod_secp256k1(sn1_low);

    let (ep1_high, en1_high, sp1_high, sn1_high) = scalar_to_epns(u1.high);
    let ep1_high_u384 = felt_to_uint384(ep1_high);
    let en1_high_u384 = felt_to_uint384(en1_high);
    let sp1_high_u384 = sign_to_uint384_mod_secp256k1(sp1_high);
    let sn1_high_u384 = sign_to_uint384_mod_secp256k1(sn1_high);

    let (ep2_low, en2_low, sp2_low, sn2_low) = scalar_to_epns(u2.low);
    let ep2_low_u384 = felt_to_uint384(ep2_low);
    let en2_low_u384 = felt_to_uint384(en2_low);
    let sp2_low_u384 = sign_to_uint384_mod_secp256k1(sp2_low);
    let sn2_low_u384 = sign_to_uint384_mod_secp256k1(sn2_low);

    let (ep2_high, en2_high, sp2_high, sn2_high) = scalar_to_epns(u2.high);
    let ep2_high_u384 = felt_to_uint384(ep2_high);
    let en2_high_u384 = felt_to_uint384(en2_high);
    let sp2_high_u384 = sign_to_uint384_mod_secp256k1(sp2_high);
    let sn2_high_u384 = sign_to_uint384_mod_secp256k1(sn2_high);

    %{ build_msm_hints_and_fill_memory %}

    // Interaction with Poseidon, protocol is roughly a sequence of hashing:
    // - initial constant 'MSM_G1'
    // - curve ID
    // - Number of scalars in MSM
    // - curve generator G
    // - user input R point
    //
    // ==> interaction
    //
    // - u1
    // - u2
    // > get random linear combination coefficients
    //
    // ==> interaction
    // > get seed for random point

    // rlc_coeff is casted to Uint384 after hashing the values of Q (which is used to compute rlc_coeff)
    tempvar rlc_coeff_u384_cast_offset = 4;
    tempvar ecip_circuit_constants_offset = 5 * N_LIMBS;
    tempvar ecip_circuit_q_offset = 46 * N_LIMBS;

    let msm_size = 2;
    assert poseidon_ptr[0].input = PoseidonBuiltinState(s0='MSM_G1', s1=0, s2=1);
    assert poseidon_ptr[1].input = PoseidonBuiltinState(
        s0=secp256k1.CURVE_ID + poseidon_ptr[0].output.s0,
        s1=msm_size + poseidon_ptr[0].output.s1,
        s2=poseidon_ptr[0].output.s2,
    );
    let poseidon_ptr = poseidon_ptr + 2 * PoseidonBuiltin.SIZE;

    let generator_point = get_generator_point();
    let (generator_point_limbs: felt*) = alloc();
    memcpy(generator_point_limbs, generator_point.value.x.value, 4);
    memcpy(generator_point_limbs + 4, generator_point.value.y.value, 4);
    hash_full_transcript(generator_point_limbs, 2);

    let (r_limbs: felt*) = alloc();
    memcpy(r_limbs, r_point.value.x.value, 4);
    memcpy(r_limbs + 4, r_point.value.y.value, 4);
    hash_full_transcript(r_limbs, 2);

    // Q_low, Q_high, Q_high_shifted (filled by prover) (46 - 51).
    hash_full_transcript(
        range_check96_ptr + rlc_coeff_u384_cast_offset + ecip_circuit_constants_offset +
        ecip_circuit_q_offset,
        3 * 2,
    );
    let _s0 = [cast(poseidon_ptr, felt*) - 3];
    let _s1 = [cast(poseidon_ptr, felt*) - 2];
    let _s2 = [cast(poseidon_ptr, felt*) - 1];

    // U1, U2
    assert poseidon_ptr[0].input = PoseidonBuiltinState(s0=_s0 + u1.low, s1=_s1 + u1.high, s2=_s2);
    assert poseidon_ptr[1].input = PoseidonBuiltinState(
        s0=poseidon_ptr[0].output.s0 + u2.low,
        s1=poseidon_ptr[0].output.s1 + u2.high,
        s2=poseidon_ptr[0].output.s2,
    );
    tempvar rlc_coeff = poseidon_ptr[1].output.s1;
    let poseidon_ptr = poseidon_ptr + 2 * PoseidonBuiltin.SIZE;
    let rlc_coeff_u384 = felt_to_uint384(rlc_coeff);

    // Hash sum_dlog_div 2 points : (0-25)
    hash_full_transcript(range_check96_ptr + ecip_circuit_constants_offset, 26);
    tempvar range_check96_ptr_init = range_check96_ptr;
    tempvar range_check96_ptr_after_circuit = range_check96_ptr + 1200;
    let random_point = get_random_point{range_check96_ptr=range_check96_ptr_after_circuit}(
        seed=[cast(poseidon_ptr, felt*) - 3], a=a, b=b, g=g, modulus=modulus
    );
    let range_check96_ptr = range_check96_ptr_init;

    // Circuits inputs

    let ecip_input: UInt384* = cast(range_check96_ptr + ecip_circuit_constants_offset, UInt384*);

    // Random Linear Combination Sum of Discrete Logarithm Division
    // rlc_sum_dlog_div for 2 points: n_coeffs = 18 + 4 * 2 = 26 (0-25)

    // q_low, q_high, q_high_shifted (46 - 51)

    ecip_2p(
        U384(&ecip_input[0]),
        U384(&ecip_input[1]),
        U384(&ecip_input[2]),
        U384(&ecip_input[3]),
        U384(&ecip_input[4]),
        U384(&ecip_input[5]),
        U384(&ecip_input[6]),
        U384(&ecip_input[7]),
        U384(&ecip_input[8]),
        U384(&ecip_input[9]),
        U384(&ecip_input[10]),
        U384(&ecip_input[11]),
        U384(&ecip_input[12]),
        U384(&ecip_input[13]),
        U384(&ecip_input[14]),
        U384(&ecip_input[15]),
        U384(&ecip_input[16]),
        U384(&ecip_input[17]),
        U384(&ecip_input[18]),
        U384(&ecip_input[19]),
        U384(&ecip_input[20]),
        U384(&ecip_input[21]),
        U384(&ecip_input[22]),
        U384(&ecip_input[23]),
        U384(&ecip_input[24]),
        U384(&ecip_input[25]),
        generator_point.value,
        r_point.value,
        U384(&ep1_low_u384),
        U384(&en1_low_u384),
        U384(&sp1_low_u384),
        U384(&sn1_low_u384),
        U384(&ep2_low_u384),
        U384(&en2_low_u384),
        U384(&sp2_low_u384),
        U384(&sn2_low_u384),
        U384(&ep1_high_u384),
        U384(&en1_high_u384),
        U384(&sp1_high_u384),
        U384(&sn1_high_u384),
        U384(&ep2_high_u384),
        U384(&en2_high_u384),
        U384(&sp2_high_u384),
        U384(&sn2_high_u384),
        U384(&ecip_input[46]),
        U384(&ecip_input[47]),
        U384(&ecip_input[48]),
        U384(&ecip_input[49]),
        U384(&ecip_input[50]),
        U384(&ecip_input[51]),
        random_point.value,
        a,
        b,
        U384(&rlc_coeff_u384),
        modulus=modulus,
    );

    let range_check96_ptr = range_check96_ptr_after_circuit;

    tempvar p0 = G1Point(new G1PointStruct(x=U384(&ecip_input[46]), y=U384(&ecip_input[47])));
    tempvar p1 = G1Point(new G1PointStruct(x=U384(&ecip_input[50]), y=U384(&ecip_input[51])));

    let res = ec_add(p0, p1, a, modulus);

    let (u384_zero) = get_label_location(U384_ZERO);
    let point_at_infinity_x = U384__eq__(res.value.x, U384(cast(u384_zero, U384Struct*)));
    let point_at_infinity_y = U384__eq__(res.value.y, U384(cast(u384_zero, U384Struct*)));
    if (point_at_infinity_x.value != 0 and point_at_infinity_y.value != 0) {
        tempvar public_key_x = Bytes32(new Bytes32Struct(0, 0));
        tempvar public_key_y = Bytes32(new Bytes32Struct(0, 0));
        return (public_key_x=public_key_x, public_key_y=public_key_y, success=0);
    }

    let max_value = Uint256(secp256k1.P_LOW_128 - 1, secp256k1.P_HIGH_128);
    let x_uint256 = uint384_to_uint256([res.value.x.value]);
    assert_uint256_le(x_uint256, max_value);
    let y_uint256 = uint384_to_uint256([res.value.y.value]);
    assert_uint256_le(y_uint256, max_value);

    let (x_reversed) = uint256_reverse_endian(x_uint256);
    let (y_reversed) = uint256_reverse_endian(y_uint256);

    tempvar public_key_x = Bytes32(new Bytes32Struct(x_reversed.low, x_reversed.high));
    tempvar public_key_y = Bytes32(new Bytes32Struct(y_reversed.low, y_reversed.high));
    return (public_key_x=public_key_x, public_key_y=public_key_y, success=1);
}
