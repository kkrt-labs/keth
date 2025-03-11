%builtins range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from legacy.utils.array import reverse, count_not_zero
from cairo_core.bytes import Bytes

func test__reverse(data: Bytes) -> felt* {
    alloc_locals;
    let (output) = alloc();
    reverse(output, data.value.len, data.value.data);
    return output;
}

func test__count_not_zero(data: Bytes) -> felt {
    let count = count_not_zero(data.value.len, data.value.data);
    return count;
}
