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

func assert_is_quad_residue{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384*, root: UInt384*, g: UInt384*, is_quad_residue: UInt384*, p: UInt384*) {
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
    assert [range_check96_ptr + 12] = root.d0;
    assert [range_check96_ptr + 13] = root.d1;
    assert [range_check96_ptr + 14] = root.d2;
    assert [range_check96_ptr + 15] = root.d3;
    assert [range_check96_ptr + 16] = g.d0;
    assert [range_check96_ptr + 17] = g.d1;
    assert [range_check96_ptr + 18] = g.d2;
    assert [range_check96_ptr + 19] = g.d3;
    assert [range_check96_ptr + 20] = is_quad_residue.d0;
    assert [range_check96_ptr + 21] = is_quad_residue.d1;
    assert [range_check96_ptr + 22] = is_quad_residue.d2;
    assert [range_check96_ptr + 23] = is_quad_residue.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=6,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=5,
    );

    let range_check96_ptr = range_check96_ptr + 60;

    return ();

    add_offsets:
    dw 4;
    dw 0;
    dw 24;
    dw 28;
    dw 20;
    dw 24;
    dw 4;
    dw 4;
    dw 32;
    dw 4;
    dw 0;
    dw 44;
    dw 48;
    dw 20;
    dw 44;
    dw 36;
    dw 52;
    dw 56;

    mul_offsets:
    dw 20;
    dw 28;
    dw 32;
    dw 8;
    dw 20;
    dw 36;
    dw 16;
    dw 8;
    dw 40;
    dw 40;
    dw 48;
    dw 52;
    dw 12;
    dw 12;
    dw 56;
}

func assert_eq{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    return ();

    add_offsets:
    dw 0;
    dw 8;
    dw 4;

    mul_offsets:
}

func assert_neq{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) {
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
    assert [range_check96_ptr + 12] = y.d0;
    assert [range_check96_ptr + 13] = y.d1;
    assert [range_check96_ptr + 14] = y.d2;
    assert [range_check96_ptr + 15] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 28;

    return ();

    add_offsets:
    dw 4;
    dw 0;
    dw 16;
    dw 20;
    dw 12;
    dw 8;

    mul_offsets:
    dw 24;
    dw 20;
    dw 16;
}

func neg{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

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
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 16;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 0;
    dw 0;
    dw 8;
    dw 12;
    dw 4;
    dw 8;

    mul_offsets:
}

func assert_neg{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 16;

    return ();

    add_offsets:
    dw 0;
    dw 0;
    dw 12;
    dw 4;
    dw 8;
    dw 12;

    mul_offsets:
}

func assert_not_neg{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) {
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
    assert [range_check96_ptr + 12] = y.d0;
    assert [range_check96_ptr + 13] = y.d1;
    assert [range_check96_ptr + 14] = y.d2;
    assert [range_check96_ptr + 15] = y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 28;

    return ();

    add_offsets:
    dw 4;
    dw 0;
    dw 16;
    dw 8;
    dw 12;
    dw 20;

    mul_offsets:
    dw 24;
    dw 20;
    dw 16;
}
