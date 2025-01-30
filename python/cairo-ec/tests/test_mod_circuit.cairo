from starkware.cairo.common.cairo_builtins import ModBuiltin, UInt384
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.modulo import run_mod_p_circuit

func test__simple_circuit(x: felt, y: felt) -> felt {
    tempvar sum = x + y;
    tempvar prod = x * y;

    return_label:
    return sum + prod;
}

func test__mod_builtin{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(
    x: UInt384*,
    y: UInt384*,
    p: UInt384*,
    add_mod_offsets_ptr: felt*,
    add_mod_n: felt,
    mul_mod_offsets_ptr: felt*,
    mul_mod_n: felt,
    offset: felt,
) -> felt* {
    alloc_locals;

    let values_ptr = range_check96_ptr;
    assert [values_ptr + 0] = x.d0;
    assert [values_ptr + 1] = x.d1;
    assert [values_ptr + 2] = x.d2;
    assert [values_ptr + 3] = x.d3;
    assert [values_ptr + 4] = y.d0;
    assert [values_ptr + 5] = y.d1;
    assert [values_ptr + 6] = y.d2;
    assert [values_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(values_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=add_mod_n,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=mul_mod_n,
    );

    let range_check96_ptr = values_ptr + offset;

    return values_ptr;
}
