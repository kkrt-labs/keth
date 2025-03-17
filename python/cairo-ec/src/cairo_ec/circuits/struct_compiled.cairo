from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.common.modulo import run_mod_p_circuit
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

struct Point {
    x: UInt384*,
    y: UInt384*,
}

struct ReturnPoint {
    p1: Point,
    p2: UInt384*,
}

func return_tuple_same_struct_params{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(pt: Point*, q: Point*, p: UInt384*) -> (Point*, UInt384*, ReturnPoint*) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 2;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    assert [range_check96_ptr + 4] = 0;
    assert [range_check96_ptr + 5] = 0;
    assert [range_check96_ptr + 6] = 0;
    assert [range_check96_ptr + 7] = 0;

    assert [range_check96_ptr + 8] = pt.x.d0;
    assert [range_check96_ptr + 9] = pt.x.d1;
    assert [range_check96_ptr + 10] = pt.x.d2;
    assert [range_check96_ptr + 11] = pt.x.d3;
    assert [range_check96_ptr + 12] = pt.y.d0;
    assert [range_check96_ptr + 13] = pt.y.d1;
    assert [range_check96_ptr + 14] = pt.y.d2;
    assert [range_check96_ptr + 15] = pt.y.d3;
    assert [range_check96_ptr + 16] = q.x.d0;
    assert [range_check96_ptr + 17] = q.x.d1;
    assert [range_check96_ptr + 18] = q.x.d2;
    assert [range_check96_ptr + 19] = q.x.d3;
    assert [range_check96_ptr + 20] = q.y.d0;
    assert [range_check96_ptr + 21] = q.y.d1;
    assert [range_check96_ptr + 22] = q.y.d2;
    assert [range_check96_ptr + 23] = q.y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=12,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=3,
    );

    let range_check96_ptr = range_check96_ptr + 76;

    return (
        cast(range_check96_ptr - 24, Point*),
        cast(range_check96_ptr - 12, UInt384*),
        cast(range_check96_ptr - 8, ReturnPoint*),
    );

    add_offsets:
    dw 16;
    dw 4;
    dw 12;
    dw 20;
    dw 0;
    dw 8;
    dw 32;
    dw 0;
    dw 28;
    dw 36;
    dw 8;
    dw 32;
    dw 40;
    dw 36;
    dw 0;
    dw 48;
    dw 4;
    dw 44;
    dw 4;
    dw 36;
    dw 52;
    dw 4;
    dw 48;
    dw 56;
    dw 4;
    dw 0;
    dw 60;
    dw 4;
    dw 36;
    dw 64;
    dw 4;
    dw 48;
    dw 68;
    dw 4;
    dw 36;
    dw 72;

    mul_offsets:
    dw 24;
    dw 20;
    dw 16;
    dw 24;
    dw 24;
    dw 28;
    dw 24;
    dw 40;
    dw 44;
}

func return_single_same_struct_params{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(pt: Point*, q: Point*, p: UInt384*) -> Point* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = pt.x.d0;
    assert [range_check96_ptr + 5] = pt.x.d1;
    assert [range_check96_ptr + 6] = pt.x.d2;
    assert [range_check96_ptr + 7] = pt.x.d3;
    assert [range_check96_ptr + 8] = pt.y.d0;
    assert [range_check96_ptr + 9] = pt.y.d1;
    assert [range_check96_ptr + 10] = pt.y.d2;
    assert [range_check96_ptr + 11] = pt.y.d3;
    assert [range_check96_ptr + 12] = q.x.d0;
    assert [range_check96_ptr + 13] = q.x.d1;
    assert [range_check96_ptr + 14] = q.x.d2;
    assert [range_check96_ptr + 15] = q.x.d3;
    assert [range_check96_ptr + 16] = q.y.d0;
    assert [range_check96_ptr + 17] = q.y.d1;
    assert [range_check96_ptr + 18] = q.y.d2;
    assert [range_check96_ptr + 19] = q.y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=8,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=3,
    );

    let range_check96_ptr = range_check96_ptr + 60;

    return cast(range_check96_ptr - 8, Point*);

    add_offsets:
    dw 16;
    dw 4;
    dw 12;
    dw 20;
    dw 0;
    dw 8;
    dw 32;
    dw 0;
    dw 28;
    dw 36;
    dw 8;
    dw 32;
    dw 40;
    dw 36;
    dw 0;
    dw 48;
    dw 4;
    dw 44;
    dw 4;
    dw 36;
    dw 52;
    dw 4;
    dw 48;
    dw 56;

    mul_offsets:
    dw 24;
    dw 20;
    dw 16;
    dw 24;
    dw 24;
    dw 28;
    dw 24;
    dw 40;
    dw 44;
}

