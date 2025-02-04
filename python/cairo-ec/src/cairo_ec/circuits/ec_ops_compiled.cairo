from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.common.modulo import run_mod_p_circuit
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

func ec_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x0: UInt384*, y0: UInt384*, x1: UInt384*, y1: UInt384*, p: UInt384*
) -> (UInt384*, UInt384*) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = x0.d0;
    assert [range_check96_ptr + 5] = x0.d1;
    assert [range_check96_ptr + 6] = x0.d2;
    assert [range_check96_ptr + 7] = x0.d3;
    assert [range_check96_ptr + 8] = y0.d0;
    assert [range_check96_ptr + 9] = y0.d1;
    assert [range_check96_ptr + 10] = y0.d2;
    assert [range_check96_ptr + 11] = y0.d3;
    assert [range_check96_ptr + 12] = x1.d0;
    assert [range_check96_ptr + 13] = x1.d1;
    assert [range_check96_ptr + 14] = x1.d2;
    assert [range_check96_ptr + 15] = x1.d3;
    assert [range_check96_ptr + 16] = y1.d0;
    assert [range_check96_ptr + 17] = y1.d1;
    assert [range_check96_ptr + 18] = y1.d2;
    assert [range_check96_ptr + 19] = y1.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=8,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=3,
    );

    let range_check96_ptr = range_check96_ptr + 64;

    return (cast(range_check96_ptr - 8, UInt384*), cast(range_check96_ptr - 4, UInt384*));

    add_offsets:
    dw 20;
    dw 8;
    dw 16;
    dw 24;
    dw 4;
    dw 12;
    dw 36;
    dw 4;
    dw 32;
    dw 40;
    dw 12;
    dw 36;
    dw 44;
    dw 40;
    dw 4;
    dw 52;
    dw 8;
    dw 48;
    dw 0;
    dw 40;
    dw 56;
    dw 0;
    dw 52;
    dw 60;

    mul_offsets:
    dw 28;
    dw 24;
    dw 20;
    dw 28;
    dw 28;
    dw 32;
    dw 28;
    dw 44;
    dw 48;
}

func ec_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x0: UInt384*, y0: UInt384*, a: UInt384*, p: UInt384*
) -> (UInt384*, UInt384*) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 3;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    assert [range_check96_ptr + 4] = 2;
    assert [range_check96_ptr + 5] = 0;
    assert [range_check96_ptr + 6] = 0;
    assert [range_check96_ptr + 7] = 0;
    assert [range_check96_ptr + 8] = 0;
    assert [range_check96_ptr + 9] = 0;
    assert [range_check96_ptr + 10] = 0;
    assert [range_check96_ptr + 11] = 0;

    assert [range_check96_ptr + 12] = x0.d0;
    assert [range_check96_ptr + 13] = x0.d1;
    assert [range_check96_ptr + 14] = x0.d2;
    assert [range_check96_ptr + 15] = x0.d3;
    assert [range_check96_ptr + 16] = y0.d0;
    assert [range_check96_ptr + 17] = y0.d1;
    assert [range_check96_ptr + 18] = y0.d2;
    assert [range_check96_ptr + 19] = y0.d3;
    assert [range_check96_ptr + 20] = a.d0;
    assert [range_check96_ptr + 21] = a.d1;
    assert [range_check96_ptr + 22] = a.d2;
    assert [range_check96_ptr + 23] = a.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=9,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=6,
    );

    let range_check96_ptr = range_check96_ptr + 84;

    return (cast(range_check96_ptr - 8, UInt384*), cast(range_check96_ptr - 4, UInt384*));

    add_offsets:
    dw 8;
    dw 0;
    dw 24;
    dw 32;
    dw 20;
    dw 36;
    dw 8;
    dw 4;
    dw 40;
    dw 56;
    dw 12;
    dw 52;
    dw 60;
    dw 12;
    dw 56;
    dw 64;
    dw 60;
    dw 12;
    dw 72;
    dw 16;
    dw 68;
    dw 8;
    dw 60;
    dw 76;
    dw 8;
    dw 72;
    dw 80;

    mul_offsets:
    dw 24;
    dw 12;
    dw 28;
    dw 28;
    dw 12;
    dw 32;
    dw 40;
    dw 16;
    dw 44;
    dw 48;
    dw 44;
    dw 36;
    dw 48;
    dw 48;
    dw 52;
    dw 48;
    dw 64;
    dw 68;
}
