from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import bool
from ethereum.utils.numeric import is_zero
from starkware.cairo.common.math import assert_not_equal

func Bytes__eq__(_self: Bytes, other: Bytes) -> bool {
    if (_self.value.len != other.value.len) {
        tempvar res = bool(0);
        return res;
    }

    // Case diff: we can let the prover do the work of iterating over the bytes,
    // return the first different byte index, and assert in cairo that the a[index] != b[index]
    tempvar is_diff;
    tempvar diff_index;
    %{
        self_bytes = b''.join([memory[ids._self.value.data + i].to_bytes(1, "little") for i in range(ids._self.value.len)])
        other_bytes = b''.join([memory[ids.other.value.data + i].to_bytes(1, "little") for i in range(ids.other.value.len)])
        diff_index = next((i for i, (b_self, b_other) in enumerate(zip(self_bytes, other_bytes)) if b_self != b_other), None)
        if diff_index is not None:
            ids.is_diff = 1
            ids.diff_index = diff_index
        else:
            # No differences found in common prefix. Lengths were checked before
            ids.is_diff = 0
            ids.diff_index = 0
    %}

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
