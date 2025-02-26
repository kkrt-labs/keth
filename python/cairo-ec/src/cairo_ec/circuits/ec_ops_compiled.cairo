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

func assert_x_is_on_curve{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(
    x: UInt384*,
    y: UInt384*,
    a: UInt384*,
    b: UInt384*,
    g: UInt384*,
    is_on_curve: UInt384*,
    p: UInt384*,
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
    assert [range_check96_ptr + 16] = a.d0;
    assert [range_check96_ptr + 17] = a.d1;
    assert [range_check96_ptr + 18] = a.d2;
    assert [range_check96_ptr + 19] = a.d3;
    assert [range_check96_ptr + 20] = b.d0;
    assert [range_check96_ptr + 21] = b.d1;
    assert [range_check96_ptr + 22] = b.d2;
    assert [range_check96_ptr + 23] = b.d3;
    assert [range_check96_ptr + 24] = g.d0;
    assert [range_check96_ptr + 25] = g.d1;
    assert [range_check96_ptr + 26] = g.d2;
    assert [range_check96_ptr + 27] = g.d3;
    assert [range_check96_ptr + 28] = is_on_curve.d0;
    assert [range_check96_ptr + 29] = is_on_curve.d1;
    assert [range_check96_ptr + 30] = is_on_curve.d2;
    assert [range_check96_ptr + 31] = is_on_curve.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=8,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=8,
    );

    let range_check96_ptr = range_check96_ptr + 88;

    return ();

    add_offsets:
    dw 4;
    dw 0;
    dw 32;
    dw 36;
    dw 28;
    dw 32;
    dw 4;
    dw 4;
    dw 40;
    dw 48;
    dw 52;
    dw 56;
    dw 56;
    dw 20;
    dw 60;
    dw 4;
    dw 0;
    dw 72;
    dw 76;
    dw 28;
    dw 72;
    dw 64;
    dw 80;
    dw 84;

    mul_offsets:
    dw 28;
    dw 36;
    dw 40;
    dw 8;
    dw 8;
    dw 44;
    dw 44;
    dw 8;
    dw 48;
    dw 16;
    dw 8;
    dw 52;
    dw 60;
    dw 28;
    dw 64;
    dw 24;
    dw 60;
    dw 68;
    dw 68;
    dw 76;
    dw 80;
    dw 12;
    dw 12;
    dw 84;
}

func assert_on_curve{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, a: UInt384*, b: UInt384*, p: UInt384*
) {
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
    assert [range_check96_ptr + 8] = a.d0;
    assert [range_check96_ptr + 9] = a.d1;
    assert [range_check96_ptr + 10] = a.d2;
    assert [range_check96_ptr + 11] = a.d3;
    assert [range_check96_ptr + 12] = b.d0;
    assert [range_check96_ptr + 13] = b.d1;
    assert [range_check96_ptr + 14] = b.d2;
    assert [range_check96_ptr + 15] = b.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=2,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=4,
    );

    let range_check96_ptr = range_check96_ptr + 36;

    return ();

    add_offsets:
    dw 20;
    dw 24;
    dw 28;
    dw 28;
    dw 12;
    dw 32;

    mul_offsets:
    dw 0;
    dw 0;
    dw 16;
    dw 16;
    dw 0;
    dw 20;
    dw 8;
    dw 0;
    dw 24;
    dw 4;
    dw 4;
    dw 32;
}

func assert_not_on_curve{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384*, y: UInt384*, a: UInt384*, b: UInt384*, p: UInt384*) -> UInt384* {
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
    assert [range_check96_ptr + 16] = a.d0;
    assert [range_check96_ptr + 17] = a.d1;
    assert [range_check96_ptr + 18] = a.d2;
    assert [range_check96_ptr + 19] = a.d3;
    assert [range_check96_ptr + 20] = b.d0;
    assert [range_check96_ptr + 21] = b.d1;
    assert [range_check96_ptr + 22] = b.d2;
    assert [range_check96_ptr + 23] = b.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=4,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=5,
    );

    let range_check96_ptr = range_check96_ptr + 60;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 28;
    dw 32;
    dw 36;
    dw 36;
    dw 20;
    dw 40;
    dw 4;
    dw 0;
    dw 44;
    dw 52;
    dw 40;
    dw 48;

    mul_offsets:
    dw 8;
    dw 8;
    dw 24;
    dw 24;
    dw 8;
    dw 28;
    dw 16;
    dw 8;
    dw 32;
    dw 12;
    dw 12;
    dw 48;
    dw 56;
    dw 52;
    dw 44;
}

