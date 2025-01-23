from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    UInt384,
    PoseidonBuiltin,
)
from starkware.cairo.common.poseidon_state import PoseidonBuiltinState
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location

from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from src.utils.maths import unsigned_div_rem, scalar_to_epns
from src.utils.circuit_utils import N_LIMBS, hash_full_transcript
from src.utils.ecdsa_circuit import get_full_ecip_2P_circuit
from src.utils.uint256 import assert_uint256_le
from src.utils.uint384 import (
    uint384_to_uint256,
    uint256_to_uint384,
    uint384_eq_mod_p,
    uint384_is_neg_mod_p,
    uint384_div_mod_p,
    uint384_neg_mod_p,
    felt_to_uint384,
)
from src.curve.secp256k1 import (
    secp256k1,
    get_generator_point,
    try_get_point_from_x,
    get_random_point,
    ec_add,
    sign_to_uint384_mod_secp256k1,
)
from src.curve.g1_point import G1Point

namespace Signature {
    // Assert 1 <= x < N. Assumes valid Uint256.
    func validate_signature_entry{range_check_ptr}(x: Uint256) {
        if (x.high == 0) {
            if (x.low == 0) {
                assert 1 = 0;
                return ();
            } else {
                return ();
            }
        } else {
            if (x.high == secp256k1.N_HIGH_128) {
                assert [range_check_ptr] = secp256k1.N_LOW_128 - 1 - x.low;
                tempvar range_check_ptr = range_check_ptr + 1;
                return ();
            } else {
                assert [range_check_ptr] = secp256k1.N_HIGH_128 - 1 - x.high;
                tempvar range_check_ptr = range_check_ptr + 1;
                return ();
            }
        }
    }

    func verify_eth_signature_uint256{
        range_check_ptr,
        range_check96_ptr: felt*,
        add_mod_ptr: ModBuiltin*,
        mul_mod_ptr: ModBuiltin*,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        poseidon_ptr: PoseidonBuiltin*,
    }(msg_hash: Uint256, r: Uint256, s: Uint256, y_parity: felt, eth_address: felt) {
        alloc_locals;
        with_attr error_message("Signature out of range.") {
            validate_signature_entry(r);
            validate_signature_entry(s);
        }
        let msg_hash_uint384 = uint256_to_uint384(msg_hash);
        let r_uint384 = uint256_to_uint384(r);
        let s_uint384 = uint256_to_uint384(s);

        with_attr error_message("Invalid y_parity") {
            assert (1 - y_parity) * y_parity = 0;
        }

        with_attr error_message("Invalid signature.") {
            let (success, recovered_address) = try_recover_eth_address(
                msg_hash=msg_hash_uint384, r=r_uint384, s=s_uint384, y_parity=y_parity
            );
            assert success = 1;
            assert eth_address = recovered_address;
        }

        return ();
    }

