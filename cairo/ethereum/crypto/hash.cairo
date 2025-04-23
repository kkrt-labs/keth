from ethereum_types.bytes import Bytes32, Bytes
from legacy.utils.bytes import bytes_to_bytes8_little_endian
from starkware.cairo.common.cairo_keccak.keccak import cairo_keccak
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.builtin_keccak.keccak import keccak as keccak_builtin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from ethereum_types.numeric import bool
from starkware.cairo.common.registers import get_label_location

using Hash32 = Bytes32;

EMPTY_ROOT:
dw 0x6ef8c092e64583ffa655cc1b171fe856;  // low
dw 0x21b463e3b52f6201c0ad6c991be0485b;  // high

EMPTY_HASH:
dw 0xc003c7dcb27d7e923c23f7860146d2c5;  // low
dw 0x70a4855d04d8fa7b3b2782ca53b600e5;  // high

func keccak256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    buffer: Bytes
) -> Hash32 {
    alloc_locals;

    if (buffer.value.len == 0) {
        let (empty_hash) = get_label_location(EMPTY_HASH);
        let low = empty_hash[0];
        let high = empty_hash[1];
        tempvar value = new Uint256(low=low, high=high);
        tempvar hash = Hash32(value=value);
        return hash;
    }

    let (local dst: felt*) = alloc();
    bytes_to_bytes8_little_endian(dst, buffer.value.len, buffer.value.data);

    let (result) = cairo_keccak(dst, buffer.value.len);
    tempvar value = new Uint256(low=result.low, high=result.high);
    tempvar hash = Hash32(value=value);
    return hash;
}

func keccak256_builtin{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    buffer: Bytes
) -> Hash32 {
    alloc_locals;

    let (local dst: felt*) = alloc();
    bytes_to_bytes8_little_endian(dst, buffer.value.len, buffer.value.data);

    let (result) = keccak_builtin(dst, buffer.value.len);
    tempvar value = new Uint256(low=result.low, high=result.high);
    tempvar hash = Hash32(value=value);
    return hash;
}