func ecip_2p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    div_a_coeff_0: UInt384*,
    div_a_coeff_1: UInt384*,
    div_a_coeff_2: UInt384*,
    div_a_coeff_3: UInt384*,
    div_a_coeff_4: UInt384*,
    div_b_coeff_0: UInt384*,
    div_b_coeff_1: UInt384*,
    div_b_coeff_2: UInt384*,
    div_b_coeff_3: UInt384*,
    div_b_coeff_4: UInt384*,
    div_b_coeff_5: UInt384*,
    div_c_coeff_0: UInt384*,
    div_c_coeff_1: UInt384*,
    div_c_coeff_2: UInt384*,
    div_c_coeff_3: UInt384*,
    div_c_coeff_4: UInt384*,
    div_c_coeff_5: UInt384*,
    div_d_coeff_0: UInt384*,
    div_d_coeff_1: UInt384*,
    div_d_coeff_2: UInt384*,
    div_d_coeff_3: UInt384*,
    div_d_coeff_4: UInt384*,
    div_d_coeff_5: UInt384*,
    div_d_coeff_6: UInt384*,
    div_d_coeff_7: UInt384*,
    div_d_coeff_8: UInt384*,
    g_x: UInt384*,
    g_y: UInt384*,
    r_x: UInt384*,
    r_y: UInt384*,
    ep1_low: UInt384*,
    en1_low: UInt384*,
    sp1_low: UInt384*,
    sn1_low: UInt384*,
    ep2_low: UInt384*,
    en2_low: UInt384*,
    sp2_low: UInt384*,
    sn2_low: UInt384*,
    ep1_high: UInt384*,
    en1_high: UInt384*,
    sp1_high: UInt384*,
    sn1_high: UInt384*,
    ep2_high: UInt384*,
    en2_high: UInt384*,
    sp2_high: UInt384*,
    sn2_high: UInt384*,
    q_low_x: UInt384*,
    q_low_y: UInt384*,
    q_high_x: UInt384*,
    q_high_y: UInt384*,
    q_high_shifted_x: UInt384*,
    q_high_shifted_y: UInt384*,
    a0_x: UInt384*,
    a0_y: UInt384*,
    a: UInt384*,
    b: UInt384*,
    base_rlc: UInt384*,
    p: UInt384*,
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 12528508628158887531275213211;
    assert [range_check96_ptr + 1] = 4361599596;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    assert [range_check96_ptr + 4] = 12528508628158887531275213211;
    assert [range_check96_ptr + 5] = 66632300;
    assert [range_check96_ptr + 6] = 0;
    assert [range_check96_ptr + 7] = 0;
    assert [range_check96_ptr + 8] = 3;
    assert [range_check96_ptr + 9] = 0;
    assert [range_check96_ptr + 10] = 0;
    assert [range_check96_ptr + 11] = 0;
    assert [range_check96_ptr + 12] = 2;
    assert [range_check96_ptr + 13] = 0;
    assert [range_check96_ptr + 14] = 0;
    assert [range_check96_ptr + 15] = 0;
    assert [range_check96_ptr + 16] = 0;
    assert [range_check96_ptr + 17] = 0;
    assert [range_check96_ptr + 18] = 0;
    assert [range_check96_ptr + 19] = 0;

    assert [range_check96_ptr + 20] = div_a_coeff_0.d0;
    assert [range_check96_ptr + 21] = div_a_coeff_0.d1;
    assert [range_check96_ptr + 22] = div_a_coeff_0.d2;
    assert [range_check96_ptr + 23] = div_a_coeff_0.d3;
    assert [range_check96_ptr + 24] = div_a_coeff_1.d0;
    assert [range_check96_ptr + 25] = div_a_coeff_1.d1;
    assert [range_check96_ptr + 26] = div_a_coeff_1.d2;
    assert [range_check96_ptr + 27] = div_a_coeff_1.d3;
    assert [range_check96_ptr + 28] = div_a_coeff_2.d0;
    assert [range_check96_ptr + 29] = div_a_coeff_2.d1;
    assert [range_check96_ptr + 30] = div_a_coeff_2.d2;
    assert [range_check96_ptr + 31] = div_a_coeff_2.d3;
    assert [range_check96_ptr + 32] = div_a_coeff_3.d0;
    assert [range_check96_ptr + 33] = div_a_coeff_3.d1;
    assert [range_check96_ptr + 34] = div_a_coeff_3.d2;
    assert [range_check96_ptr + 35] = div_a_coeff_3.d3;
    assert [range_check96_ptr + 36] = div_a_coeff_4.d0;
    assert [range_check96_ptr + 37] = div_a_coeff_4.d1;
    assert [range_check96_ptr + 38] = div_a_coeff_4.d2;
    assert [range_check96_ptr + 39] = div_a_coeff_4.d3;
    assert [range_check96_ptr + 40] = div_b_coeff_0.d0;
    assert [range_check96_ptr + 41] = div_b_coeff_0.d1;
    assert [range_check96_ptr + 42] = div_b_coeff_0.d2;
    assert [range_check96_ptr + 43] = div_b_coeff_0.d3;
    assert [range_check96_ptr + 44] = div_b_coeff_1.d0;
    assert [range_check96_ptr + 45] = div_b_coeff_1.d1;
    assert [range_check96_ptr + 46] = div_b_coeff_1.d2;
    assert [range_check96_ptr + 47] = div_b_coeff_1.d3;
    assert [range_check96_ptr + 48] = div_b_coeff_2.d0;
    assert [range_check96_ptr + 49] = div_b_coeff_2.d1;
    assert [range_check96_ptr + 50] = div_b_coeff_2.d2;
    assert [range_check96_ptr + 51] = div_b_coeff_2.d3;
    assert [range_check96_ptr + 52] = div_b_coeff_3.d0;
    assert [range_check96_ptr + 53] = div_b_coeff_3.d1;
    assert [range_check96_ptr + 54] = div_b_coeff_3.d2;
    assert [range_check96_ptr + 55] = div_b_coeff_3.d3;
    assert [range_check96_ptr + 56] = div_b_coeff_4.d0;
    assert [range_check96_ptr + 57] = div_b_coeff_4.d1;
    assert [range_check96_ptr + 58] = div_b_coeff_4.d2;
    assert [range_check96_ptr + 59] = div_b_coeff_4.d3;
    assert [range_check96_ptr + 60] = div_b_coeff_5.d0;
    assert [range_check96_ptr + 61] = div_b_coeff_5.d1;
    assert [range_check96_ptr + 62] = div_b_coeff_5.d2;
    assert [range_check96_ptr + 63] = div_b_coeff_5.d3;
    assert [range_check96_ptr + 64] = div_c_coeff_0.d0;
    assert [range_check96_ptr + 65] = div_c_coeff_0.d1;
    assert [range_check96_ptr + 66] = div_c_coeff_0.d2;
    assert [range_check96_ptr + 67] = div_c_coeff_0.d3;
    assert [range_check96_ptr + 68] = div_c_coeff_1.d0;
    assert [range_check96_ptr + 69] = div_c_coeff_1.d1;
    assert [range_check96_ptr + 70] = div_c_coeff_1.d2;
    assert [range_check96_ptr + 71] = div_c_coeff_1.d3;
    assert [range_check96_ptr + 72] = div_c_coeff_2.d0;
    assert [range_check96_ptr + 73] = div_c_coeff_2.d1;
    assert [range_check96_ptr + 74] = div_c_coeff_2.d2;
    assert [range_check96_ptr + 75] = div_c_coeff_2.d3;
    assert [range_check96_ptr + 76] = div_c_coeff_3.d0;
    assert [range_check96_ptr + 77] = div_c_coeff_3.d1;
    assert [range_check96_ptr + 78] = div_c_coeff_3.d2;
    assert [range_check96_ptr + 79] = div_c_coeff_3.d3;
    assert [range_check96_ptr + 80] = div_c_coeff_4.d0;
    assert [range_check96_ptr + 81] = div_c_coeff_4.d1;
    assert [range_check96_ptr + 82] = div_c_coeff_4.d2;
    assert [range_check96_ptr + 83] = div_c_coeff_4.d3;
    assert [range_check96_ptr + 84] = div_c_coeff_5.d0;
    assert [range_check96_ptr + 85] = div_c_coeff_5.d1;
    assert [range_check96_ptr + 86] = div_c_coeff_5.d2;
    assert [range_check96_ptr + 87] = div_c_coeff_5.d3;
    assert [range_check96_ptr + 88] = div_d_coeff_0.d0;
    assert [range_check96_ptr + 89] = div_d_coeff_0.d1;
    assert [range_check96_ptr + 90] = div_d_coeff_0.d2;
    assert [range_check96_ptr + 91] = div_d_coeff_0.d3;
    assert [range_check96_ptr + 92] = div_d_coeff_1.d0;
    assert [range_check96_ptr + 93] = div_d_coeff_1.d1;
    assert [range_check96_ptr + 94] = div_d_coeff_1.d2;
    assert [range_check96_ptr + 95] = div_d_coeff_1.d3;
    assert [range_check96_ptr + 96] = div_d_coeff_2.d0;
    assert [range_check96_ptr + 97] = div_d_coeff_2.d1;
    assert [range_check96_ptr + 98] = div_d_coeff_2.d2;
    assert [range_check96_ptr + 99] = div_d_coeff_2.d3;
    assert [range_check96_ptr + 100] = div_d_coeff_3.d0;
    assert [range_check96_ptr + 101] = div_d_coeff_3.d1;
    assert [range_check96_ptr + 102] = div_d_coeff_3.d2;
    assert [range_check96_ptr + 103] = div_d_coeff_3.d3;
    assert [range_check96_ptr + 104] = div_d_coeff_4.d0;
    assert [range_check96_ptr + 105] = div_d_coeff_4.d1;
    assert [range_check96_ptr + 106] = div_d_coeff_4.d2;
    assert [range_check96_ptr + 107] = div_d_coeff_4.d3;
    assert [range_check96_ptr + 108] = div_d_coeff_5.d0;
    assert [range_check96_ptr + 109] = div_d_coeff_5.d1;
    assert [range_check96_ptr + 110] = div_d_coeff_5.d2;
    assert [range_check96_ptr + 111] = div_d_coeff_5.d3;
    assert [range_check96_ptr + 112] = div_d_coeff_6.d0;
    assert [range_check96_ptr + 113] = div_d_coeff_6.d1;
    assert [range_check96_ptr + 114] = div_d_coeff_6.d2;
    assert [range_check96_ptr + 115] = div_d_coeff_6.d3;
    assert [range_check96_ptr + 116] = div_d_coeff_7.d0;
    assert [range_check96_ptr + 117] = div_d_coeff_7.d1;
    assert [range_check96_ptr + 118] = div_d_coeff_7.d2;
    assert [range_check96_ptr + 119] = div_d_coeff_7.d3;
    assert [range_check96_ptr + 120] = div_d_coeff_8.d0;
    assert [range_check96_ptr + 121] = div_d_coeff_8.d1;
    assert [range_check96_ptr + 122] = div_d_coeff_8.d2;
    assert [range_check96_ptr + 123] = div_d_coeff_8.d3;
    assert [range_check96_ptr + 124] = g_x.d0;
    assert [range_check96_ptr + 125] = g_x.d1;
    assert [range_check96_ptr + 126] = g_x.d2;
    assert [range_check96_ptr + 127] = g_x.d3;
    assert [range_check96_ptr + 128] = g_y.d0;
    assert [range_check96_ptr + 129] = g_y.d1;
    assert [range_check96_ptr + 130] = g_y.d2;
    assert [range_check96_ptr + 131] = g_y.d3;
    assert [range_check96_ptr + 132] = r_x.d0;
    assert [range_check96_ptr + 133] = r_x.d1;
    assert [range_check96_ptr + 134] = r_x.d2;
    assert [range_check96_ptr + 135] = r_x.d3;
    assert [range_check96_ptr + 136] = r_y.d0;
    assert [range_check96_ptr + 137] = r_y.d1;
    assert [range_check96_ptr + 138] = r_y.d2;
    assert [range_check96_ptr + 139] = r_y.d3;
    assert [range_check96_ptr + 140] = ep1_low.d0;
    assert [range_check96_ptr + 141] = ep1_low.d1;
    assert [range_check96_ptr + 142] = ep1_low.d2;
    assert [range_check96_ptr + 143] = ep1_low.d3;
    assert [range_check96_ptr + 144] = en1_low.d0;
    assert [range_check96_ptr + 145] = en1_low.d1;
    assert [range_check96_ptr + 146] = en1_low.d2;
    assert [range_check96_ptr + 147] = en1_low.d3;
    assert [range_check96_ptr + 148] = sp1_low.d0;
    assert [range_check96_ptr + 149] = sp1_low.d1;
    assert [range_check96_ptr + 150] = sp1_low.d2;
    assert [range_check96_ptr + 151] = sp1_low.d3;
    assert [range_check96_ptr + 152] = sn1_low.d0;
    assert [range_check96_ptr + 153] = sn1_low.d1;
    assert [range_check96_ptr + 154] = sn1_low.d2;
    assert [range_check96_ptr + 155] = sn1_low.d3;
    assert [range_check96_ptr + 156] = ep2_low.d0;
    assert [range_check96_ptr + 157] = ep2_low.d1;
    assert [range_check96_ptr + 158] = ep2_low.d2;
    assert [range_check96_ptr + 159] = ep2_low.d3;
    assert [range_check96_ptr + 160] = en2_low.d0;
    assert [range_check96_ptr + 161] = en2_low.d1;
    assert [range_check96_ptr + 162] = en2_low.d2;
    assert [range_check96_ptr + 163] = en2_low.d3;
    assert [range_check96_ptr + 164] = sp2_low.d0;
    assert [range_check96_ptr + 165] = sp2_low.d1;
    assert [range_check96_ptr + 166] = sp2_low.d2;
    assert [range_check96_ptr + 167] = sp2_low.d3;
    assert [range_check96_ptr + 168] = sn2_low.d0;
    assert [range_check96_ptr + 169] = sn2_low.d1;
    assert [range_check96_ptr + 170] = sn2_low.d2;
    assert [range_check96_ptr + 171] = sn2_low.d3;
    assert [range_check96_ptr + 172] = ep1_high.d0;
    assert [range_check96_ptr + 173] = ep1_high.d1;
    assert [range_check96_ptr + 174] = ep1_high.d2;
    assert [range_check96_ptr + 175] = ep1_high.d3;
    assert [range_check96_ptr + 176] = en1_high.d0;
    assert [range_check96_ptr + 177] = en1_high.d1;
    assert [range_check96_ptr + 178] = en1_high.d2;
    assert [range_check96_ptr + 179] = en1_high.d3;
    assert [range_check96_ptr + 180] = sp1_high.d0;
    assert [range_check96_ptr + 181] = sp1_high.d1;
    assert [range_check96_ptr + 182] = sp1_high.d2;
    assert [range_check96_ptr + 183] = sp1_high.d3;
    assert [range_check96_ptr + 184] = sn1_high.d0;
    assert [range_check96_ptr + 185] = sn1_high.d1;
    assert [range_check96_ptr + 186] = sn1_high.d2;
    assert [range_check96_ptr + 187] = sn1_high.d3;
    assert [range_check96_ptr + 188] = ep2_high.d0;
    assert [range_check96_ptr + 189] = ep2_high.d1;
    assert [range_check96_ptr + 190] = ep2_high.d2;
    assert [range_check96_ptr + 191] = ep2_high.d3;
    assert [range_check96_ptr + 192] = en2_high.d0;
    assert [range_check96_ptr + 193] = en2_high.d1;
    assert [range_check96_ptr + 194] = en2_high.d2;
    assert [range_check96_ptr + 195] = en2_high.d3;
    assert [range_check96_ptr + 196] = sp2_high.d0;
    assert [range_check96_ptr + 197] = sp2_high.d1;
    assert [range_check96_ptr + 198] = sp2_high.d2;
    assert [range_check96_ptr + 199] = sp2_high.d3;
    assert [range_check96_ptr + 200] = sn2_high.d0;
    assert [range_check96_ptr + 201] = sn2_high.d1;
    assert [range_check96_ptr + 202] = sn2_high.d2;
    assert [range_check96_ptr + 203] = sn2_high.d3;
    assert [range_check96_ptr + 204] = q_low_x.d0;
    assert [range_check96_ptr + 205] = q_low_x.d1;
    assert [range_check96_ptr + 206] = q_low_x.d2;
    assert [range_check96_ptr + 207] = q_low_x.d3;
    assert [range_check96_ptr + 208] = q_low_y.d0;
    assert [range_check96_ptr + 209] = q_low_y.d1;
    assert [range_check96_ptr + 210] = q_low_y.d2;
    assert [range_check96_ptr + 211] = q_low_y.d3;
    assert [range_check96_ptr + 212] = q_high_x.d0;
    assert [range_check96_ptr + 213] = q_high_x.d1;
    assert [range_check96_ptr + 214] = q_high_x.d2;
    assert [range_check96_ptr + 215] = q_high_x.d3;
    assert [range_check96_ptr + 216] = q_high_y.d0;
    assert [range_check96_ptr + 217] = q_high_y.d1;
    assert [range_check96_ptr + 218] = q_high_y.d2;
    assert [range_check96_ptr + 219] = q_high_y.d3;
    assert [range_check96_ptr + 220] = q_high_shifted_x.d0;
    assert [range_check96_ptr + 221] = q_high_shifted_x.d1;
    assert [range_check96_ptr + 222] = q_high_shifted_x.d2;
    assert [range_check96_ptr + 223] = q_high_shifted_x.d3;
    assert [range_check96_ptr + 224] = q_high_shifted_y.d0;
    assert [range_check96_ptr + 225] = q_high_shifted_y.d1;
    assert [range_check96_ptr + 226] = q_high_shifted_y.d2;
    assert [range_check96_ptr + 227] = q_high_shifted_y.d3;
    assert [range_check96_ptr + 228] = a0_x.d0;
    assert [range_check96_ptr + 229] = a0_x.d1;
    assert [range_check96_ptr + 230] = a0_x.d2;
    assert [range_check96_ptr + 231] = a0_x.d3;
    assert [range_check96_ptr + 232] = a0_y.d0;
    assert [range_check96_ptr + 233] = a0_y.d1;
    assert [range_check96_ptr + 234] = a0_y.d2;
    assert [range_check96_ptr + 235] = a0_y.d3;
    assert [range_check96_ptr + 236] = a.d0;
    assert [range_check96_ptr + 237] = a.d1;
    assert [range_check96_ptr + 238] = a.d2;
    assert [range_check96_ptr + 239] = a.d3;
    assert [range_check96_ptr + 240] = b.d0;
    assert [range_check96_ptr + 241] = b.d1;
    assert [range_check96_ptr + 242] = b.d2;
    assert [range_check96_ptr + 243] = b.d3;
    assert [range_check96_ptr + 244] = base_rlc.d0;
    assert [range_check96_ptr + 245] = base_rlc.d1;
    assert [range_check96_ptr + 246] = base_rlc.d2;
    assert [range_check96_ptr + 247] = base_rlc.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=111,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=134,
    );

    let range_check96_ptr = range_check96_ptr + 1200;

    return ();

    add_offsets:
    dw 252;
    dw 256;
    dw 260;
    dw 260;
    dw 240;
    dw 264;
    dw 272;
    dw 236;
    dw 276;
    dw 276;
    dw 280;
    dw 284;
    dw 284;
    dw 240;
    dw 288;
    dw 296;
    dw 300;
    dw 304;
    dw 304;
    dw 240;
    dw 308;
    dw 316;
    dw 320;
    dw 324;
    dw 324;
    dw 240;
    dw 328;
    dw 336;
    dw 340;
    dw 344;
    dw 344;
    dw 240;
    dw 348;
    dw 356;
    dw 360;
    dw 364;
    dw 364;
    dw 240;
    dw 368;
    dw 16;
    dw 8;
    dw 372;
    dw 380;
    dw 236;
    dw 384;
    dw 16;
    dw 12;
    dw 388;
    dw 404;
    dw 400;
    dw 232;
    dw 16;
    dw 12;
    dw 412;
    dw 420;
    dw 416;
    dw 408;
    dw 424;
    dw 420;
    dw 228;
    dw 432;
    dw 428;
    dw 232;
    dw 436;
    dw 232;
    dw 432;
    dw 440;
    dw 228;
    dw 420;
    dw 16;
    dw 12;
    dw 448;
    dw 456;
    dw 420;
    dw 228;
    dw 16;
    dw 8;
    dw 464;
    dw 472;
    dw 236;
    dw 476;
    dw 16;
    dw 12;
    dw 480;
    dw 492;
    dw 488;
    dw 476;
    dw 16;
    dw 12;
    dw 500;
    dw 496;
    dw 504;
    dw 508;
    dw 32;
    dw 512;
    dw 516;
    dw 28;
    dw 520;
    dw 524;
    dw 24;
    dw 528;
    dw 532;
    dw 20;
    dw 536;
    dw 540;
    dw 56;
    dw 544;
    dw 548;
    dw 52;
    dw 552;
    dw 556;
    dw 48;
    dw 560;
    dw 564;
    dw 44;
    dw 568;
    dw 572;
    dw 40;
    dw 576;
    dw 580;
    dw 80;
    dw 584;
    dw 588;
    dw 76;
    dw 592;
    dw 596;
    dw 72;
    dw 600;
    dw 604;
    dw 68;
    dw 608;
    dw 612;
    dw 64;
    dw 616;
    dw 620;
    dw 116;
    dw 624;
    dw 628;
    dw 112;
    dw 632;
    dw 636;
    dw 108;
    dw 640;
    dw 644;
    dw 104;
    dw 648;
    dw 652;
    dw 100;
    dw 656;
    dw 660;
    dw 96;
    dw 664;
    dw 668;
    dw 92;
    dw 672;
    dw 676;
    dw 88;
    dw 680;
    dw 684;
    dw 688;
    dw 696;
    dw 700;
    dw 32;
    dw 704;
    dw 708;
    dw 28;
    dw 712;
    dw 716;
    dw 24;
    dw 720;
    dw 724;
    dw 20;
    dw 728;
    dw 732;
    dw 56;
    dw 736;
    dw 740;
    dw 52;
    dw 744;
    dw 748;
    dw 48;
    dw 752;
    dw 756;
    dw 44;
    dw 760;
    dw 764;
    dw 40;
    dw 768;
    dw 772;
    dw 80;
    dw 776;
    dw 780;
    dw 76;
    dw 784;
    dw 788;
    dw 72;
    dw 792;
    dw 796;
    dw 68;
    dw 800;
    dw 804;
    dw 64;
    dw 808;
    dw 812;
    dw 116;
    dw 816;
    dw 820;
    dw 112;
    dw 824;
    dw 828;
    dw 108;
    dw 832;
    dw 836;
    dw 104;
    dw 840;
    dw 844;
    dw 100;
    dw 848;
    dw 852;
    dw 96;
    dw 856;
    dw 860;
    dw 92;
    dw 864;
    dw 868;
    dw 88;
    dw 872;
    dw 876;
    dw 880;
    dw 888;
    dw 892;
    dw 904;
    dw 900;
    dw 896;
    dw 908;
    dw 124;
    dw 228;
    dw 912;
    dw 404;
    dw 916;
    dw 920;
    dw 916;
    dw 128;
    dw 128;
    dw 916;
    dw 924;
    dw 952;
    dw 948;
    dw 936;
    dw 956;
    dw 132;
    dw 228;
    dw 960;
    dw 404;
    dw 964;
    dw 968;
    dw 964;
    dw 136;
    dw 136;
    dw 964;
    dw 972;
    dw 1000;
    dw 996;
    dw 984;
    dw 1004;
    dw 204;
    dw 228;
    dw 1008;
    dw 404;
    dw 1012;
    dw 208;
    dw 1012;
    dw 1016;
    dw 952;
    dw 1000;
    dw 1024;
    dw 1028;
    dw 1020;
    dw 1024;
    dw 1056;
    dw 1052;
    dw 1040;
    dw 1084;
    dw 1080;
    dw 1068;
    dw 1088;
    dw 212;
    dw 228;
    dw 1092;
    dw 404;
    dw 1096;
    dw 216;
    dw 1096;
    dw 1100;
    dw 1056;
    dw 1084;
    dw 1108;
    dw 1112;
    dw 1104;
    dw 1108;
    dw 16;
    dw 4;
    dw 1116;
    dw 16;
    dw 0;
    dw 1120;
    dw 1124;
    dw 1096;
    dw 216;
    dw 1144;
    dw 220;
    dw 228;
    dw 1148;
    dw 404;
    dw 1152;
    dw 224;
    dw 1152;
    dw 1156;
    dw 1164;
    dw 1132;
    dw 1140;
    dw 1168;
    dw 1160;
    dw 1164;
    dw 1180;
    dw 1184;
    dw 1188;
    dw 1188;
    dw 1192;
    dw 1196;
    dw 16;
    dw 1196;
    dw 904;

    mul_offsets:
    dw 124;
    dw 124;
    dw 248;
    dw 248;
    dw 124;
    dw 252;
    dw 236;
    dw 124;
    dw 256;
    dw 128;
    dw 128;
    dw 264;
    dw 132;
    dw 132;
    dw 268;
    dw 268;
    dw 132;
    dw 272;
    dw 236;
    dw 132;
    dw 280;
    dw 136;
    dw 136;
    dw 288;
    dw 228;
    dw 228;
    dw 292;
    dw 292;
    dw 228;
    dw 296;
    dw 236;
    dw 228;
    dw 300;
    dw 232;
    dw 232;
    dw 308;
    dw 204;
    dw 204;
    dw 312;
    dw 312;
    dw 204;
    dw 316;
    dw 236;
    dw 204;
    dw 320;
    dw 208;
    dw 208;
    dw 328;
    dw 212;
    dw 212;
    dw 332;
    dw 332;
    dw 212;
    dw 336;
    dw 236;
    dw 212;
    dw 340;
    dw 216;
    dw 216;
    dw 348;
    dw 220;
    dw 220;
    dw 352;
    dw 352;
    dw 220;
    dw 356;
    dw 236;
    dw 220;
    dw 360;
    dw 224;
    dw 224;
    dw 368;
    dw 372;
    dw 228;
    dw 376;
    dw 376;
    dw 228;
    dw 380;
    dw 388;
    dw 232;
    dw 392;
    dw 396;
    dw 392;
    dw 384;
    dw 228;
    dw 396;
    dw 400;
    dw 396;
    dw 396;
    dw 408;
    dw 412;
    dw 228;
    dw 416;
    dw 396;
    dw 424;
    dw 428;
    dw 444;
    dw 440;
    dw 436;
    dw 448;
    dw 432;
    dw 452;
    dw 452;
    dw 456;
    dw 460;
    dw 464;
    dw 420;
    dw 468;
    dw 468;
    dw 420;
    dw 472;
    dw 480;
    dw 444;
    dw 484;
    dw 484;
    dw 432;
    dw 488;
    dw 496;
    dw 492;
    dw 460;
    dw 500;
    dw 444;
    dw 504;
    dw 228;
    dw 36;
    dw 512;
    dw 228;
    dw 516;
    dw 520;
    dw 228;
    dw 524;
    dw 528;
    dw 228;
    dw 532;
    dw 536;
    dw 228;
    dw 60;
    dw 544;
    dw 228;
    dw 548;
    dw 552;
    dw 228;
    dw 556;
    dw 560;
    dw 228;
    dw 564;
    dw 568;
    dw 228;
    dw 572;
    dw 576;
    dw 228;
    dw 84;
    dw 584;
    dw 228;
    dw 588;
    dw 592;
    dw 228;
    dw 596;
    dw 600;
    dw 228;
    dw 604;
    dw 608;
    dw 228;
    dw 612;
    dw 616;
    dw 228;
    dw 120;
    dw 624;
    dw 228;
    dw 628;
    dw 632;
    dw 228;
    dw 636;
    dw 640;
    dw 228;
    dw 644;
    dw 648;
    dw 228;
    dw 652;
    dw 656;
    dw 228;
    dw 660;
    dw 664;
    dw 228;
    dw 668;
    dw 672;
    dw 228;
    dw 676;
    dw 680;
    dw 688;
    dw 580;
    dw 540;
    dw 232;
    dw 620;
    dw 692;
    dw 696;
    dw 684;
    dw 692;
    dw 420;
    dw 36;
    dw 704;
    dw 420;
    dw 708;
    dw 712;
    dw 420;
    dw 716;
    dw 720;
    dw 420;
    dw 724;
    dw 728;
    dw 420;
    dw 60;
    dw 736;
    dw 420;
    dw 740;
    dw 744;
    dw 420;
    dw 748;
    dw 752;
    dw 420;
    dw 756;
    dw 760;
    dw 420;
    dw 764;
    dw 768;
    dw 420;
    dw 84;
    dw 776;
    dw 420;
    dw 780;
    dw 784;
    dw 420;
    dw 788;
    dw 792;
    dw 420;
    dw 796;
    dw 800;
    dw 420;
    dw 804;
    dw 808;
    dw 420;
    dw 120;
    dw 816;
    dw 420;
    dw 820;
    dw 824;
    dw 420;
    dw 828;
    dw 832;
    dw 420;
    dw 836;
    dw 840;
    dw 420;
    dw 844;
    dw 848;
    dw 420;
    dw 852;
    dw 856;
    dw 420;
    dw 860;
    dw 864;
    dw 420;
    dw 868;
    dw 872;
    dw 880;
    dw 772;
    dw 732;
    dw 432;
    dw 812;
    dw 884;
    dw 888;
    dw 876;
    dw 884;
    dw 508;
    dw 700;
    dw 896;
    dw 496;
    dw 892;
    dw 900;
    dw 396;
    dw 124;
    dw 912;
    dw 148;
    dw 140;
    dw 928;
    dw 928;
    dw 908;
    dw 932;
    dw 936;
    dw 920;
    dw 932;
    dw 152;
    dw 144;
    dw 940;
    dw 940;
    dw 908;
    dw 944;
    dw 948;
    dw 924;
    dw 944;
    dw 396;
    dw 132;
    dw 960;
    dw 164;
    dw 156;
    dw 976;
    dw 976;
    dw 956;
    dw 980;
    dw 984;
    dw 968;
    dw 980;
    dw 168;
    dw 160;
    dw 988;
    dw 988;
    dw 956;
    dw 992;
    dw 996;
    dw 972;
    dw 992;
    dw 396;
    dw 204;
    dw 1008;
    dw 1020;
    dw 1016;
    dw 1004;
    dw 180;
    dw 172;
    dw 1032;
    dw 1032;
    dw 908;
    dw 1036;
    dw 1040;
    dw 920;
    dw 1036;
    dw 184;
    dw 176;
    dw 1044;
    dw 1044;
    dw 908;
    dw 1048;
    dw 1052;
    dw 924;
    dw 1048;
    dw 196;
    dw 188;
    dw 1060;
    dw 1060;
    dw 956;
    dw 1064;
    dw 1068;
    dw 968;
    dw 1064;
    dw 200;
    dw 192;
    dw 1072;
    dw 1072;
    dw 956;
    dw 1076;
    dw 1080;
    dw 972;
    dw 1076;
    dw 396;
    dw 212;
    dw 1092;
    dw 1104;
    dw 1100;
    dw 1088;
    dw 1116;
    dw 1088;
    dw 1128;
    dw 1132;
    dw 1124;
    dw 1128;
    dw 1120;
    dw 1088;
    dw 1136;
    dw 1140;
    dw 1100;
    dw 1136;
    dw 396;
    dw 220;
    dw 1148;
    dw 1160;
    dw 1156;
    dw 1144;
    dw 244;
    dw 244;
    dw 1172;
    dw 1172;
    dw 244;
    dw 1176;
    dw 244;
    dw 1028;
    dw 1180;
    dw 1172;
    dw 1112;
    dw 1184;
    dw 1176;
    dw 1168;
    dw 1192;
}