    // @notice Similar to `recover_public_key`, but handles the case where 'x' does not correspond to a point on the
    // curve gracefully.
    // @param msg_hash The signed message hash.
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
        range_check96_ptr: felt*,
        add_mod_ptr: ModBuiltin*,
        mul_mod_ptr: ModBuiltin*,
        poseidon_ptr: PoseidonBuiltin*,
    }(msg_hash: UInt384, r: UInt384, s: UInt384, y_parity: felt) -> (
        public_key_point: G1Point, success: felt
    ) {
        alloc_locals;
        let (__fp__, _) = get_fp_and_pc();
        let (y, is_on_curve) = try_get_point_from_x(x=r, v=y_parity);
        if (is_on_curve == 0) {
            return (
                public_key_point=G1Point(x=UInt384(0, 0, 0, 0), y=UInt384(0, 0, 0, 0)), success=0
            );
        }
        let r_point = G1Point(x=r, y=y);
        // The result is given by
        //   -(msg_hash / r) * gen + (s / r) * r_point
        // where the division by r is modulo N.

        let N = UInt384(secp256k1.N0, secp256k1.N1, secp256k1.N2, secp256k1.N3);
        let N_min_one = Uint256(secp256k1.N_LOW_128 - 1, secp256k1.N_HIGH_128);

        let _u1 = uint384_div_mod_p(msg_hash, r, N);
        let _u1 = uint384_neg_mod_p(_u1, N);
        let _u2 = uint384_div_mod_p(s, r, N);

        let u1 = uint384_to_uint256(_u1);
        assert_uint256_le(u1, N_min_one);
        let u2 = uint384_to_uint256(_u2);
        assert_uint256_le(u2, N_min_one);

        let (ep1_low, en1_low, sp1_low, sn1_low) = scalar_to_epns(u1.low);
        let ep1_low_384 = felt_to_uint384(ep1_low);
        let en1_low_384 = felt_to_uint384(en1_low);
        let sp1_low_384 = sign_to_uint384_mod_secp256k1(sp1_low);
        let sn1_low_384 = sign_to_uint384_mod_secp256k1(sn1_low);

        let (ep1_high, en1_high, sp1_high, sn1_high) = scalar_to_epns(u1.high);
        let ep1_high_384 = felt_to_uint384(ep1_high);
        let en1_high_384 = felt_to_uint384(en1_high);
        let sp1_high_384 = sign_to_uint384_mod_secp256k1(sp1_high);
        let sn1_high_384 = sign_to_uint384_mod_secp256k1(sn1_high);

        let (ep2_low, en2_low, sp2_low, sn2_low) = scalar_to_epns(u2.low);
        let ep2_low_384 = felt_to_uint384(ep2_low);
        let en2_low_384 = felt_to_uint384(en2_low);
        let sp2_low_384 = sign_to_uint384_mod_secp256k1(sp2_low);
        let sn2_low_384 = sign_to_uint384_mod_secp256k1(sn2_low);

        let (ep2_high, en2_high, sp2_high, sn2_high) = scalar_to_epns(u2.high);
        let ep2_high_384 = felt_to_uint384(ep2_high);
        let en2_high_384 = felt_to_uint384(en2_high);
        let sp2_high_384 = sign_to_uint384_mod_secp256k1(sp2_high);
        let sn2_high_384 = sign_to_uint384_mod_secp256k1(sn2_high);

        %{
            from garaga.hints.io import pack_bigint_ptr, pack_felt_ptr, fill_sum_dlog_div, fill_g1_point, bigint_split
            from garaga.starknet.tests_and_calldata_generators.msm import MSMCalldataBuilder
            from garaga.definitions import G1Point
            import time
            curve_id = CurveID.SECP256K1
            r_point = (bigint_pack(ids.r_point.x, 4, 2**96), bigint_pack(ids.r_point.y, 4, 2**96))
            points = [G1Point.get_nG(curve_id, 1), G1Point(r_point[0], r_point[1], curve_id)]
            scalars = [ids.u1.low + 2**128*ids.u1.high, ids.u2.low + 2**128*ids.u2.high]
            builder = MSMCalldataBuilder(curve_id, points, scalars)
            (msm_hint, derive_point_from_x_hint) = builder.build_msm_hints()
            Q_low, Q_high, Q_high_shifted, RLCSumDlogDiv = msm_hint.elmts

            def fill_elmt_at_index(
                x, ptr: object, memory: object, index: int, static_offset: int = 0
            ):
                limbs = bigint_split(x, 4, 2**96)
                for i in range(4):
                    memory[ptr + index * 4 + i + static_offset] = limbs[i]
                return


            def fill_elmts_at_index(
                x,
                ptr: object,
                memory: object,
                index: int,
                static_offset: int = 0,
            ):
                for i in range(len(x)):
                    fill_elmt_at_index(x[i], ptr + i * 4, memory, index, static_offset)
                return

            rlc_sum_dlog_div_coeffs = RLCSumDlogDiv.a_num + RLCSumDlogDiv.a_den + RLCSumDlogDiv.b_num + RLCSumDlogDiv.b_den
            assert len(rlc_sum_dlog_div_coeffs) == 18 + 4*2, f"len(rlc_sum_dlog_div_coeffs) == {len(rlc_sum_dlog_div_coeffs)} != {18 + 4*2}"


            offset = 4
            fill_elmts_at_index(rlc_sum_dlog_div_coeffs, ids.range_check96_ptr, memory, 4, offset)

            fill_elmt_at_index(Q_low[0], ids.range_check96_ptr, memory, 50, offset)
            fill_elmt_at_index(Q_low[1], ids.range_check96_ptr, memory, 51, offset)
            fill_elmt_at_index(Q_high[0], ids.range_check96_ptr, memory, 52, offset)
            fill_elmt_at_index(Q_high[1], ids.range_check96_ptr, memory, 53, offset)
            fill_elmt_at_index(Q_high_shifted[0], ids.range_check96_ptr, memory, 54, offset)
            fill_elmt_at_index(Q_high_shifted[1], ids.range_check96_ptr, memory, 55, offset)
        %}

        // Interaction with Poseidon, protocol is roughly a sequence of hashing:
        // - initial constant 'MSM_G1'
        // - curve ID
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

        assert poseidon_ptr[0].input = PoseidonBuiltinState(s0='MSM_G1', s1=0, s2=1);
        assert poseidon_ptr[1].input = PoseidonBuiltinState(
            s0=secp256k1.CURVE_ID + poseidon_ptr[0].output.s0,
            s1=2 + poseidon_ptr[0].output.s1,
            s2=poseidon_ptr[0].output.s2,
        );
        let poseidon_ptr = poseidon_ptr + 2 * PoseidonBuiltin.SIZE;

        let generator_point = get_generator_point();
        hash_full_transcript(cast(generator_point, felt*), 2);
        hash_full_transcript(cast(&r_point, felt*), 2);
        // Q_low, Q_high, Q_high_shifted (filled by prover) (50 - 55).
        hash_full_transcript(range_check96_ptr + 4 + 50 * N_LIMBS, 3 * 2);
        let _s0 = [cast(poseidon_ptr, felt*) - 3];
        let _s1 = [cast(poseidon_ptr, felt*) - 2];
        let _s2 = [cast(poseidon_ptr, felt*) - 1];

        // U1, U2
        assert poseidon_ptr[0].input = PoseidonBuiltinState(
            s0=_s0 + u1.low, s1=_s1 + u1.high, s2=_s2
        );
        assert poseidon_ptr[1].input = PoseidonBuiltinState(
            s0=poseidon_ptr[0].output.s0 + u2.low,
            s1=poseidon_ptr[0].output.s1 + u2.high,
            s2=poseidon_ptr[0].output.s2,
        );
        tempvar rlc_coeff = poseidon_ptr[1].output.s1;
        let poseidon_ptr = poseidon_ptr + 2 * PoseidonBuiltin.SIZE;
        let rlc_coeff_u384 = felt_to_uint384(rlc_coeff);

        // Hash SumDlogDiv 2 points : (4-29)
        hash_full_transcript(range_check96_ptr + 4 * N_LIMBS, 26);
        tempvar range_check96_ptr_init = range_check96_ptr;
        tempvar range_check96_ptr_after_circuit = range_check96_ptr + 224 + (4 + 117 + 108 - 1) *
            N_LIMBS;
        let random_point = get_random_point{range_check96_ptr=range_check96_ptr_after_circuit}(
            seed=[cast(poseidon_ptr, felt*) - 3]
        );

        tempvar range_check96_ptr_final = range_check96_ptr_after_circuit;
        let range_check96_ptr = range_check96_ptr_init;

        // Circuits inputs

        let ecip_input: UInt384* = cast(range_check96_ptr, UInt384*);
        // Constants (0-3)
        assert ecip_input[0] = UInt384(secp256k1.G0, secp256k1.G1, secp256k1.G2, secp256k1.G3);
        assert ecip_input[1] = UInt384(0, 0, 0, 0);
        assert ecip_input[2] = UInt384(12528508628158887531275213211, 66632300, 0, 0);
        assert ecip_input[3] = UInt384(12528508628158887531275213211, 4361599596, 0, 0);

        // Random Linear Combination Sum of Discrete Logarithm Division
        // RLCSumDlogDiv for 2 points: n_coeffs = 18 + 4 * 2 = 26 (4-29)

        // Generator point, same as in get_generator_point()
        assert ecip_input[30] = UInt384(
            0x2dce28d959f2815b16f81798, 0x55a06295ce870b07029bfcdb, 0x79be667ef9dcbbac, 0x0
        );
        assert ecip_input[31] = UInt384(
            0xa68554199c47d08ffb10d4b8, 0x5da4fbfc0e1108a8fd17b448, 0x483ada7726a3c465, 0x0
        );

        // R point
        assert ecip_input[32] = r_point.x;
        assert ecip_input[33] = r_point.y;

        assert ecip_input[34] = ep1_low_384;
        assert ecip_input[35] = en1_low_384;
        assert ecip_input[36] = sp1_low_384;
        assert ecip_input[37] = sn1_low_384;

        assert ecip_input[38] = ep2_low_384;
        assert ecip_input[39] = en2_low_384;
        assert ecip_input[40] = sp2_low_384;
        assert ecip_input[41] = sn2_low_384;

        assert ecip_input[42] = ep1_high_384;
        assert ecip_input[43] = en1_high_384;
        assert ecip_input[44] = sp1_high_384;
        assert ecip_input[45] = sn1_high_384;

        assert ecip_input[46] = ep2_high_384;
        assert ecip_input[47] = en2_high_384;
        assert ecip_input[48] = sp2_high_384;
        assert ecip_input[49] = sn2_high_384;

        // Q_low / Q_high / Q_high_shifted (filled by prover) (50 - 55).

        assert ecip_input[56] = random_point.x;
        assert ecip_input[57] = random_point.y;

        // a_Weierstrass
        assert ecip_input[58] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);
        // base_rlc
        assert ecip_input[59] = rlc_coeff_u384;

        let (add_offsets_ptr, mul_offsets_ptr) = get_full_ecip_2P_circuit();
        let p = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
        assert add_mod_ptr[0] = ModBuiltin(
            p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=117
        );
        assert mul_mod_ptr[0] = ModBuiltin(
            p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=108
        );

        %{
            from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
            assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
            assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

            ModBuiltinRunner.fill_memory(
                memory=memory,
                add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 117),
                mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 108),
            )
        %}

        tempvar range_check96_ptr = range_check96_ptr_final;
        let add_mod_ptr = add_mod_ptr + 117 * ModBuiltin.SIZE;
        let mul_mod_ptr = mul_mod_ptr + 108 * ModBuiltin.SIZE;
        let res = ec_add(
            G1Point(x=ecip_input[50], y=ecip_input[51]), G1Point(x=ecip_input[54], y=ecip_input[55])
        );
        return (public_key_point=res, success=1);
    }

    // @notice Converts a public key point to the corresponding Ethereum address.
    // @param x The x coordinate of the public key point.
    // @param y The y coordinate of the public key point.
    // @return The Ethereum address.
    func public_key_point_to_eth_address{
        range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
    }(x: Uint256, y: Uint256) -> felt {
        alloc_locals;
        let (local elements: Uint256*) = alloc();
        assert elements[0] = x;
        assert elements[1] = y;
        let (point_hash: Uint256) = keccak_uint256s_bigend(n_elements=2, elements=elements);

        // The Ethereum address is the 20 least significant bytes of the keccak of the public key.
        let (_, high_low) = unsigned_div_rem(point_hash.high, 2 ** 32);
        let eth_address = point_hash.low + RC_BOUND * high_low;
        return eth_address;
    }

    // @notice Recovers the Ethereum address from a signature.
    // @dev If the public key point is not on the curve, the function returns success=0.
    // @dev: This function does not validate the r, s values.
    // @param msg_hash The signed message hash.
    // @param r The r value of the signature.
    // @param s The s value of the signature.
    // @param y_parity The y parity value of the signature. true if odd, false if even.
    // @return The Ethereum address.
    func try_recover_eth_address{
        range_check_ptr,
        range_check96_ptr: felt*,
        add_mod_ptr: ModBuiltin*,
        mul_mod_ptr: ModBuiltin*,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        poseidon_ptr: PoseidonBuiltin*,
    }(msg_hash: UInt384, r: UInt384, s: UInt384, y_parity: felt) -> (success: felt, address: felt) {
        alloc_locals;
        let (public_key_point, success) = try_recover_public_key(
            msg_hash=msg_hash, r=r, s=s, y_parity=y_parity
        );
        if (success == 0) {
            return (success=0, address=0);
        }
        let max_value = Uint256(secp256k1.P_LOW_128 - 1, secp256k1.P_HIGH_128);
        let x_uint256 = uint384_to_uint256(public_key_point.x);
        assert_uint256_le(x_uint256, max_value);
        let y_uint256 = uint384_to_uint256(public_key_point.y);
        assert_uint256_le(y_uint256, max_value);
        let address = public_key_point_to_eth_address(x=x_uint256, y=y_uint256);
        return (success=success, address=address);
    }
}
