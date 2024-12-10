from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.cairo_secp.bigint3 import BigInt3
from starkware.cairo.common.cairo_secp.ec_point import EcPoint
from starkware.cairo.common.cairo_secp.signature import (
    validate_signature_entry,
    try_get_point_from_x,
    get_generator_point,
    div_mod_n,
)
from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.cairo_secp.bigint import bigint_to_uint256, uint256_to_bigint
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.cairo_secp.ec import ec_add, ec_mul, ec_negate
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from src.utils.maths import unsigned_div_rem

from src.interfaces.interfaces import ICairo1Helpers

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