func ecip_1p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    div_a_coeff_0: UInt384*,
    div_a_coeff_1: UInt384*,
    div_a_coeff_2: UInt384*,
    div_a_coeff_3: UInt384*,
    div_b_coeff_0: UInt384*,
    div_b_coeff_1: UInt384*,
    div_b_coeff_2: UInt384*,
    div_b_coeff_3: UInt384*,
    div_b_coeff_4: UInt384*,
    div_c_coeff_0: UInt384*,
    div_c_coeff_1: UInt384*,
    div_c_coeff_2: UInt384*,
    div_c_coeff_3: UInt384*,
    div_c_coeff_4: UInt384*,
    div_d_coeff_0: UInt384*,
    div_d_coeff_1: UInt384*,
    div_d_coeff_2: UInt384*,
    div_d_coeff_3: UInt384*,
    div_d_coeff_4: UInt384*,
    div_d_coeff_5: UInt384*,
    div_d_coeff_6: UInt384*,
    div_d_coeff_7: UInt384*,
    g_x: UInt384*,
    g_y: UInt384*,
    ep_low: UInt384*,
    en_low: UInt384*,
    sp_low: UInt384*,
    sn_low: UInt384*,
    ep_high: UInt384*,
    en_high: UInt384*,
    sp_high: UInt384*,
    sn_high: UInt384*,
    q_low_x: UInt384*,
    q_low_y: UInt384*,
    q_high_x: UInt384*,
    q_high_y: UInt384*,
    q_high_shifted_x: UInt384*,
    q_high_shifted_y: UInt384*,
    a0_x: UInt384*,
    a0_y: UInt384*,
    a: UInt384*,
    b: UInt384*,
    base_rlc: UInt384*,
    p: UInt384*,
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_mod_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_mod_offsets_ptr = pc + (mul_offsets - pc_label);

    assert [range_check96_ptr + 0] = 12528508628158887531275213211;
    assert [range_check96_ptr + 1] = 4361599596;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    assert [range_check96_ptr + 4] = 12528508628158887531275213211;
    assert [range_check96_ptr + 5] = 66632300;
    assert [range_check96_ptr + 6] = 0;
    assert [range_check96_ptr + 7] = 0;
    assert [range_check96_ptr + 8] = 3;
    assert [range_check96_ptr + 9] = 0;
    assert [range_check96_ptr + 10] = 0;
    assert [range_check96_ptr + 11] = 0;
    assert [range_check96_ptr + 12] = 2;
    assert [range_check96_ptr + 13] = 0;
    assert [range_check96_ptr + 14] = 0;
    assert [range_check96_ptr + 15] = 0;
    assert [range_check96_ptr + 16] = 0;
    assert [range_check96_ptr + 17] = 0;
    assert [range_check96_ptr + 18] = 0;
    assert [range_check96_ptr + 19] = 0;

    assert [range_check96_ptr + 20] = div_a_coeff_0.d0;
    assert [range_check96_ptr + 21] = div_a_coeff_0.d1;
    assert [range_check96_ptr + 22] = div_a_coeff_0.d2;
    assert [range_check96_ptr + 23] = div_a_coeff_0.d3;
    assert [range_check96_ptr + 24] = div_a_coeff_1.d0;
    assert [range_check96_ptr + 25] = div_a_coeff_1.d1;
    assert [range_check96_ptr + 26] = div_a_coeff_1.d2;
    assert [range_check96_ptr + 27] = div_a_coeff_1.d3;
    assert [range_check96_ptr + 28] = div_a_coeff_2.d0;
    assert [range_check96_ptr + 29] = div_a_coeff_2.d1;
    assert [range_check96_ptr + 30] = div_a_coeff_2.d2;
    assert [range_check96_ptr + 31] = div_a_coeff_2.d3;
    assert [range_check96_ptr + 32] = div_a_coeff_3.d0;
    assert [range_check96_ptr + 33] = div_a_coeff_3.d1;
    assert [range_check96_ptr + 34] = div_a_coeff_3.d2;
    assert [range_check96_ptr + 35] = div_a_coeff_3.d3;
    assert [range_check96_ptr + 36] = div_b_coeff_0.d0;
    assert [range_check96_ptr + 37] = div_b_coeff_0.d1;
    assert [range_check96_ptr + 38] = div_b_coeff_0.d2;
    assert [range_check96_ptr + 39] = div_b_coeff_0.d3;
    assert [range_check96_ptr + 40] = div_b_coeff_1.d0;
    assert [range_check96_ptr + 41] = div_b_coeff_1.d1;
    assert [range_check96_ptr + 42] = div_b_coeff_1.d2;
    assert [range_check96_ptr + 43] = div_b_coeff_1.d3;
    assert [range_check96_ptr + 44] = div_b_coeff_2.d0;
    assert [range_check96_ptr + 45] = div_b_coeff_2.d1;
    assert [range_check96_ptr + 46] = div_b_coeff_2.d2;
    assert [range_check96_ptr + 47] = div_b_coeff_2.d3;
    assert [range_check96_ptr + 48] = div_b_coeff_3.d0;
    assert [range_check96_ptr + 49] = div_b_coeff_3.d1;
    assert [range_check96_ptr + 50] = div_b_coeff_3.d2;
    assert [range_check96_ptr + 51] = div_b_coeff_3.d3;
    assert [range_check96_ptr + 52] = div_b_coeff_4.d0;
    assert [range_check96_ptr + 53] = div_b_coeff_4.d1;
    assert [range_check96_ptr + 54] = div_b_coeff_4.d2;
    assert [range_check96_ptr + 55] = div_b_coeff_4.d3;
    assert [range_check96_ptr + 56] = div_c_coeff_0.d0;
    assert [range_check96_ptr + 57] = div_c_coeff_0.d1;
    assert [range_check96_ptr + 58] = div_c_coeff_0.d2;
    assert [range_check96_ptr + 59] = div_c_coeff_0.d3;
    assert [range_check96_ptr + 60] = div_c_coeff_1.d0;
    assert [range_check96_ptr + 61] = div_c_coeff_1.d1;
    assert [range_check96_ptr + 62] = div_c_coeff_1.d2;
    assert [range_check96_ptr + 63] = div_c_coeff_1.d3;
    assert [range_check96_ptr + 64] = div_c_coeff_2.d0;
    assert [range_check96_ptr + 65] = div_c_coeff_2.d1;
    assert [range_check96_ptr + 66] = div_c_coeff_2.d2;
    assert [range_check96_ptr + 67] = div_c_coeff_2.d3;
    assert [range_check96_ptr + 68] = div_c_coeff_3.d0;
    assert [range_check96_ptr + 69] = div_c_coeff_3.d1;
    assert [range_check96_ptr + 70] = div_c_coeff_3.d2;
    assert [range_check96_ptr + 71] = div_c_coeff_3.d3;
    assert [range_check96_ptr + 72] = div_c_coeff_4.d0;
    assert [range_check96_ptr + 73] = div_c_coeff_4.d1;
    assert [range_check96_ptr + 74] = div_c_coeff_4.d2;
    assert [range_check96_ptr + 75] = div_c_coeff_4.d3;
    assert [range_check96_ptr + 76] = div_d_coeff_0.d0;
    assert [range_check96_ptr + 77] = div_d_coeff_0.d1;
    assert [range_check96_ptr + 78] = div_d_coeff_0.d2;
    assert [range_check96_ptr + 79] = div_d_coeff_0.d3;
    assert [range_check96_ptr + 80] = div_d_coeff_1.d0;
    assert [range_check96_ptr + 81] = div_d_coeff_1.d1;
    assert [range_check96_ptr + 82] = div_d_coeff_1.d2;
    assert [range_check96_ptr + 83] = div_d_coeff_1.d3;
    assert [range_check96_ptr + 84] = div_d_coeff_2.d0;
    assert [range_check96_ptr + 85] = div_d_coeff_2.d1;
    assert [range_check96_ptr + 86] = div_d_coeff_2.d2;
    assert [range_check96_ptr + 87] = div_d_coeff_2.d3;
    assert [range_check96_ptr + 88] = div_d_coeff_3.d0;
    assert [range_check96_ptr + 89] = div_d_coeff_3.d1;
    assert [range_check96_ptr + 90] = div_d_coeff_3.d2;
    assert [range_check96_ptr + 91] = div_d_coeff_3.d3;
    assert [range_check96_ptr + 92] = div_d_coeff_4.d0;
    assert [range_check96_ptr + 93] = div_d_coeff_4.d1;
    assert [range_check96_ptr + 94] = div_d_coeff_4.d2;
    assert [range_check96_ptr + 95] = div_d_coeff_4.d3;
    assert [range_check96_ptr + 96] = div_d_coeff_5.d0;
    assert [range_check96_ptr + 97] = div_d_coeff_5.d1;
    assert [range_check96_ptr + 98] = div_d_coeff_5.d2;
    assert [range_check96_ptr + 99] = div_d_coeff_5.d3;
    assert [range_check96_ptr + 100] = div_d_coeff_6.d0;
    assert [range_check96_ptr + 101] = div_d_coeff_6.d1;
    assert [range_check96_ptr + 102] = div_d_coeff_6.d2;
    assert [range_check96_ptr + 103] = div_d_coeff_6.d3;
    assert [range_check96_ptr + 104] = div_d_coeff_7.d0;
    assert [range_check96_ptr + 105] = div_d_coeff_7.d1;
    assert [range_check96_ptr + 106] = div_d_coeff_7.d2;
    assert [range_check96_ptr + 107] = div_d_coeff_7.d3;
    assert [range_check96_ptr + 108] = g_x.d0;
    assert [range_check96_ptr + 109] = g_x.d1;
    assert [range_check96_ptr + 110] = g_x.d2;
    assert [range_check96_ptr + 111] = g_x.d3;
    assert [range_check96_ptr + 112] = g_y.d0;
    assert [range_check96_ptr + 113] = g_y.d1;
    assert [range_check96_ptr + 114] = g_y.d2;
    assert [range_check96_ptr + 115] = g_y.d3;
    assert [range_check96_ptr + 116] = ep_low.d0;
    assert [range_check96_ptr + 117] = ep_low.d1;
    assert [range_check96_ptr + 118] = ep_low.d2;
    assert [range_check96_ptr + 119] = ep_low.d3;
    assert [range_check96_ptr + 120] = en_low.d0;
    assert [range_check96_ptr + 121] = en_low.d1;
    assert [range_check96_ptr + 122] = en_low.d2;
    assert [range_check96_ptr + 123] = en_low.d3;
    assert [range_check96_ptr + 124] = sp_low.d0;
    assert [range_check96_ptr + 125] = sp_low.d1;
    assert [range_check96_ptr + 126] = sp_low.d2;
    assert [range_check96_ptr + 127] = sp_low.d3;
    assert [range_check96_ptr + 128] = sn_low.d0;
    assert [range_check96_ptr + 129] = sn_low.d1;
    assert [range_check96_ptr + 130] = sn_low.d2;
    assert [range_check96_ptr + 131] = sn_low.d3;
    assert [range_check96_ptr + 132] = ep_high.d0;
    assert [range_check96_ptr + 133] = ep_high.d1;
    assert [range_check96_ptr + 134] = ep_high.d2;
    assert [range_check96_ptr + 135] = ep_high.d3;
    assert [range_check96_ptr + 136] = en_high.d0;
    assert [range_check96_ptr + 137] = en_high.d1;
    assert [range_check96_ptr + 138] = en_high.d2;
    assert [range_check96_ptr + 139] = en_high.d3;
    assert [range_check96_ptr + 140] = sp_high.d0;
    assert [range_check96_ptr + 141] = sp_high.d1;
    assert [range_check96_ptr + 142] = sp_high.d2;
    assert [range_check96_ptr + 143] = sp_high.d3;
    assert [range_check96_ptr + 144] = sn_high.d0;
    assert [range_check96_ptr + 145] = sn_high.d1;
    assert [range_check96_ptr + 146] = sn_high.d2;
    assert [range_check96_ptr + 147] = sn_high.d3;
    assert [range_check96_ptr + 148] = q_low_x.d0;
    assert [range_check96_ptr + 149] = q_low_x.d1;
    assert [range_check96_ptr + 150] = q_low_x.d2;
    assert [range_check96_ptr + 151] = q_low_x.d3;
    assert [range_check96_ptr + 152] = q_low_y.d0;
    assert [range_check96_ptr + 153] = q_low_y.d1;
    assert [range_check96_ptr + 154] = q_low_y.d2;
    assert [range_check96_ptr + 155] = q_low_y.d3;
    assert [range_check96_ptr + 156] = q_high_x.d0;
    assert [range_check96_ptr + 157] = q_high_x.d1;
    assert [range_check96_ptr + 158] = q_high_x.d2;
    assert [range_check96_ptr + 159] = q_high_x.d3;
    assert [range_check96_ptr + 160] = q_high_y.d0;
    assert [range_check96_ptr + 161] = q_high_y.d1;
    assert [range_check96_ptr + 162] = q_high_y.d2;
    assert [range_check96_ptr + 163] = q_high_y.d3;
    assert [range_check96_ptr + 164] = q_high_shifted_x.d0;
    assert [range_check96_ptr + 165] = q_high_shifted_x.d1;
    assert [range_check96_ptr + 166] = q_high_shifted_x.d2;
    assert [range_check96_ptr + 167] = q_high_shifted_x.d3;
    assert [range_check96_ptr + 168] = q_high_shifted_y.d0;
    assert [range_check96_ptr + 169] = q_high_shifted_y.d1;
    assert [range_check96_ptr + 170] = q_high_shifted_y.d2;
    assert [range_check96_ptr + 171] = q_high_shifted_y.d3;
    assert [range_check96_ptr + 172] = a0_x.d0;
    assert [range_check96_ptr + 173] = a0_x.d1;
    assert [range_check96_ptr + 174] = a0_x.d2;
    assert [range_check96_ptr + 175] = a0_x.d3;
    assert [range_check96_ptr + 176] = a0_y.d0;
    assert [range_check96_ptr + 177] = a0_y.d1;
    assert [range_check96_ptr + 178] = a0_y.d2;
    assert [range_check96_ptr + 179] = a0_y.d3;
    assert [range_check96_ptr + 180] = a.d0;
    assert [range_check96_ptr + 181] = a.d1;
    assert [range_check96_ptr + 182] = a.d2;
    assert [range_check96_ptr + 183] = a.d3;
    assert [range_check96_ptr + 184] = b.d0;
    assert [range_check96_ptr + 185] = b.d1;
    assert [range_check96_ptr + 186] = b.d2;
    assert [range_check96_ptr + 187] = b.d3;
    assert [range_check96_ptr + 188] = base_rlc.d0;
    assert [range_check96_ptr + 189] = base_rlc.d1;
    assert [range_check96_ptr + 190] = base_rlc.d2;
    assert [range_check96_ptr + 191] = base_rlc.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=92,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=109,
    );

    let range_check96_ptr = range_check96_ptr + 972;

    return ();

    add_offsets:
    dw 196;
    dw 200;
    dw 204;
    dw 204;
    dw 184;
    dw 208;
    dw 216;
    dw 220;
    dw 224;
    dw 224;
    dw 184;
    dw 228;
    dw 236;
    dw 240;
    dw 244;
    dw 244;
    dw 184;
    dw 248;
    dw 256;
    dw 260;
    dw 264;
    dw 264;
    dw 184;
    dw 268;
    dw 276;
    dw 280;
    dw 284;
    dw 284;
    dw 184;
    dw 288;
    dw 16;
    dw 8;
    dw 292;
    dw 300;
    dw 180;
    dw 304;
    dw 16;
    dw 12;
    dw 308;
    dw 324;
    dw 320;
    dw 176;
    dw 16;
    dw 12;
    dw 332;
    dw 340;
    dw 336;
    dw 328;
    dw 344;
    dw 340;
    dw 172;
    dw 352;
    dw 348;
    dw 176;
    dw 356;
    dw 176;
    dw 352;
    dw 360;
    dw 172;
    dw 340;
    dw 16;
    dw 12;
    dw 368;
    dw 376;
    dw 340;
    dw 172;
    dw 16;
    dw 8;
    dw 384;
    dw 392;
    dw 180;
    dw 396;
    dw 16;
    dw 12;
    dw 400;
    dw 412;
    dw 408;
    dw 396;
    dw 16;
    dw 12;
    dw 420;
    dw 416;
    dw 424;
    dw 428;
    dw 28;
    dw 432;
    dw 436;
    dw 24;
    dw 440;
    dw 444;
    dw 20;
    dw 448;
    dw 452;
    dw 48;
    dw 456;
    dw 460;
    dw 44;
    dw 464;
    dw 468;
    dw 40;
    dw 472;
    dw 476;
    dw 36;
    dw 480;
    dw 484;
    dw 68;
    dw 488;
    dw 492;
    dw 64;
    dw 496;
    dw 500;
    dw 60;
    dw 504;
    dw 508;
    dw 56;
    dw 512;
    dw 516;
    dw 100;
    dw 520;
    dw 524;
    dw 96;
    dw 528;
    dw 532;
    dw 92;
    dw 536;
    dw 540;
    dw 88;
    dw 544;
    dw 548;
    dw 84;
    dw 552;
    dw 556;
    dw 80;
    dw 560;
    dw 564;
    dw 76;
    dw 568;
    dw 572;
    dw 576;
    dw 584;
    dw 588;
    dw 28;
    dw 592;
    dw 596;
    dw 24;
    dw 600;
    dw 604;
    dw 20;
    dw 608;
    dw 612;
    dw 48;
    dw 616;
    dw 620;
    dw 44;
    dw 624;
    dw 628;
    dw 40;
    dw 632;
    dw 636;
    dw 36;
    dw 640;
    dw 644;
    dw 68;
    dw 648;
    dw 652;
    dw 64;
    dw 656;
    dw 660;
    dw 60;
    dw 664;
    dw 668;
    dw 56;
    dw 672;
    dw 676;
    dw 100;
    dw 680;
    dw 684;
    dw 96;
    dw 688;
    dw 692;
    dw 92;
    dw 696;
    dw 700;
    dw 88;
    dw 704;
    dw 708;
    dw 84;
    dw 712;
    dw 716;
    dw 80;
    dw 720;
    dw 724;
    dw 76;
    dw 728;
    dw 732;
    dw 736;
    dw 744;
    dw 748;
    dw 760;
    dw 756;
    dw 752;
    dw 764;
    dw 108;
    dw 172;
    dw 768;
    dw 324;
    dw 772;
    dw 776;
    dw 772;
    dw 112;
    dw 112;
    dw 772;
    dw 780;
    dw 808;
    dw 804;
    dw 792;
    dw 812;
    dw 148;
    dw 172;
    dw 816;
    dw 324;
    dw 820;
    dw 152;
    dw 820;
    dw 824;
    dw 832;
    dw 828;
    dw 808;
    dw 860;
    dw 856;
    dw 844;
    dw 864;
    dw 156;
    dw 172;
    dw 868;
    dw 324;
    dw 872;
    dw 160;
    dw 872;
    dw 876;
    dw 884;
    dw 880;
    dw 860;
    dw 16;
    dw 4;
    dw 888;
    dw 16;
    dw 0;
    dw 892;
    dw 896;
    dw 872;
    dw 160;
    dw 916;
    dw 164;
    dw 172;
    dw 920;
    dw 324;
    dw 924;
    dw 168;
    dw 924;
    dw 928;
    dw 936;
    dw 904;
    dw 912;
    dw 940;
    dw 932;
    dw 936;
    dw 952;
    dw 956;
    dw 960;
    dw 960;
    dw 964;
    dw 968;
    dw 16;
    dw 968;
    dw 760;

    mul_offsets:
    dw 108;
    dw 108;
    dw 192;
    dw 192;
    dw 108;
    dw 196;
    dw 180;
    dw 108;
    dw 200;
    dw 112;
    dw 112;
    dw 208;
    dw 172;
    dw 172;
    dw 212;
    dw 212;
    dw 172;
    dw 216;
    dw 180;
    dw 172;
    dw 220;
    dw 176;
    dw 176;
    dw 228;
    dw 148;
    dw 148;
    dw 232;
    dw 232;
    dw 148;
    dw 236;
    dw 180;
    dw 148;
    dw 240;
    dw 152;
    dw 152;
    dw 248;
    dw 156;
    dw 156;
    dw 252;
    dw 252;
    dw 156;
    dw 256;
    dw 180;
    dw 156;
    dw 260;
    dw 160;
    dw 160;
    dw 268;
    dw 164;
    dw 164;
    dw 272;
    dw 272;
    dw 164;
    dw 276;
    dw 180;
    dw 164;
    dw 280;
    dw 168;
    dw 168;
    dw 288;
    dw 292;
    dw 172;
    dw 296;
    dw 296;
    dw 172;
    dw 300;
    dw 308;
    dw 176;
    dw 312;
    dw 316;
    dw 312;
    dw 304;
    dw 172;
    dw 316;
    dw 320;
    dw 316;
    dw 316;
    dw 328;
    dw 332;
    dw 172;
    dw 336;
    dw 316;
    dw 344;
    dw 348;
    dw 364;
    dw 360;
    dw 356;
    dw 368;
    dw 352;
    dw 372;
    dw 372;
    dw 376;
    dw 380;
    dw 384;
    dw 340;
    dw 388;
    dw 388;
    dw 340;
    dw 392;
    dw 400;
    dw 364;
    dw 404;
    dw 404;
    dw 352;
    dw 408;
    dw 416;
    dw 412;
    dw 380;
    dw 420;
    dw 364;
    dw 424;
    dw 172;
    dw 32;
    dw 432;
    dw 172;
    dw 436;
    dw 440;
    dw 172;
    dw 444;
    dw 448;
    dw 172;
    dw 52;
    dw 456;
    dw 172;
    dw 460;
    dw 464;
    dw 172;
    dw 468;
    dw 472;
    dw 172;
    dw 476;
    dw 480;
    dw 172;
    dw 72;
    dw 488;
    dw 172;
    dw 492;
    dw 496;
    dw 172;
    dw 500;
    dw 504;
    dw 172;
    dw 508;
    dw 512;
    dw 172;
    dw 104;
    dw 520;
    dw 172;
    dw 524;
    dw 528;
    dw 172;
    dw 532;
    dw 536;
    dw 172;
    dw 540;
    dw 544;
    dw 172;
    dw 548;
    dw 552;
    dw 172;
    dw 556;
    dw 560;
    dw 172;
    dw 564;
    dw 568;
    dw 576;
    dw 484;
    dw 452;
    dw 176;
    dw 516;
    dw 580;
    dw 584;
    dw 572;
    dw 580;
    dw 340;
    dw 32;
    dw 592;
    dw 340;
    dw 596;
    dw 600;
    dw 340;
    dw 604;
    dw 608;
    dw 340;
    dw 52;
    dw 616;
    dw 340;
    dw 620;
    dw 624;
    dw 340;
    dw 628;
    dw 632;
    dw 340;
    dw 636;
    dw 640;
    dw 340;
    dw 72;
    dw 648;
    dw 340;
    dw 652;
    dw 656;
    dw 340;
    dw 660;
    dw 664;
    dw 340;
    dw 668;
    dw 672;
    dw 340;
    dw 104;
    dw 680;
    dw 340;
    dw 684;
    dw 688;
    dw 340;
    dw 692;
    dw 696;
    dw 340;
    dw 700;
    dw 704;
    dw 340;
    dw 708;
    dw 712;
    dw 340;
    dw 716;
    dw 720;
    dw 340;
    dw 724;
    dw 728;
    dw 736;
    dw 644;
    dw 612;
    dw 352;
    dw 676;
    dw 740;
    dw 744;
    dw 732;
    dw 740;
    dw 428;
    dw 588;
    dw 752;
    dw 416;
    dw 748;
    dw 756;
    dw 316;
    dw 108;
    dw 768;
    dw 124;
    dw 116;
    dw 784;
    dw 784;
    dw 764;
    dw 788;
    dw 792;
    dw 776;
    dw 788;
    dw 128;
    dw 120;
    dw 796;
    dw 796;
    dw 764;
    dw 800;
    dw 804;
    dw 780;
    dw 800;
    dw 316;
    dw 148;
    dw 816;
    dw 828;
    dw 824;
    dw 812;
    dw 140;
    dw 132;
    dw 836;
    dw 836;
    dw 764;
    dw 840;
    dw 844;
    dw 776;
    dw 840;
    dw 144;
    dw 136;
    dw 848;
    dw 848;
    dw 764;
    dw 852;
    dw 856;
    dw 780;
    dw 852;
    dw 316;
    dw 156;
    dw 868;
    dw 880;
    dw 876;
    dw 864;
    dw 888;
    dw 864;
    dw 900;
    dw 904;
    dw 896;
    dw 900;
    dw 892;
    dw 864;
    dw 908;
    dw 912;
    dw 876;
    dw 908;
    dw 316;
    dw 164;
    dw 920;
    dw 932;
    dw 928;
    dw 916;
    dw 188;
    dw 188;
    dw 944;
    dw 944;
    dw 188;
    dw 948;
    dw 188;
    dw 832;
    dw 952;
    dw 944;
    dw 884;
    dw 956;
    dw 948;
    dw 940;
    dw 964;
}
