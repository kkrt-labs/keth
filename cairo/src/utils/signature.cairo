from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    UInt384,
    PoseidonBuiltin,
)
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from ethereum.utils.numeric import divmod

from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from src.utils.maths import unsigned_div_rem

from src.interfaces.interfaces import ICairo1Helpers
from src.utils.circuit_basic_field_ops import div_mod_p, neg_mod_p, is_opposite_mod_p, is_eq_mod_p
from src.utils.circuit_utils import (
    N_LIMBS,
    hash_full_transcript_and_get_Z_3_LIMBS,
    scalar_to_epns,
    felt_to_UInt384,
    run_modulo_circuit_basic,
)

from src.utils.ecdsa_circuit import (
    get_full_ecip_2P_circuit,
    get_ADD_EC_POINT_circuit,
    get_DOUBLE_EC_POINT_circuit,
)

struct G1Point {
    x: UInt384,
    y: UInt384,
}

namespace secp256k1 {
    const CURVE_ID = 2;
    const P0 = 0xfffffffffffffffefffffc2f;
    const P1 = 0xffffffffffffffffffffffff;
    const P2 = 0xffffffffffffffff;
    const P3 = 0x0;
    const N0 = 0xaf48a03bbfd25e8cd0364141;
    const N1 = 0xfffffffffffffffebaaedce6;
    const N2 = 0xffffffffffffffff;
    const N_LOW_128 = 0xbaaedce6af48a03bbfd25e8cd0364141;
    const N_HIGH_128 = 0xfffffffffffffffffffffffffffffffe;
    const N3 = 0x0;
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
    const MIN_ONE_D0 = 0xfffffffffffffffefffffc2e;
    const MIN_ONE_D1 = 0xffffffffffffffffffffffff;
    const MIN_ONE_D2 = 0xffffffffffffffff;
    const MIN_ONE_D3 = 0x0;
}

const POW_2_32 = 2 ** 32;
const POW_2_64 = 2 ** 64;
const POW_2_96 = 2 ** 96;

@known_ap_change
func get_generator_point() -> (point: G1Point) {
    // generator_point = (
    //     0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798,
    //     0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8
    // ).
    return (
        point=G1Point(
            x=UInt384(
                0x2dce28d959f2815b16f81798, 0x55a06295ce870b07029bfcdb, 0x79be667ef9dcbbac, 0x0
            ),
            y=UInt384(
                0xa68554199c47d08ffb10d4b8, 0x5da4fbfc0e1108a8fd17b448, 0x483ada7726a3c465, 0x0
            ),
        ),
    );
}

@known_ap_change
func sign_to_UInt384_mod_secp256k1(sign: felt) -> (res: UInt384) {
    if (sign == -1) {
        return (res=UInt384(secp256k1.MIN_ONE_D0, secp256k1.MIN_ONE_D1, secp256k1.MIN_ONE_D2, 0));
    } else {
        return (res=UInt384(1, 0, 0, 0));
    }
}

// Input must be a valid Uint256.
func uint256_to_uint384{range_check_ptr}(a: Uint256) -> (res: UInt384) {
    let (high_64_high, high_64_low) = divmod(a.high, POW_2_64);
    let (low_32_high, low_96_low) = divmod(a.low, POW_2_96);
    return (res=UInt384(low_96_low, low_32_high + POW_2_32 * high_64_low, high_64_high, 0));
}

// Assume the input is valid UInt384 (will be the case if coming from ModuloBuiltin)
func uint384_to_uint256_mod_p{range_check_ptr}(a: UInt384, p: UInt384) -> (res: Uint256) {
    // First force the prover to have filled a fully reduced field element < P.
    assert a.d3 = 0;
    assert [range_check_ptr] = p.d2 - a.d2;  // a.d2 <= p.d2
    tempvar range_check_ptr = range_check_ptr + 1;

    if (a.d2 == p.d2) {
        if (a.d1 == p.d1) {
            assert [range_check_ptr] = p.d0 - 1 - a.d0;
            tempvar range_check_ptr = range_check_ptr + 1;
        } else {
            assert [range_check_ptr] = p.d1 - 1 - a.d1;
            tempvar range_check_ptr = range_check_ptr + 1;
        }
    } else {
        tempvar range_check_ptr = range_check_ptr;
    }
    // Then decompose and rebuild uint256
    let (d1_high_64, d1_low_32) = divmod(a.d1, 2 ** 32);
    // a.d2 is guaranteed to be in 64 bits since we know it's fully reduced.
    return (res=Uint256(low=a.d0 + 2 ** 96 * d1_low_32, high=d1_high_64 + 2 ** 64 * a.d2));
}

