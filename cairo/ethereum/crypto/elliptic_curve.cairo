from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, ModBuiltin, PoseidonBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from ethereum_types.bytes import Bytes32
from ethereum.prague.fork_types import Address
from cairo_ec.curve.secp256k1 import try_recover_public_key
from cairo_ec.uint384 import uint256_to_uint384
from ethereum_types.numeric import U256
from ethereum.crypto.hash import Hash32
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_keccak.keccak import cairo_keccak_uint256s
from cairo_core.maths import unsigned_div_rem
from ethereum.exceptions import EthereumException, InvalidSignatureError

// @notice Recovers the public key from a given signature.
// @param r The r value of the signature.
// @param s The s value of the signature.
// @param v The v value of the signature.
// @param msg_hash Hash of the message being recovered.
// @return x, y The recovered public key points in U256 format to simplify subsequent cairo hashing.
func secp256k1_recover{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(r: U256, s: U256, v: U256, msg_hash: Hash32) -> (
    public_key_x: Bytes32, public_key_y: Bytes32, error: EthereumException*
) {
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

    if (success != 1) {
        tempvar err = new EthereumException(InvalidSignatureError);
        return (public_key_point_x, public_key_point_y, err);
    }

    return (public_key_point_x, public_key_point_y, cast(0, EthereumException*));
}

// @notice Converts a public key point to the corresponding Ethereum address.
// @param x The x coordinate of the public key point.
// @param y The y coordinate of the public key point.
// @return The Ethereum address, interpreted as a 20-byte little-endian value.
func public_key_point_to_eth_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*
}(public_key_x: Bytes32, public_key_y: Bytes32) -> Address {
    alloc_locals;
    let (local elements: Uint256*) = alloc();
    assert elements[0] = [public_key_x.value];
    assert elements[1] = [public_key_y.value];
    let (point_hash: Uint256) = cairo_keccak_uint256s(n_elements=2, elements=elements);

    // The point_hash is a 32-byte value, in little endian, we want the 20 most significant bytes.
    let (low_high, _) = unsigned_div_rem(point_hash.low, 2 ** 96);
    let eth_address = low_high + 2 ** 32 * point_hash.high;
    tempvar res = Address(eth_address);
    return res;
}
