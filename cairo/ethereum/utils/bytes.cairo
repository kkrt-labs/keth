from ethereum_types.bytes import Bytes, BytesStruct, Bytes20, Bytes32
from ethereum_types.numeric import bool
from ethereum.utils.numeric import is_zero
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_equal
from src.utils.bytes import (
    felt_to_bytes20_little,
    uint256_to_bytes_little,
    uint256_to_bytes32_little,
)

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