// A function field element of the form :
// F(x,y) = a(x) + y b(x)
// Where a, b are rational functions of x.
// The rational functions are represented as polynomials in x with coefficients in F_p, starting from the constant term.
// No information about the degrees of the polynomials is stored here as they are derived implicitely from the MSM size.
struct FunctionFelt {
    a_num: UInt384*,
    a_den: UInt384*,
    b_num: UInt384*,
    b_den: UInt384*,
}

func hash_sum_dlog_div_batched{poseidon_ptr: PoseidonBuiltin*}(
    f: FunctionFelt, msm_size: felt, init_hash: felt, curve_id: felt
) -> (res: felt) {
    alloc_locals;
    assert poseidon_ptr[0].input.s0 = init_hash;
    assert poseidon_ptr[0].input.s1 = 0;
    assert poseidon_ptr[0].input.s2 = 1;
    let poseidon_ptr = poseidon_ptr + PoseidonBuiltin.SIZE;

    let (s0: felt, s1: felt, s2: felt) = hash_full_transcript_and_get_Z_3_LIMBS(
        limbs_ptr=cast(f.a_num, felt*), n=msm_size + 1, curve_id=curve_id
    );
    let (s0: felt, s1: felt, s2: felt) = hash_full_transcript_and_get_Z_3_LIMBS(
        limbs_ptr=cast(f.a_den, felt*), n=msm_size + 2, curve_id=curve_id
    );
    let (s0: felt, s1: felt, s2: felt) = hash_full_transcript_and_get_Z_3_LIMBS(
        limbs_ptr=cast(f.b_num, felt*), n=msm_size + 2, curve_id=curve_id
    );
    let (Z: felt, _, _) = hash_full_transcript_and_get_Z_3_LIMBS(
        limbs_ptr=cast(f.b_den, felt*), n=msm_size + 5, curve_id=curve_id
    );

    return (res=Z);
}

func try_get_point_from_x_secp256k1{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(x: UInt384, v: felt, result: G1Point*) -> (is_on_curve: felt) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();
    let (add_offsets_ptr: felt*) = get_label_location(add_offsets_ptr_loc);
    let (mul_offsets_ptr: felt*) = get_label_location(mul_offsets_ptr_loc);
    let constants_ptr_len = 2;
    let input_len = 24;
    let add_mod_n = 5;
    let mul_mod_n = 7;
    let n_assert_eq = 1;

    local rhs_from_x_is_a_square_residue: felt;
    local y_try: UInt384;
    %{
        from starkware.python.math_utils import is_quad_residue
        from sympy import sqrt_mod
        from garaga.definitions import CURVES, CurveID
        from garaga.hints.io import bigint_pack, bigint_fill
        curve_id = CurveID.SECP256K1.value
        a = CURVES[curve_id].a
        b = CURVES[curve_id].b
        p = CURVES[curve_id].p
        x = bigint_pack(ids.x, 4, 2**96)
        rhs = (x**3 + a*x + b) % p
        ids.rhs_from_x_is_a_square_residue = is_quad_residue(rhs, p)
        if ids.rhs_from_x_is_a_square_residue == 1:
            square_root = sqrt_mod(rhs, p)
            if ids.v % 2 == square_root % 2:
                pass
            else:
                square_root = - square_root % p
        else:
            square_root = sqrt_mod(rhs*CURVES[curve_id].fp_generator, p)

        bigint_fill(square_root, ids.y_try, 4, 2**96)
    %}

    let P: UInt384 = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);

    let input: UInt384* = cast(range_check96_ptr, UInt384*);

    assert input[0] = UInt384(1, 0, 0, 0);
    assert input[1] = UInt384(0, 0, 0, 0);
    assert input[2] = x;
    assert input[3] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);
    assert input[4] = UInt384(secp256k1.B0, secp256k1.B1, secp256k1.B2, secp256k1.B3);
    assert input[5] = UInt384(secp256k1.G0, secp256k1.G1, secp256k1.G2, secp256k1.G3);
    assert input[6] = y_try;

    if (rhs_from_x_is_a_square_residue != 0) {
        assert input[7] = UInt384(1, 0, 0, 0);
    } else {
        assert input[7] = UInt384(0, 0, 0, 0);
    }

    run_modulo_circuit_basic(
        P, add_offsets_ptr, add_mod_n, mul_offsets_ptr, mul_mod_n, input_len, n_assert_eq
    );

    if (rhs_from_x_is_a_square_residue != 0) {
        assert [result] = G1Point(x=x, y=y_try);
        return (is_on_curve=1);
    } else {
        assert [result] = G1Point(x=UInt384(0, 0, 0, 0), y=UInt384(0, 0, 0, 0));
        return (is_on_curve=0);
    }

    // constants_ptr_loc:
    // dw 1;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;

    add_offsets_ptr_loc:
    dw 40;  // (ax)+b
    dw 16;
    dw 44;
    dw 36;  // (x3+ax)+b=rhs
    dw 44;
    dw 48;
    dw 28;  // (1-is_on_curve)
    dw 60;
    dw 0;
    dw 56;  // is_on_curve*rhs + (1-is_on_curve)*g*rhs
    dw 64;
    dw 68;
    dw 4;  // assert rhs_or_grhs == should_be_rhs_or_grhs
    dw 72;
    dw 68;

    mul_offsets_ptr_loc:
    dw 8;  // x2
    dw 8;
    dw 32;
    dw 8;  // x3
    dw 32;
    dw 36;
    dw 12;  // ax
    dw 8;
    dw 40;
    dw 20;  // g*rhs
    dw 48;
    dw 52;
    dw 28;  // is_on_curve*rhs
    dw 48;
    dw 56;
    dw 60;  // (1-is_on_curve)*grhs
    dw 52;
    dw 64;
    dw 24;  // y_try^2=should_be_rhs_or_grhs
    dw 24;
    dw 72;
}