func return_single_nested_struct_params{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(pt: Point*, q: Point*, p: UInt384*) -> ReturnPoint* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = pt.x.d0;
    assert [range_check96_ptr + 5] = pt.x.d1;
    assert [range_check96_ptr + 6] = pt.x.d2;
    assert [range_check96_ptr + 7] = pt.x.d3;
    assert [range_check96_ptr + 8] = pt.y.d0;
    assert [range_check96_ptr + 9] = pt.y.d1;
    assert [range_check96_ptr + 10] = pt.y.d2;
    assert [range_check96_ptr + 11] = pt.y.d3;
    assert [range_check96_ptr + 12] = q.x.d0;
    assert [range_check96_ptr + 13] = q.x.d1;
    assert [range_check96_ptr + 14] = q.x.d2;
    assert [range_check96_ptr + 15] = q.x.d3;
    assert [range_check96_ptr + 16] = q.y.d0;
    assert [range_check96_ptr + 17] = q.y.d1;
    assert [range_check96_ptr + 18] = q.y.d2;
    assert [range_check96_ptr + 19] = q.y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=9,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=3,
    );

    let range_check96_ptr = range_check96_ptr + 64;

    return cast(range_check96_ptr - 12, ReturnPoint*);

    add_offsets:
    dw 16;
    dw 4;
    dw 12;
    dw 20;
    dw 0;
    dw 8;
    dw 32;
    dw 0;
    dw 28;
    dw 36;
    dw 8;
    dw 32;
    dw 40;
    dw 36;
    dw 0;
    dw 48;
    dw 4;
    dw 44;
    dw 4;
    dw 36;
    dw 52;
    dw 4;
    dw 48;
    dw 56;
    dw 4;
    dw 36;
    dw 60;

    mul_offsets:
    dw 24;
    dw 20;
    dw 16;
    dw 24;
    dw 24;
    dw 28;
    dw 24;
    dw 40;
    dw 44;
}

func ec_add_struct{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    pt: Point*, q: Point*, p: UInt384*
) -> Point* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;

    assert [range_check96_ptr + 4] = pt.x.d0;
    assert [range_check96_ptr + 5] = pt.x.d1;
    assert [range_check96_ptr + 6] = pt.x.d2;
    assert [range_check96_ptr + 7] = pt.x.d3;
    assert [range_check96_ptr + 8] = pt.y.d0;
    assert [range_check96_ptr + 9] = pt.y.d1;
    assert [range_check96_ptr + 10] = pt.y.d2;
    assert [range_check96_ptr + 11] = pt.y.d3;
    assert [range_check96_ptr + 12] = q.x.d0;
    assert [range_check96_ptr + 13] = q.x.d1;
    assert [range_check96_ptr + 14] = q.x.d2;
    assert [range_check96_ptr + 15] = q.x.d3;
    assert [range_check96_ptr + 16] = q.y.d0;
    assert [range_check96_ptr + 17] = q.y.d1;
    assert [range_check96_ptr + 18] = q.y.d2;
    assert [range_check96_ptr + 19] = q.y.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=8,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=3,
    );

    let range_check96_ptr = range_check96_ptr + 60;

    return cast(range_check96_ptr - 8, Point*);

    add_offsets:
    dw 16;
    dw 4;
    dw 12;
    dw 20;
    dw 0;
    dw 8;
    dw 32;
    dw 0;
    dw 28;
    dw 36;
    dw 8;
    dw 32;
    dw 40;
    dw 36;
    dw 0;
    dw 48;
    dw 4;
    dw 44;
    dw 4;
    dw 36;
    dw 52;
    dw 4;
    dw 48;
    dw 56;

    mul_offsets:
    dw 24;
    dw 20;
    dw 16;
    dw 24;
    dw 24;
    dw 28;
    dw 24;
    dw 40;
    dw 44;
}
