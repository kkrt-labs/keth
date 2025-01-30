from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    HashBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from ethereum_types.bytes import Bytes, Bytes32, BytesStruct
from ethereum.cancun.fork_types import Address, Address_from_felt
from cairo_ec.curve.secp256k1 import (
    try_recover_public_key,
    secp256k1,
    public_key_point_to_eth_address as _public_key_point_to_eth_address,
)
from cairo_ec.uint384 import uint256_to_uint384, uint384_to_uint256
from cairo_core.maths import assert_uint256_le
from ethereum_types.numeric import U256, U256Struct
from ethereum.crypto.hash import Hash32

// @notice Recovers the public key from a given signature.
// @param r The r value of the signature.
// @param s The s value of the signature.
// @param v The v value of the signature.
// @param msg_hash Hash of the message being recovered.
// @return x, y The recovered public key points in U256 format to simplify subsequent cairo hashing.
func secp256k1_recover_uint256_bigends{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(r: U256, s: U256, v: U256, msg_hash: Hash32) -> (x: U256, y: U256) {
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

    let (public_key_point, success) = try_recover_public_key(
        msg_hash=msg_hash_uint384, r=r_uint384, s=s_uint384, y_parity=y_parity
    );

    with_attr error_message("ValueError") {
        assert success = 1;
    }

    let max_value = Uint256(secp256k1.P_LOW_128 - 1, secp256k1.P_HIGH_128);
    let x_uint256 = uint384_to_uint256(public_key_point.x);
    assert_uint256_le(x_uint256, max_value);
    let y_uint256 = uint384_to_uint256(public_key_point.y);
    assert_uint256_le(y_uint256, max_value);

    tempvar x = U256(new U256Struct(x_uint256.low, x_uint256.high));
    tempvar y = U256(new U256Struct(y_uint256.low, y_uint256.high));
    return (x=x, y=y);
}

func public_key_point_to_eth_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(x: U256, y: U256) -> Address {
    let eth_address_felt = _public_key_point_to_eth_address(x=[x.value], y=[y.value]);

    let eth_address = Address_from_felt(eth_address_felt);

    return eth_address;
}
