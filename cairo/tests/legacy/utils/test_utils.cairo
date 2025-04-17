%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256

from cairo_core.bytes import Bytes
from legacy.utils.utils import Helpers

func test__bytes_to_uint256{range_check_ptr}(word: Bytes) -> Uint256 {
    alloc_locals;

    let res = Helpers.bytes_to_uint256(word.value.len, word.value.data);

    return res;
}
