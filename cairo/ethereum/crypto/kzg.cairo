from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, UInt384
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.bitwise import bitwise_and
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.memcpy import memcpy
from ethereum_types.bytes import (
    Bytes,
    Bytes4,
    Bytes32,
    Bytes48,
    BytesStruct,
    ListBytes4,
    ListBytes4Struct,
)
from ethereum_types.numeric import U256, U256Struct, U384, bool
from ethereum.utils.bytes import ListBytes4_be_to_bytes, Bytes_to_be_ListBytes4
from ethereum.utils.numeric import (
    U256_from_be_bytes32,
    U256_le,
    U384_from_be_bytes,
    U384_to_be_bytes,
    U384_ZERO,
    U384__eq__,
    Bytes32_from_be_bytes,
)
from cairo_ec.curve.bls12_381 import bls12_381
from ethereum.crypto.bls12_381 import BLSF2, BLSF2Struct, BLSF2__eq__, BLSF2_ZERO
from cairo_core.numeric import OptionalU384
from cairo_core.hash.sha256 import sha256_be_output
from ethereum.cancun.fork_types import VersionedHash
from legacy.utils.array import reverse

using BLSScalar = U256;
using KZGCommitment = Bytes48;
const VERSIONED_HASH_VERSION_KZG = 0x01;

const GET_FLAGS_MASK = 2 ** 95 + 2 ** 94 + 2 ** 93;

func kzg_commitment_to_versioned_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    kzg_commitment: KZGCommitment
) -> VersionedHash {
    alloc_locals;

    // Convert KZG commitment to a big-endian bytes array
    let bytes_input = U384_to_be_bytes(U384(kzg_commitment.value), 48);
    let (local bytes_input_reversed: felt*) = alloc();
    reverse(bytes_input_reversed, 48, bytes_input.value.data);
    tempvar bytes_input_reversed_bytes = Bytes(new BytesStruct(data=bytes_input_reversed, len=48));

    // Convert the bytes array to a list of bytes4 to hash
    let list_bytes4_be_reverse = Bytes_to_be_ListBytes4(bytes_input_reversed_bytes);
    let hash = sha256_be_output(list_bytes4_be_reverse.value.data, 48);
    tempvar hash_bytes4 = ListBytes4(new ListBytes4Struct(cast(hash, Bytes4*), 8));
    let hash_bytes = ListBytes4_be_to_bytes(hash_bytes4);

    // Format the output
    let (local result_bytes: felt*) = alloc();
    assert result_bytes[0] = VERSIONED_HASH_VERSION_KZG;
    memcpy(result_bytes + 1, hash_bytes.value.data + 1, 31);
    tempvar bytes_result = Bytes(new BytesStruct(data=result_bytes, len=32));
    let versioned_hash = Bytes32_from_be_bytes(bytes_result);
    tempvar res = VersionedHash(versioned_hash.value);
    return res;
}

func bytes_to_bls_field{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes32) -> BLSScalar {
    let field_element = U256_from_be_bytes32(b);
    tempvar bls_modulus = U256(new U256Struct(low=bls12_381.N_LOW_128, high=bls12_381.N_HIGH_128));
    let is_valid = U256_le(field_element, bls_modulus);
    with_attr error_message("AssertionError") {
        assert is_valid.value = 1;
    }
    tempvar result = BLSScalar(field_element.value);
    return result;
}

// Diverge from specs: limited to 48 bytes
func os2ip{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes) -> U384 {
    let result = U384_from_be_bytes(b);
    return result;
}

// Extract all three most significant bits with one bitwise operation
// Since each limb of z is 96-bit long, the MSB is at position 95 in d3
func get_flags{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(z: U384) -> (bool, bool, bool) {
    let (flags_mask) = bitwise_and(z.value.d3, GET_FLAGS_MASK);
    let (c, remainder1) = unsigned_div_rem(flags_mask, 2 ** 95);
    let (b, remainder2) = unsigned_div_rem(remainder1, 2 ** 94);
    let (a, _) = unsigned_div_rem(remainder2, 2 ** 93);

    let c_flag = is_not_zero(c);
    let b_flag = is_not_zero(b);
    let a_flag = is_not_zero(a);
    return (bool(c_flag), bool(b_flag), bool(a_flag));
}

func is_point_at_infinity{range_check96_ptr: felt*}(z1: U384, z2: OptionalU384) -> bool {
    alloc_locals;

    let (u384_zero_ptr) = get_label_location(U384_ZERO);
    let u384_zero = U384(cast(u384_zero_ptr, UInt384*));
    if (z2.value != 0) {
        let is_z1_zero = U384__eq__(z1, u384_zero);
        let is_z2_zero = U384__eq__(U384(z2.value), u384_zero);
        let result = bool(is_z1_zero.value * is_z2_zero.value);
        return result;
    }
    let is_z1_zero = U384__eq__(z1, u384_zero);
    let result = bool(is_z1_zero.value);
    return result;
}
