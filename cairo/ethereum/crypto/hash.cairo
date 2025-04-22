from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_blake2s.blake2s import blake2s
from ethereum_types.numeric import bool
from ethereum_types.bytes import Bytes32, Bytes
from legacy.utils.bytes import bytes_to_bytes8_little_endian, bytes_to_bytes4_little_endian

using Hash32 = Bytes32;

EMPTY_ROOT_KECCAK:
dw 0x6ef8c092e64583ffa655cc1b171fe856;  // low
dw 0x21b463e3b52f6201c0ad6c991be0485b;  // high

EMPTY_HASH_KECCAK:
dw 0xc003c7dcb27d7e923c23f7860146d2c5;  // low
dw 0x70a4855d04d8fa7b3b2782ca53b600e5;  // high

// @notice Computes the keccak256 hash of a bytes object.
func keccak256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    buffer: Bytes
) -> Hash32 {
    alloc_locals;
    let (local dst: felt*) = alloc();
    bytes_to_bytes8_little_endian(dst, buffer.value.len, buffer.value.data);

    let (result) = keccak(dst, buffer.value.len);
    tempvar value = new Uint256(low=result.low, high=result.high);
    tempvar hash = Hash32(value=value);
    return hash;
}

// @notice Computes the blake2s hash of a bytes object.
// @dev `finalize_blake2s` must absolutely be called at the end of the program.
func blake2s_bytes{range_check_ptr, blake2s_ptr: felt*}(buffer: Bytes) -> Hash32 {
    alloc_locals;
    let n_bytes = buffer.value.len;
    let (dst: felt*) = alloc();
    bytes_to_bytes4_little_endian(dst, n_bytes, buffer.value.data);
    let (result) = blake2s(dst, n_bytes);
    tempvar value = new Uint256(low=result.low, high=result.high);
    tempvar hash = Hash32(value=value);
    return hash;
}

// @notice Computes the hash of a bytes object using the given hash function.
// @dev To avoid re-binding the arguments in the correct order, the `hash_function_name` must be the
// first implicit argument.
// @dev This function takes as implicit arguments all possible arguments for the hash_function_names used.
func hash_with{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, blake2s_ptr: felt*
}(buffer: Bytes, hash_function_name: felt) -> Hash32 {
    alloc_locals;
    let n_bytes = buffer.value.len;

    if (hash_function_name == 'blake2s') {
        let (dst: felt*) = alloc();
        bytes_to_bytes4_little_endian(dst, n_bytes, buffer.value.data);
        let (result) = blake2s(dst, n_bytes);
        tempvar value = new Uint256(low=result.low, high=result.high);
        tempvar hash = Hash32(value=value);
        return hash;
    }

    let (local dst: felt*) = alloc();
    bytes_to_bytes8_little_endian(dst, n_bytes, buffer.value.data);
    let (result) = keccak(dst, n_bytes);
    tempvar value = new Uint256(low=result.low, high=result.high);
    tempvar hash = Hash32(value=value);
    return hash;
}