namespace Signature {
    // A version of verify_eth_signature that uses the keccak builtin.

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
        let (msg_hash_uint384: UInt384) = uint256_to_uint384(msg_hash);
        // Todo :fix with UInt384
        with_attr error_message("Signature out of range.") {
            validate_signature_entry(r);
            validate_signature_entry(s);
        }
        let (r_uint384: UInt384) = uint256_to_uint384(r);
        let (s_uint384: UInt384) = uint256_to_uint384(s);

        with_attr error_message("Invalid y_parity") {
            assert (1 - y_parity) * y_parity = 0;
        }

        with_attr error_message("Invalid signature.") {
            let (success, recovered_address) = try_recover_eth_address(
                msg_hash=msg_hash_uint384, r=r_uint384, s=s_uint384, y_parity=y_parity
            );
            assert success = 1;
        }

        assert eth_address = recovered_address;
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
        let (local r_point: G1Point*) = alloc();
        let (is_on_curve) = try_get_point_from_x_secp256k1(x=r, v=y_parity, result=r_point);
        if (is_on_curve == 0) {
            assert 1 = 0;
            return (
                public_key_point=G1Point(x=UInt384(0, 0, 0, 0), y=UInt384(0, 0, 0, 0)), success=0
            );
        }
        let (generator_point: G1Point) = get_generator_point();
        // The result is given by
        //   -(msg_hash / r) * gen + (s / r) * r_point
        // where the division by r is modulo N.

        let N = UInt384(secp256k1.N0, secp256k1.N1, secp256k1.N2, secp256k1.N3);

        let (_u1: UInt384) = div_mod_p(msg_hash, r, N);
        let (_u1: UInt384) = neg_mod_p(_u1, N);
        let (_u2: UInt384) = div_mod_p(s, r, N);

        let (u1) = uint384_to_uint256_mod_p(_u1, N);
        let (u2) = uint384_to_uint256_mod_p(_u2, N);

        let (ep1_low, en1_low, sp1_low, sn1_low) = scalar_to_epns(u1.low);
        let (ep1_high, en1_high, sp1_high, sn1_high) = scalar_to_epns(u1.high);

        let (ep1_low_384) = felt_to_UInt384(ep1_low);
        let (en1_low_384) = felt_to_UInt384(en1_low);
        let (sp1_low_384) = sign_to_UInt384_mod_secp256k1(sp1_low);
        let (sn1_low_384) = sign_to_UInt384_mod_secp256k1(sn1_low);

        let (ep1_high_384) = felt_to_UInt384(ep1_high);
        let (en1_high_384) = felt_to_UInt384(en1_high);
        let (sp1_high_384) = sign_to_UInt384_mod_secp256k1(sp1_high);
        let (sn1_high_384) = sign_to_UInt384_mod_secp256k1(sn1_high);

