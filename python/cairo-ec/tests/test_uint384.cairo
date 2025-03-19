from starkware.cairo.common.cairo_builtins import HashBuiltin, UInt384, ModBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from cairo_ec.uint384 import (
    uint384_assert_le,
    uint384_to_uint256,
    uint256_to_uint384,
    uint384_eq_mod_p,
    uint384_is_neg_mod_p,
    felt_to_uint384,
)

from cairo_core.numeric import U256, U384

func test__uint256_to_uint384{range_check_ptr}(a: U256) -> U384 {
    alloc_locals;
    let res_ = uint256_to_uint384([a.value]);
    tempvar res = U384(new res_);
    return res;
}

func test__uint384_to_uint256{range_check_ptr}(a: U384) -> U256 {
    alloc_locals;
    let res_ = uint384_to_uint256([a.value]);
    tempvar res = U256(new res_);
    return res;
}

func test__uint384_assert_le{range_check96_ptr: felt*}(a: U384, b: U384) {
    alloc_locals;
    uint384_assert_le([a.value], [b.value]);

    return ();
}

func test__uint384_eq_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: U384, y: U384, p: U384) -> felt {
    alloc_locals;
    let res = uint384_eq_mod_p([x.value], [y.value], [p.value]);
    return res;
}

func test__uint384_is_neg_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: U384, y: U384, p: U384) -> felt {
    alloc_locals;
    let res = uint384_is_neg_mod_p([x.value], [y.value], [p.value]);
    return res;
}

func test__felt_to_uint384{range_check96_ptr: felt*}(x: felt) -> U384 {
    alloc_locals;
    let res_ = felt_to_uint384(x);
    tempvar res = U384(new res_);
    return res;
}
