from ethereum_types.bytes import Bytes32, Bytes
from legacy.utils.bytes import bytes_to_bytes8_little_endian
from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

using Hash32 = Bytes32;

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
