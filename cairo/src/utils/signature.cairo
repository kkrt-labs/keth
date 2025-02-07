from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    UInt384,
    PoseidonBuiltin,
)
from starkware.cairo.common.poseidon_state import PoseidonBuiltinState

from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from cairo_core.maths import unsigned_div_rem, assert_uint256_le
from cairo_ec.uint384 import uint384_to_uint256, uint256_to_uint384
from cairo_ec.curve.secp256k1 import (
    secp256k1,
    try_recover_public_key,
    public_key_point_to_eth_address_be,
)

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
        let address = public_key_point_to_eth_address_be(x=x_uint256, y=y_uint256);
        return (success=success, address=address);
    }
}
