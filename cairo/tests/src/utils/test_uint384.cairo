from starkware.cairo.common.cairo_builtins import HashBuiltin, UInt384
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from src.utils.uint384 import assert_uint384_le, uint384_to_uint256, uint256_to_uint384

func test__uint256_to_uint384{range_check_ptr}() -> UInt384 {
    alloc_locals;
    let (a_ptr) = alloc();
    %{ segments.write_arg(ids.a_ptr, program_input["a"]) %}
    let res = uint256_to_uint384([cast(a_ptr, Uint256*)]);
    return res;
}

func test__uint384_to_uint256{range_check_ptr}() -> Uint256 {
    alloc_locals;
    let (a_ptr) = alloc();
    %{ segments.write_arg(ids.a_ptr, program_input["a"]) %}
    let res = uint384_to_uint256([cast(a_ptr, UInt384*)]);

    return res;
}

func test__assert_uint384_le{range_check96_ptr: felt*}() {
    alloc_locals;
    let (a_ptr) = alloc();
    let (b_ptr) = alloc();
    %{
        segments.write_arg(ids.a_ptr, program_input["a"])
        segments.write_arg(ids.b_ptr, program_input["b"])
    %}
    assert_uint384_le([cast(a_ptr, UInt384*)], [cast(b_ptr, UInt384*)]);

    return ();
}
