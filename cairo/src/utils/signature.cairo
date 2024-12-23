from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    UInt384,
    PoseidonBuiltin,
)
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.cairo_secp.bigint3 import BigInt3
from starkware.cairo.common.cairo_secp.ec_point import EcPoint
from starkware.cairo.common.cairo_secp.signature import (
    validate_signature_entry,
    try_get_point_from_x,
    get_generator_point,
    div_mod_n,
)
from ethereum.utils.numeric import divmod

from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.cairo_secp.bigint import bigint_to_uint256, uint256_to_bigint
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.cairo_secp.ec import ec_add, ec_mul, ec_negate
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from src.utils.maths import unsigned_div_rem

from src.interfaces.interfaces import ICairo1Helpers

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

const N_LIMBS = 4;
// Input must be a valid Uint256.
func uint256_to_uint384{range_check_ptr}(a: Uint256) -> (res: UInt384) {
    let (high_64_high, high_64_low) = divmod(a.high, POW_2_64);
    let (low_32_high, low_96_low) = divmod(a.low, POW_2_96);
    return (res=UInt384(low_96_low, low_32_high + POW_2_32 * high_64_low, high_64_high, 0));
}

// Assume the input is valid UInt384 (will be the case if coming from ModuloBuiltin)
func uint384_to_uint256_mod_secp256k1{range_check_ptr}(a: UInt384) -> (res: Uint256) {
    // First force the prover to have filled a fully reduced field element < P.
    assert a.d3 = 0;
    assert [range_check_ptr] = secp256k1.P2 - a.d2;  // a.d2 <= secp256k1.P2
    tempvar range_check_ptr = range_check_ptr + 1;

    if (a.d2 == secp256k1.P2) {
        if (a.d1 == secp256k1.P1) {
            assert [range_check_ptr] = secp256k1.P0 - 1 - a.d0;
            tempvar range_check_ptr = range_check_ptr + 1;
        }
        assert [range_check_ptr] = secp256k1.P1 - 1 - a.d1;
        tempvar range_check_ptr = range_check_ptr + 1;
    }
    // Then decompose and rebuild uint256
    let (d1_high_64, d1_low_32) = divmod(a.d1, 2 ** 32);
    // a.d2 is guaranteed to be in 64 bits since we know it's fully reduced.
    return (res=Uint256(low=a.d0 + 2 ** 96 * d1_low_32, high=d1_high_64 + 2 ** 64 * a.d2));
}

