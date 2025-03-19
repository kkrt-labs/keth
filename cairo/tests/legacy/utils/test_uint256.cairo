%builtins range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from cairo_core.numeric import U256

from legacy.utils.uint256 import uint256_add, uint256_sub

func test__uint256_add{range_check_ptr}(a: U256, b: U256) -> (felt, felt, felt) {
    let (res, carry) = uint256_add([a.value], [b.value]);

    return (res.low, res.high, carry);
}

func test__uint256_sub{range_check_ptr}(a: U256, b: U256) -> Uint256 {
    let (res) = uint256_sub([a.value], [b.value]);

    return res;
}