        let (ep2_low, en2_low, sp2_low, sn2_low) = scalar_to_epns(u2.low);

        let (ep2_low_384) = felt_to_UInt384(ep2_low);
        let (en2_low_384) = felt_to_UInt384(en2_low);
        let (sp2_low_384) = sign_to_UInt384_mod_secp256k1(sp2_low);
        let (sn2_low_384) = sign_to_UInt384_mod_secp256k1(sn2_low);

        let (ep2_high, en2_high, sp2_high, sn2_high) = scalar_to_epns(u2.high);
        let (ep2_high_384) = felt_to_UInt384(ep2_high);
        let (en2_high_384) = felt_to_UInt384(en2_high);
        let (sp2_high_384) = sign_to_UInt384_mod_secp256k1(sp2_high);
        let (sn2_high_384) = sign_to_UInt384_mod_secp256k1(sn2_high);

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
                x, ptr: object, memory: object, index: int
            ):
                limbs = bigint_split(x, 4, 2**96)
                for i in range(4):
                    memory[ptr + index * 4 + i] = limbs[i]
                return


            def fill_elmts_at_index(
                x,
                ptr: object,
                memory: object,
                index: int,
            ):
                for i in range(len(x)):
                    fill_elmt_at_index(x[i], ptr + i * 4, memory, index)
                return

            rlc_sum_dlog_div_coeffs = RLCSumDlogDiv.a_num + RLCSumDlogDiv.a_den + RLCSumDlogDiv.b_num + RLCSumDlogDiv.b_den
            assert len(rlc_sum_dlog_div_coeffs) == 18 + 4*2, f"len(rlc_sum_dlog_div_coeffs) == {len(rlc_sum_dlog_div_coeffs)} != {18 + 4*2}"
            fill_elmts_at_index(rlc_sum_dlog_div_coeffs, ids.range_check96_ptr, memory, 4)

            fill_elmt_at_index(Q_low[0], ids.range_check96_ptr, memory, 50)
            fill_elmt_at_index(Q_low[1], ids.range_check96_ptr, memory, 51)
            fill_elmt_at_index(Q_high[0], ids.range_check96_ptr, memory, 52)
            fill_elmt_at_index(Q_high[1], ids.range_check96_ptr, memory, 53)
            fill_elmt_at_index(Q_high_shifted[0], ids.range_check96_ptr, memory, 54)
            fill_elmt_at_index(Q_high_shifted[1], ids.range_check96_ptr, memory, 55)


            print(f"Hashing Z = Poseidon(Input, Commitments) = Hash(Points, scalars, Q_low, Q_high, Q_high_shifted, SumDlogDivLow, SumDlogDivHigh, SumDlogDivShifted)...")
        %}

        let ecip_input: UInt384* = cast(range_check96_ptr, UInt384*);

        // Constants
        assert ecip_input[0] = UInt384(3, 0, 0, 0);
        assert ecip_input[1] = UInt384(0, 0, 0, 0);
        assert ecip_input[2] = UInt384(12528508628158887531275213211, 66632300, 0, 0);
        assert ecip_input[3] = UInt384(12528508628158887531275213211, 4361599596, 0, 0);

        // RLCSumDlogDiv 2points :  n_coeffs = 18 + 4 * 2 = 26 (filled by prover)

        // Generator point
        assert ecip_input[30] = UInt384(
            0x2dce28d959f2815b16f81798, 0x55a06295ce870b07029bfcdb, 0x79be667ef9dcbbac, 0x0
        );  // x_gen
        assert ecip_input[31] = UInt384(
            0xa68554199c47d08ffb10d4b8, 0x5da4fbfc0e1108a8fd17b448, 0x483ada7726a3c465, 0x0
        );  // y_gen

        assert ecip_input[32] = ep1_low_384;
        assert ecip_input[33] = en1_low_384;
        assert ecip_input[34] = sp1_low_384;
        assert ecip_input[35] = sn1_low_384;

        assert ecip_input[36] = ep1_high_384;
        assert ecip_input[37] = en1_high_384;
        assert ecip_input[38] = sp1_high_384;
        assert ecip_input[39] = sn1_high_384;

        // R point
        assert ecip_input[40] = r_point.x;
        assert ecip_input[41] = r_point.y;

        assert ecip_input[42] = ep2_low_384;
        assert ecip_input[43] = en2_low_384;
        assert ecip_input[44] = sp2_low_384;
        assert ecip_input[45] = sn2_low_384;

        assert ecip_input[46] = ep2_high_384;
        assert ecip_input[47] = en2_high_384;
        assert ecip_input[48] = sp2_high_384;
        assert ecip_input[49] = sn2_high_384;

        // Q_low / Q_high / Q_high_shifted (filled by prover) (50 - 55).
        // ...
        // Random point A0

        assert ecip_input[56] = UInt384(1, 0, 0, 0);
        assert ecip_input[57] = UInt384(0, 0, 0, 0);

        // a_weirstrass
        assert ecip_input[58] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);
        // base_rlc
        assert ecip_input[59] = UInt384(2, 0, 0, 0);

        // let (point1) = ec_mul(generator_point, u1);
        // let (minus_point1) = ec_negate(point1);
        // let (point2) = ec_mul([r_point], u2);
        // let (public_key_point) = ec_add(minus_point1, point2);
        // return (public_key_point=public_key_point, success=1);

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

        tempvar range_check96_ptr = range_check96_ptr + 224 + (4 + 117 + 108 - 1) * N_LIMBS;
        let add_mod_ptr = add_mod_ptr + 117 * ModBuiltin.SIZE;
        let mul_mod_ptr = mul_mod_ptr + 108 * ModBuiltin.SIZE;
        // Add Q_low and Q_high_shifted:
        let (res) = add_ec_points_secp256k1(
            G1Point(x=ecip_input[50], y=ecip_input[51]), G1Point(x=ecip_input[54], y=ecip_input[55])
        );
        return (public_key_point=res, success=1);
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
            assert 1 = 0;
            return (success=0, address=0);
        }
        let modulus = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
        let (x_uint256) = uint384_to_uint256_mod_p(public_key_point.x, modulus);
        let (y_uint256) = uint384_to_uint256_mod_p(public_key_point.y, modulus);
        let address = Internals.public_key_point_to_eth_address(x=x_uint256, y=y_uint256);
        return (success=success, address=address);
    }
}

