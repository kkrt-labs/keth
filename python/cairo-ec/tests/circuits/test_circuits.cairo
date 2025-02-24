from starkware.cairo.common.cairo_builtins import ModBuiltin, UInt384
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.modulo import run_mod_p_circuit

from cairo_ec.circuits.mod_ops import (
    add,
    sub,
    mul,
    div,
    diff_ratio,
    sum_ratio,
    inv,
    assert_is_quad_residue,
)
from cairo_ec.circuits.mod_ops_compiled import (
    add as add_compiled,
    sub as sub_compiled,
    mul as mul_compiled,
    div as div_compiled,
    diff_ratio as diff_ratio_compiled,
    sum_ratio as sum_ratio_compiled,
    inv as inv_compiled,
    assert_is_quad_residue as assert_is_quad_residue_compiled,
)
from cairo_ec.circuits.ec_ops import ec_add, ec_double, assert_is_on_curve, assert_not_on_curve
from cairo_ec.circuits.ec_ops_compiled import (
    ec_add as ec_add_compiled,
    ec_double as ec_double_compiled,
    assert_is_on_curve as assert_is_on_curve_compiled,
    assert_not_on_curve as assert_not_on_curve_compiled,
)

func test__circuit{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    values_ptr: felt*,
    values_ptr_len: felt,
    p: UInt384*,
    add_mod_offsets_ptr: felt*,
    add_mod_n: felt,
    mul_mod_offsets_ptr: felt*,
    mul_mod_n: felt,
    total_offset: felt,
) -> felt* {
    alloc_locals;

    memcpy(range_check96_ptr, values_ptr, values_ptr_len);
    local range_check96_ptr_end: felt* = range_check96_ptr + total_offset;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=add_mod_n,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=mul_mod_n,
    );

    let range_check96_ptr = range_check96_ptr_end;

    return range_check96_ptr_end - total_offset;
}
