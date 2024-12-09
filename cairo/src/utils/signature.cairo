from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.cairo_secp.bigint3 import BigInt3, UnreducedBigInt3
from starkware.cairo.common.cairo_secp.ec_point import EcPoint
from starkware.cairo.common.cairo_secp.signature import (
    validate_signature_entry,
    try_get_point_from_x,
    get_generator_point,
    div_mod_n,
)
from starkware.cairo.common.cairo_secp.ec import ec_add, ec_mul, ec_negate
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_secp.bigint import uint256_to_bigint

from src.interfaces.interfaces import ICairo1Helpers

namespace Signature {
    // A version of verify_eth_signature, with that msg_hash, r and s as Uint256 and
    // using the Cairo1 helpers class.
    func verify_eth_signature_uint256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
        msg_hash: Uint256, r: Uint256, s: Uint256, y_parity: felt, eth_address: felt
    ) {
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
            let (success, recovered_address) = ICairo1Helpers.recover_eth_address(
                msg_hash=msg_hash, r=r, s=s, y_parity=y_parity
            );
            // TODO: uncomment when we have a working recover_eth_address
            // assert success = 1;
            // assert eth_address = recovered_address;
        }
        return ();
    }

    // Similar to `recover_public_key`, but handles the case where 'x' does not correspond to a point on the
    // curve gracefully.
    // Receives a signature and the signed message hash.
    // Returns the public key associated with the signer, represented as a point on the curve, and `true` if valid.
    // Returns the point (0, 0) and `false` otherwise.
    // Note:
    //   Some places use the values 27 and 28 instead of 0 and 1 for v.
    //   In that case, a subtraction by 27 returns a v that can be used by this function.
    // Prover assumptions:
    // * r is the x coordinate of some nonzero point on the curve.
    // * All the limbs of s and msg_hash are in the range (-2 ** 210.99, 2 ** 210.99).
    // * All the limbs of r are in the range (-2 ** 124.99, 2 ** 124.99).
    func try_recover_public_key{range_check_ptr}(
        msg_hash: BigInt3, r: BigInt3, s: BigInt3, v: felt
    ) -> (public_key_point: EcPoint, success: felt) {
        alloc_locals;
        let (local r_point: EcPoint*) = alloc();
        let (is_on_curve) = try_get_point_from_x(x=r, v=v, result=r_point);
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
}
