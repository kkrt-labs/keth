from ethereum_types.bytes import (
    Bytes,
    Bytes8,
    BytesStruct,
    Bytes20,
    Bytes32,
    Bytes4,
    ListBytes4,
    ListBytes4Struct,
)
from ethereum_types.numeric import bool
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_equal, split_int
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from src.utils.bytes import (
    felt_to_bytes20_little,
    uint256_to_bytes_little,
    uint256_to_bytes32_little,
)
from cairo_core.maths import unsigned_div_rem, felt252_to_bytes
from cairo_core.comparison import is_zero

func Bytes__eq__(_self: Bytes, other: Bytes) -> bool {
    if (_self.value.len != other.value.len) {
        tempvar res = bool(0);
        return res;
    }

    // Case diff: we can let the prover do the work of iterating over the bytes,
    // return the first different byte index, and assert in cairo that the a[index] != b[index]
    tempvar is_diff;
    tempvar diff_index;
    %{ Bytes__eq__ %}

    if (is_diff == 1) {
        // Assert that the bytes are different at the first different index
        with_attr error_message("Bytes__eq__: bytes at provided index are equal") {
            assert_not_equal(_self.value.data[diff_index], other.value.data[diff_index]);
        }
        tempvar res = bool(0);
        return res;
    }

    // Case equal: we need to iterate over all keys in cairo, because the prover might not have been honest
    // about the first different byte index.
    tempvar i = 0;

    loop:
    let index = [ap - 1];
    let self_value = cast([fp - 4], BytesStruct*);
    let other_value = cast([fp - 3], BytesStruct*);

    let is_end = is_zero(index - self_value.len);
    tempvar res = bool(1);
    jmp end if is_end != 0;

    let is_eq = is_zero(self_value.data[index] - other_value.data[index]);

    tempvar i = i + 1;
    jmp loop if is_eq != 0;
    tempvar res = bool(0);

    end:
    let res = bool([ap - 1]);
    return res;
}

// @notice Packs the input bytes 4-by-4, big-endian.
// @dev Expects the input len to be a multiple of 4.
func Bytes_to_be_ListBytes4{range_check_ptr}(input: Bytes) -> ListBytes4 {
    alloc_locals;
    let (local output_start: Bytes4*) = alloc();
    if (input.value.len == 0) {
        tempvar res = ListBytes4(new ListBytes4Struct(output_start, 0));
        return res;
    }

    let (local output_len, r) = unsigned_div_rem(input.value.len, 4);
    local range_check_ptr = range_check_ptr;
    with_attr error_message("IndexError") {
        assert r = 0;
    }

    tempvar input_ptr = input.value.data;
    tempvar idx = 0;
    ap += 4;

    loop:
    let input_ptr = cast([ap - 6], felt*);
    let idx = [ap - 5];

    tempvar current = input_ptr[0] + input_ptr[1] * 2 ** 8 + input_ptr[2] * 2 ** 16 + input_ptr[2] *
        2 ** 24 + input_ptr[3] * 2 ** 32;
    assert output_start[idx].value = current;

    tempvar input_ptr = input_ptr + 4;
    tempvar idx = idx + 1;
    let is_done = is_zero(output_len - idx);
    jmp end if is_done != 0;

    static_assert input_ptr == [ap - 6];
    static_assert idx == [ap - 5];
    jmp loop;

    end:
    tempvar res = ListBytes4(new ListBytes4Struct(output_start, output_len));
    return res;
}

func ListBytes4_be_to_bytes{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    src: ListBytes4
) -> Bytes {
    alloc_locals;

    let (local buffer: felt*) = alloc();
    if (src.value.len == 0) {
        tempvar res = Bytes(new BytesStruct(data=buffer, len=0));
        return res;
    }

    let res = _ListBytes4_be_to_bytes_inner{src=src, output_start=buffer}(0);
    return res;
}

func _ListBytes4_be_to_bytes_inner{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, src: ListBytes4, output_start: felt*
}(idx: felt) -> Bytes {
    if (idx == src.value.len) {
        tempvar res = Bytes(new BytesStruct(data=output_start, len=src.value.len * 4));
        return res;
    }
    felt252_to_bytes(src.value.data[idx].value, 4, output_start + idx * 4);
    return _ListBytes4_be_to_bytes_inner(idx + 1);
}

func Bytes20_to_Bytes{range_check_ptr}(src: Bytes20) -> Bytes {
    alloc_locals;
    let (buffer: felt*) = alloc();
    felt_to_bytes20_little(buffer, src.value);

    tempvar res = Bytes(new BytesStruct(data=buffer, len=20));
    return res;
}

func Bytes32_to_Bytes{range_check_ptr}(src: Bytes32) -> Bytes {
    alloc_locals;
    let (buffer: felt*) = alloc();
    uint256_to_bytes32_little(buffer, [src.value]);

    tempvar res = Bytes(new BytesStruct(data=buffer, len=32));
    return res;
}

func Bytes8_to_Bytes{range_check_ptr}(src: Bytes8) -> Bytes {
    alloc_locals;
    let (buffer: felt*) = alloc();

    // Split the felt into 8 bytes, little endian
    split_int(src.value, 8, 256, 256, buffer);

    tempvar res = Bytes(new BytesStruct(data=buffer, len=8));
    return res;
}
