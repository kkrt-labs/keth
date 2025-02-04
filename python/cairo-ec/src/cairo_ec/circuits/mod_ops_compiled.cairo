from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.common.modulo import run_mod_p_circuit
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

func add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 0;
    dw 4;
    dw 8;

    mul_offsets:
}

func sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 8;
    dw 4;
    dw 0;

    mul_offsets:
}

func mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=0,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:

    mul_offsets:
    dw 0;
    dw 4;
    dw 8;
}

func div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=0,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:

    mul_offsets:
    dw 8;
    dw 4;
    dw 0;
}

func diff_ratio{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 20;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 8;
    dw 4;
    dw 0;
    dw 12;
    dw 4;
    dw 0;

    mul_offsets:
    dw 16;
    dw 12;
    dw 8;
}

func sum_ratio{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 20;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 0;
    dw 4;
    dw 8;
    dw 0;
    dw 4;
    dw 12;

    mul_offsets:
    dw 16;
    dw 12;
    dw 8;
}

func inv{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 1;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    assert [range_check96_ptr + 4] = 0;
    assert [range_check96_ptr + 5] = 0;
    assert [range_check96_ptr + 6] = 0;
    assert [range_check96_ptr + 7] = 0;

    assert [range_check96_ptr + 8] = x.d0;
    assert [range_check96_ptr + 9] = x.d1;
    assert [range_check96_ptr + 10] = x.d2;
    assert [range_check96_ptr + 11] = x.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 20;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 4;
    dw 0;
    dw 12;

    mul_offsets:
    dw 16;
    dw 8;
    dw 12;
}
