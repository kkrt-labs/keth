from starkware.cairo.common.cairo_builtins import HashBuiltin, UInt384, ModBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from cairo_ec.uint384 import (
    uint384_assert_le,
    uint384_to_uint256,
    uint256_to_uint384,
    uint384_assert_neq_mod_p,
    uint384_assert_eq_mod_p,
    uint384_eq_mod_p,
    uint384_assert_neg_mod_p,
    uint384_assert_not_neg_mod_p,
    uint384_is_neg_mod_p,
    uint384_div_mod_p,
    uint384_neg_mod_p,
    felt_to_uint384,
)

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

func test__uint384_assert_le{range_check96_ptr: felt*}() {
    alloc_locals;
    let (a_ptr) = alloc();
    let (b_ptr) = alloc();
    %{
        segments.write_arg(ids.a_ptr, program_input["a"])
        segments.write_arg(ids.b_ptr, program_input["b"])
    %}
    uint384_assert_le([cast(a_ptr, UInt384*)], [cast(b_ptr, UInt384*)]);

    return ();
}

func test__uint384_assert_eq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}() {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    uint384_assert_eq_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return ();
}

func test__uint384_assert_neq_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}() {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    uint384_assert_neq_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return ();
}

func test__uint384_eq_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}() -> felt {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    let res = uint384_eq_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return res;
}

func test__uint384_assert_neg_mod_p{
    range_check96_ptr: felt*, mul_mod_ptr: ModBuiltin*, add_mod_ptr: ModBuiltin*
}() {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    uint384_assert_neg_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return ();
}

func test__uint384_assert_not_neg_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}() {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    uint384_assert_not_neg_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return ();
}

func test__uint384_is_neg_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}() -> felt {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    let res = uint384_is_neg_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return res;
}

func test__uint384_div_mod_p{
    range_check96_ptr: felt*, mul_mod_ptr: ModBuiltin*, add_mod_ptr: ModBuiltin*
}() -> UInt384 {
    alloc_locals;
    let (x_ptr) = alloc();
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    let res = uint384_div_mod_p(
        [cast(x_ptr, UInt384*)], [cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]
    );
    return res;
}

func test__uint384_neg_mod_p{
    range_check96_ptr: felt*, mul_mod_ptr: ModBuiltin*, add_mod_ptr: ModBuiltin*
}() -> UInt384 {
    alloc_locals;
    let (y_ptr) = alloc();
    let (p_ptr) = alloc();
    %{
        segments.write_arg(ids.y_ptr, program_input["y"])
        segments.write_arg(ids.p_ptr, program_input["p"])
    %}
    let res = uint384_neg_mod_p([cast(y_ptr, UInt384*)], [cast(p_ptr, UInt384*)]);
    return res;
}

func test__felt_to_uint384{range_check96_ptr: felt*}() -> UInt384 {
    alloc_locals;
    tempvar x;
    %{ ids.x = program_input["x"] %}
    let res = felt_to_uint384(x);
    return res;
}
