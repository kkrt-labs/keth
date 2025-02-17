from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    HashBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from ethereum_types.bytes import Bytes, Bytes32, BytesStruct
from ethereum.cancun.fork_types import Address, Address_from_felt_be
from cairo_ec.curve.secp256k1 import try_recover_public_key, secp256k1
from cairo_ec.uint384 import uint256_to_uint384, uint384_to_uint256
from cairo_core.maths import assert_uint256_le
from ethereum_types.numeric import U256, U256Struct
from ethereum.crypto.hash import Hash32
from starkware.cairo.common.alloc import alloc
from ethereum.utils.numeric import U256_to_le_bytes
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s
from cairo_core.maths import unsigned_div_rem
from starkware.cairo.common.math_cmp import RC_BOUND

// @notice Recovers the public key from a given signature.
// @param r The r value of the signature.
// @param s The s value of the signature.
// @param v The v value of the signature.
// @param msg_hash Hash of the message being recovered.
// @return x, y The recovered public key points in U256 format to simplify subsequent cairo hashing.
func secp256k1_recover{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(r: U256, s: U256, v: U256, msg_hash: Hash32) -> (public_key_x: Bytes32, public_key_y: Bytes32) {
    alloc_locals;

    // reverse endianness of msg_hash since bytes are little endian in the codebase
    let (msg_hash_reversed) = uint256_reverse_endian([msg_hash.value]);

    // Convert inputs to UInt384 for try_recover_public_key
    let r_uint384 = uint256_to_uint384([r.value]);
    let s_uint384 = uint256_to_uint384([s.value]);
    // parameter `v` MUST be a `U256` with `low` value equal to y parity and high value equal to 0
    // see: <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/crypto/elliptic_curve.py#L49>
    let y_parity = v.value.low;
    let msg_hash_uint384 = uint256_to_uint384(msg_hash_reversed);

    let (public_key_point_x, public_key_point_y, success) = try_recover_public_key(
        msg_hash=msg_hash_uint384, r=r_uint384, s=s_uint384, y_parity=y_parity
    );

    with_attr error_message("ValueError") {
        assert success = 1;
    }

    return (public_key_point_x, public_key_point_y);
}

// @notice Converts a public key point to the corresponding Ethereum address.
// @param x The x coordinate of the public key point.
// @param y The y coordinate of the public key point.
// @return The Ethereum address, interpreted as a 20-byte big-endian value.
func public_key_point_to_eth_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(public_key_x: Bytes32, public_key_y: Bytes32) -> Address {
    alloc_locals;
    let (local elements: Uint256*) = alloc();
    assert elements[0] = [public_key_x.value];
    assert elements[1] = [public_key_y.value];
    let (point_hash: Uint256) = keccak_uint256s(n_elements=2, elements=elements);

    // The point_hash is a 32-byte value, in little endian, we want the 20 least significant bytes.
    let (high_low, _) = unsigned_div_rem(point_hash.high, 2 ** 96);
    let eth_address = point_hash.low + RC_BOUND * high_low;
    tempvar res = Address(eth_address);
    return res;
}