func try_get_point_from_x_secp256k1{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(x: Uint256, v: felt, res: G1Point*) -> (is_on_curve: felt) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();
    let (constants_ptr: felt*) = get_label_location(constants_ptr_loc);
    let (add_offsets_ptr: felt*) = get_label_location(add_offsets_ptr_loc);
    let (mul_offsets_ptr: felt*) = get_label_location(mul_offsets_ptr_loc);
    let constants_ptr_len = 2;
    let input_len = 24;
    let add_mod_n = 5;
    let mul_mod_n = 7;
    let n_assert_eq = 1;

    local rhs_from_x_is_a_square_residue: felt;
    %{
        from starkware.python.math_utils import is_quad_residue
        from garaga.definitions import CURVES
        a = CURVES[ids.curve_id].a
        b = CURVES[ids.curve_id].b
        p = CURVES[ids.curve_id].p
        rhs = (ids.entropy**3 + a*ids.entropy + b) % p
        ids.rhs_from_x_is_a_square_residue = is_quad_residue(rhs, p)
    %}
    let (x_384: UInt384) = uint256_to_uint384(x);

    let (P: UInt384) = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);

    let (input: UInt384*) = cast(range_check96_ptr, UInt384*);

    assert input[0] = UInt384(1, 0, 0, 0);
    assert input[1] = UInt384(0, 0, 0, 0);
    assert input[2] = x_384;
    assert input[3] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);
    assert input[4] = UInt384(secp256k1.B0, secp256k1.B1, secp256k1.B2, secp256k1.B3);
    assert input[5] = UInt384(secp256k1.G0, secp256k1.G1, secp256k1.G2, secp256k1.G3);

    if (rhs_from_x_is_a_square_residue != 0) {
        assert input[6] = UInt384(1, 0, 0, 0);
    } else {
        assert input[6] = UInt384(0, 0, 0, 0);
    }

    assert add_mod_ptr[0] = ModBuiltin(
        p=P, values_ptr=input, offsets_ptr=add_offsets_ptr, n=add_mod_n
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=P, values_ptr=input, offsets_ptr=mul_offsets_ptr, n=mul_mod_n
    );

    tempvar range_check96_ptr = range_check96_ptr + input_len + (
        constants_ptr_len + add_mod_n + mul_mod_n - n_assert_eq
    ) * N_LIMBS;

    if (rhs_from_x_is_a_square_residue != 0) {
        return (is_on_curve=1);
    } else {
        return (is_on_curve=0);
    }

    constants_ptr_loc:
    dw 1;
    dw 0;
    dw 0;
    dw 0;
    dw 0;
    dw 0;
    dw 0;
    dw 0;

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
    func verify_eth_signature_uint256{
        range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
    }(msg_hash: Uint256, r: Uint256, s: Uint256, y_parity: felt, eth_address: felt) {
        alloc_locals;
        let (msg_hash_bigint: BigInt3) = uint256_to_bigint(msg_hash);
        let (r_bigint: BigInt3) = uint256_to_bigint(r);
        let (s_bigint: BigInt3) = uint256_to_bigint(s);

        with_attr error_message("Signature out of range.") {
            validate_signature_entry(r_bigint);
            validate_signature_entry(s_bigint);
        }

        with_attr error_message("Invalid y_parity") {
            assert (1 - y_parity) * y_parity = 0;
        }

        with_attr error_message("Invalid signature.") {
            let (success, recovered_address) = try_recover_eth_address(
                msg_hash=msg_hash_bigint, r=r_bigint, s=s_bigint, y_parity=y_parity
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
    func try_recover_public_key{range_check_ptr}(
        msg_hash: BigInt3, r: BigInt3, s: BigInt3, y_parity: felt
    ) -> (public_key_point: EcPoint, success: felt) {
        alloc_locals;
        let (local r_point: EcPoint*) = alloc();
        let (is_on_curve) = try_get_point_from_x(x=r, v=y_parity, result=r_point);
        if (is_on_curve == 0) {
            return (public_key_point=EcPoint(x=BigInt3(0, 0, 0), y=BigInt3(0, 0, 0)), success=0);
        }
        let (generator_point: EcPoint) = get_generator_point();
        // The result is given by
        //   -(msg_hash / r) * gen + (s / r) * r_point
        // where the division by r is modulo N.

        let (u1: BigInt3) = div_mod_n(msg_hash, r);
        let (u2: BigInt3) = div_mod_n(s, r);

        let (point1) = ec_mul(generator_point, u1);
        // We prefer negating the point over negating the scalar because negating mod SECP_P is
        // computationally easier than mod N.
        let (minus_point1) = ec_negate(point1);

        let (point2) = ec_mul([r_point], u2);

        let (public_key_point) = ec_add(minus_point1, point2);
        return (public_key_point=public_key_point, success=1);
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
        range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
    }(msg_hash: BigInt3, r: BigInt3, s: BigInt3, y_parity: felt) -> (success: felt, address: felt) {
        alloc_locals;
        let (public_key_point, success) = try_recover_public_key(
            msg_hash=msg_hash, r=r, s=s, y_parity=y_parity
        );
        if (success == 0) {
            return (success=0, address=0);
        }
        let (x_uint256) = bigint_to_uint256(public_key_point.x);
        let (y_uint256) = bigint_to_uint256(public_key_point.y);
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
