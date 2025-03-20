from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.common.modulo import run_mod_p_circuit
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from cairo_core.numeric import U384

func add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384, y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.value.d0;
    assert [range_check96_ptr + 1] = x.value.d1;
    assert [range_check96_ptr + 2] = x.value.d2;
    assert [range_check96_ptr + 3] = x.value.d3;
    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

    add_offsets:
    dw 0;
    dw 4;
    dw 8;

    mul_offsets:
}

func sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384, y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.value.d0;
    assert [range_check96_ptr + 1] = x.value.d1;
    assert [range_check96_ptr + 2] = x.value.d2;
    assert [range_check96_ptr + 3] = x.value.d3;
    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

    add_offsets:
    dw 8;
    dw 4;
    dw 0;

    mul_offsets:
}

func mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384, y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.value.d0;
    assert [range_check96_ptr + 1] = x.value.d1;
    assert [range_check96_ptr + 2] = x.value.d2;
    assert [range_check96_ptr + 3] = x.value.d3;
    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=0,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

    add_offsets:

    mul_offsets:
    dw 0;
    dw 4;
    dw 8;
}

func div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384, y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.value.d0;
    assert [range_check96_ptr + 1] = x.value.d1;
    assert [range_check96_ptr + 2] = x.value.d2;
    assert [range_check96_ptr + 3] = x.value.d3;
    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=0,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

    add_offsets:

    mul_offsets:
    dw 8;
    dw 4;
    dw 0;
}

func diff_ratio{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384, y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.value.d0;
    assert [range_check96_ptr + 1] = x.value.d1;
    assert [range_check96_ptr + 2] = x.value.d2;
    assert [range_check96_ptr + 3] = x.value.d3;
    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 20;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

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
    x: U384, y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = x.value.d0;
    assert [range_check96_ptr + 1] = x.value.d1;
    assert [range_check96_ptr + 2] = x.value.d2;
    assert [range_check96_ptr + 3] = x.value.d3;
    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 20;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

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
    x: U384, modulus: U384
) -> U384 {
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

    assert [range_check96_ptr + 8] = x.value.d0;
    assert [range_check96_ptr + 9] = x.value.d1;
    assert [range_check96_ptr + 10] = x.value.d2;
    assert [range_check96_ptr + 11] = x.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 20;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

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
}(x: U384, root: U384, g: U384, is_quad_residue: U384, modulus: U384) {
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

    assert [range_check96_ptr + 8] = x.value.d0;
    assert [range_check96_ptr + 9] = x.value.d1;
    assert [range_check96_ptr + 10] = x.value.d2;
    assert [range_check96_ptr + 11] = x.value.d3;
    assert [range_check96_ptr + 12] = root.value.d0;
    assert [range_check96_ptr + 13] = root.value.d1;
    assert [range_check96_ptr + 14] = root.value.d2;
    assert [range_check96_ptr + 15] = root.value.d3;
    assert [range_check96_ptr + 16] = g.value.d0;
    assert [range_check96_ptr + 17] = g.value.d1;
    assert [range_check96_ptr + 18] = g.value.d2;
    assert [range_check96_ptr + 19] = g.value.d3;
    assert [range_check96_ptr + 20] = is_quad_residue.value.d0;
    assert [range_check96_ptr + 21] = is_quad_residue.value.d1;
    assert [range_check96_ptr + 22] = is_quad_residue.value.d2;
    assert [range_check96_ptr + 23] = is_quad_residue.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=6,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=5,
    );

    let range_check96_ptr = range_check96_ptr + 60;

    tempvar res = ();
    return res;

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
    x: U384, y: U384, modulus: U384
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = x.value.d0;
    assert [range_check96_ptr + 5] = x.value.d1;
    assert [range_check96_ptr + 6] = x.value.d2;
    assert [range_check96_ptr + 7] = x.value.d3;
    assert [range_check96_ptr + 8] = y.value.d0;
    assert [range_check96_ptr + 9] = y.value.d1;
    assert [range_check96_ptr + 10] = y.value.d2;
    assert [range_check96_ptr + 11] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=1,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 12;

    tempvar res = ();
    return res;

    add_offsets:
    dw 0;
    dw 8;
    dw 4;

    mul_offsets:
}

func assert_neq{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: U384, y: U384, modulus: U384
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

    assert [range_check96_ptr + 8] = x.value.d0;
    assert [range_check96_ptr + 9] = x.value.d1;
    assert [range_check96_ptr + 10] = x.value.d2;
    assert [range_check96_ptr + 11] = x.value.d3;
    assert [range_check96_ptr + 12] = y.value.d0;
    assert [range_check96_ptr + 13] = y.value.d1;
    assert [range_check96_ptr + 14] = y.value.d2;
    assert [range_check96_ptr + 15] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 28;

    tempvar res = ();
    return res;

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
    y: U384, modulus: U384
) -> U384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = y.value.d0;
    assert [range_check96_ptr + 5] = y.value.d1;
    assert [range_check96_ptr + 6] = y.value.d2;
    assert [range_check96_ptr + 7] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 16;

    tempvar res = U384(cast(range_check96_ptr - 4, UInt384*));
    return res;

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
    x: U384, y: U384, modulus: U384
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = x.value.d0;
    assert [range_check96_ptr + 5] = x.value.d1;
    assert [range_check96_ptr + 6] = x.value.d2;
    assert [range_check96_ptr + 7] = x.value.d3;
    assert [range_check96_ptr + 8] = y.value.d0;
    assert [range_check96_ptr + 9] = y.value.d1;
    assert [range_check96_ptr + 10] = y.value.d2;
    assert [range_check96_ptr + 11] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=0,
    );

    let range_check96_ptr = range_check96_ptr + 16;

    tempvar res = ();
    return res;

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
    x: U384, y: U384, modulus: U384
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

    assert [range_check96_ptr + 8] = x.value.d0;
    assert [range_check96_ptr + 9] = x.value.d1;
    assert [range_check96_ptr + 10] = x.value.d2;
    assert [range_check96_ptr + 11] = x.value.d3;
    assert [range_check96_ptr + 12] = y.value.d0;
    assert [range_check96_ptr + 13] = y.value.d1;
    assert [range_check96_ptr + 14] = y.value.d2;
    assert [range_check96_ptr + 15] = y.value.d3;

    run_mod_p_circuit(
        p=[modulus.value],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=1,
    );

    let range_check96_ptr = range_check96_ptr + 28;

    tempvar res = ();
    return res;

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