namespace Internals {
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
}

// Add two EC points. Doesn't check if the inputs are on curve nor if they are the point at infinity.
func add_ec_points_secp256k1{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(P: G1Point, Q: G1Point) -> (res: G1Point) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    let modulus = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
    let (same_x) = is_eq_mod_p(P.x, Q.x, modulus);

    if (same_x != 0) {
        let (opposite_y) = is_opposite_mod_p(P.y, Q.y, modulus);

        if (opposite_y != 0) {
            // P + (-P) = O (point at infinity)
            return (res=G1Point(UInt384(0, 0, 0, 0), UInt384(0, 0, 0, 0)));
        } else {
            // P = Q, so we need to double the point
            let (add_offsets, mul_offsets) = get_DOUBLE_EC_POINT_circuit();
            let input: UInt384* = cast(range_check96_ptr, UInt384*);
            assert input[0] = P.x;
            assert input[1] = P.y;
            assert input[2] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);

            run_modulo_circuit_basic(
                p=modulus,
                add_offsets_ptr=add_offsets,
                add_n=6,
                mul_offsets_ptr=mul_offsets,
                mul_n=3,
                input_len=4,
                n_assert_eq=2,
            );
            return (
                res=G1Point(
                    x=[cast(cast(input, felt*) + 44, UInt384*)],
                    y=[cast(cast(input, felt*) + 56, UInt384*)],
                ),
            );
        }
    } else {
        // P and Q have different x-coordinates, perform regular addition
        let (add_offsets, mul_offsets) = get_ADD_EC_POINT_circuit();
        let input: UInt384* = cast(range_check96_ptr, UInt384*);
        assert input[0] = P.x;
        assert input[1] = P.y;
        assert input[2] = Q.x;
        assert input[3] = Q.y;

        run_modulo_circuit_basic(
            p=modulus,
            add_offsets_ptr=add_offsets,
            add_n=6,
            mul_offsets_ptr=mul_offsets,
            mul_n=3,
            input_len=4,
            n_assert_eq=2,
        );
        return (
            res=G1Point(
                x=[cast(cast(input, felt*) + 36, UInt384*)],
                y=[cast(cast(input, felt*) + 48, UInt384*)],
            ),
        );
    }
}
