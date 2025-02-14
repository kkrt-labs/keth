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

func ecip_2P{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
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
    x_g: UInt384*,
    y_g: UInt384*,
    x_r: UInt384*,
    y_r: UInt384*,
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
    x_q_low: UInt384*,
    y_q_low: UInt384*,
    x_q_high: UInt384*,
    y_q_high: UInt384*,
    x_q_high_shifted: UInt384*,
    y_q_high_shifted: UInt384*,
    x_a0: UInt384*,
    y_a0: UInt384*,
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
    assert [range_check96_ptr + 20] = 0;
    assert [range_check96_ptr + 21] = 0;
    assert [range_check96_ptr + 22] = 576460752303423505;
    assert [range_check96_ptr + 23] = 0;

    assert [range_check96_ptr + 24] = div_a_coeff_0.d0;
    assert [range_check96_ptr + 25] = div_a_coeff_0.d1;
    assert [range_check96_ptr + 26] = div_a_coeff_0.d2;
    assert [range_check96_ptr + 27] = div_a_coeff_0.d3;
    assert [range_check96_ptr + 28] = div_a_coeff_1.d0;
    assert [range_check96_ptr + 29] = div_a_coeff_1.d1;
    assert [range_check96_ptr + 30] = div_a_coeff_1.d2;
    assert [range_check96_ptr + 31] = div_a_coeff_1.d3;
    assert [range_check96_ptr + 32] = div_a_coeff_2.d0;
    assert [range_check96_ptr + 33] = div_a_coeff_2.d1;
    assert [range_check96_ptr + 34] = div_a_coeff_2.d2;
    assert [range_check96_ptr + 35] = div_a_coeff_2.d3;
    assert [range_check96_ptr + 36] = div_a_coeff_3.d0;
    assert [range_check96_ptr + 37] = div_a_coeff_3.d1;
    assert [range_check96_ptr + 38] = div_a_coeff_3.d2;
    assert [range_check96_ptr + 39] = div_a_coeff_3.d3;
    assert [range_check96_ptr + 40] = div_a_coeff_4.d0;
    assert [range_check96_ptr + 41] = div_a_coeff_4.d1;
    assert [range_check96_ptr + 42] = div_a_coeff_4.d2;
    assert [range_check96_ptr + 43] = div_a_coeff_4.d3;
    assert [range_check96_ptr + 44] = div_b_coeff_0.d0;
    assert [range_check96_ptr + 45] = div_b_coeff_0.d1;
    assert [range_check96_ptr + 46] = div_b_coeff_0.d2;
    assert [range_check96_ptr + 47] = div_b_coeff_0.d3;
    assert [range_check96_ptr + 48] = div_b_coeff_1.d0;
    assert [range_check96_ptr + 49] = div_b_coeff_1.d1;
    assert [range_check96_ptr + 50] = div_b_coeff_1.d2;
    assert [range_check96_ptr + 51] = div_b_coeff_1.d3;
    assert [range_check96_ptr + 52] = div_b_coeff_2.d0;
    assert [range_check96_ptr + 53] = div_b_coeff_2.d1;
    assert [range_check96_ptr + 54] = div_b_coeff_2.d2;
    assert [range_check96_ptr + 55] = div_b_coeff_2.d3;
    assert [range_check96_ptr + 56] = div_b_coeff_3.d0;
    assert [range_check96_ptr + 57] = div_b_coeff_3.d1;
    assert [range_check96_ptr + 58] = div_b_coeff_3.d2;
    assert [range_check96_ptr + 59] = div_b_coeff_3.d3;
    assert [range_check96_ptr + 60] = div_b_coeff_4.d0;
    assert [range_check96_ptr + 61] = div_b_coeff_4.d1;
    assert [range_check96_ptr + 62] = div_b_coeff_4.d2;
    assert [range_check96_ptr + 63] = div_b_coeff_4.d3;
    assert [range_check96_ptr + 64] = div_b_coeff_5.d0;
    assert [range_check96_ptr + 65] = div_b_coeff_5.d1;
    assert [range_check96_ptr + 66] = div_b_coeff_5.d2;
    assert [range_check96_ptr + 67] = div_b_coeff_5.d3;
    assert [range_check96_ptr + 68] = div_c_coeff_0.d0;
    assert [range_check96_ptr + 69] = div_c_coeff_0.d1;
    assert [range_check96_ptr + 70] = div_c_coeff_0.d2;
    assert [range_check96_ptr + 71] = div_c_coeff_0.d3;
    assert [range_check96_ptr + 72] = div_c_coeff_1.d0;
    assert [range_check96_ptr + 73] = div_c_coeff_1.d1;
    assert [range_check96_ptr + 74] = div_c_coeff_1.d2;
    assert [range_check96_ptr + 75] = div_c_coeff_1.d3;
    assert [range_check96_ptr + 76] = div_c_coeff_2.d0;
    assert [range_check96_ptr + 77] = div_c_coeff_2.d1;
    assert [range_check96_ptr + 78] = div_c_coeff_2.d2;
    assert [range_check96_ptr + 79] = div_c_coeff_2.d3;
    assert [range_check96_ptr + 80] = div_c_coeff_3.d0;
    assert [range_check96_ptr + 81] = div_c_coeff_3.d1;
    assert [range_check96_ptr + 82] = div_c_coeff_3.d2;
    assert [range_check96_ptr + 83] = div_c_coeff_3.d3;
    assert [range_check96_ptr + 84] = div_c_coeff_4.d0;
    assert [range_check96_ptr + 85] = div_c_coeff_4.d1;
    assert [range_check96_ptr + 86] = div_c_coeff_4.d2;
    assert [range_check96_ptr + 87] = div_c_coeff_4.d3;
    assert [range_check96_ptr + 88] = div_c_coeff_5.d0;
    assert [range_check96_ptr + 89] = div_c_coeff_5.d1;
    assert [range_check96_ptr + 90] = div_c_coeff_5.d2;
    assert [range_check96_ptr + 91] = div_c_coeff_5.d3;
    assert [range_check96_ptr + 92] = div_d_coeff_0.d0;
    assert [range_check96_ptr + 93] = div_d_coeff_0.d1;
    assert [range_check96_ptr + 94] = div_d_coeff_0.d2;
    assert [range_check96_ptr + 95] = div_d_coeff_0.d3;
    assert [range_check96_ptr + 96] = div_d_coeff_1.d0;
    assert [range_check96_ptr + 97] = div_d_coeff_1.d1;
    assert [range_check96_ptr + 98] = div_d_coeff_1.d2;
    assert [range_check96_ptr + 99] = div_d_coeff_1.d3;
    assert [range_check96_ptr + 100] = div_d_coeff_2.d0;
    assert [range_check96_ptr + 101] = div_d_coeff_2.d1;
    assert [range_check96_ptr + 102] = div_d_coeff_2.d2;
    assert [range_check96_ptr + 103] = div_d_coeff_2.d3;
    assert [range_check96_ptr + 104] = div_d_coeff_3.d0;
    assert [range_check96_ptr + 105] = div_d_coeff_3.d1;
    assert [range_check96_ptr + 106] = div_d_coeff_3.d2;
    assert [range_check96_ptr + 107] = div_d_coeff_3.d3;
    assert [range_check96_ptr + 108] = div_d_coeff_4.d0;
    assert [range_check96_ptr + 109] = div_d_coeff_4.d1;
    assert [range_check96_ptr + 110] = div_d_coeff_4.d2;
    assert [range_check96_ptr + 111] = div_d_coeff_4.d3;
    assert [range_check96_ptr + 112] = div_d_coeff_5.d0;
    assert [range_check96_ptr + 113] = div_d_coeff_5.d1;
    assert [range_check96_ptr + 114] = div_d_coeff_5.d2;
    assert [range_check96_ptr + 115] = div_d_coeff_5.d3;
    assert [range_check96_ptr + 116] = div_d_coeff_6.d0;
    assert [range_check96_ptr + 117] = div_d_coeff_6.d1;
    assert [range_check96_ptr + 118] = div_d_coeff_6.d2;
    assert [range_check96_ptr + 119] = div_d_coeff_6.d3;
    assert [range_check96_ptr + 120] = div_d_coeff_7.d0;
    assert [range_check96_ptr + 121] = div_d_coeff_7.d1;
    assert [range_check96_ptr + 122] = div_d_coeff_7.d2;
    assert [range_check96_ptr + 123] = div_d_coeff_7.d3;
    assert [range_check96_ptr + 124] = div_d_coeff_8.d0;
    assert [range_check96_ptr + 125] = div_d_coeff_8.d1;
    assert [range_check96_ptr + 126] = div_d_coeff_8.d2;
    assert [range_check96_ptr + 127] = div_d_coeff_8.d3;
    assert [range_check96_ptr + 128] = x_g.d0;
    assert [range_check96_ptr + 129] = x_g.d1;
    assert [range_check96_ptr + 130] = x_g.d2;
    assert [range_check96_ptr + 131] = x_g.d3;
    assert [range_check96_ptr + 132] = y_g.d0;
    assert [range_check96_ptr + 133] = y_g.d1;
    assert [range_check96_ptr + 134] = y_g.d2;
    assert [range_check96_ptr + 135] = y_g.d3;
    assert [range_check96_ptr + 136] = x_r.d0;
    assert [range_check96_ptr + 137] = x_r.d1;
    assert [range_check96_ptr + 138] = x_r.d2;
    assert [range_check96_ptr + 139] = x_r.d3;
    assert [range_check96_ptr + 140] = y_r.d0;
    assert [range_check96_ptr + 141] = y_r.d1;
    assert [range_check96_ptr + 142] = y_r.d2;
    assert [range_check96_ptr + 143] = y_r.d3;
    assert [range_check96_ptr + 144] = ep1_low.d0;
    assert [range_check96_ptr + 145] = ep1_low.d1;
    assert [range_check96_ptr + 146] = ep1_low.d2;
    assert [range_check96_ptr + 147] = ep1_low.d3;
    assert [range_check96_ptr + 148] = en1_low.d0;
    assert [range_check96_ptr + 149] = en1_low.d1;
    assert [range_check96_ptr + 150] = en1_low.d2;
    assert [range_check96_ptr + 151] = en1_low.d3;
    assert [range_check96_ptr + 152] = sp1_low.d0;
    assert [range_check96_ptr + 153] = sp1_low.d1;
    assert [range_check96_ptr + 154] = sp1_low.d2;
    assert [range_check96_ptr + 155] = sp1_low.d3;
    assert [range_check96_ptr + 156] = sn1_low.d0;
    assert [range_check96_ptr + 157] = sn1_low.d1;
    assert [range_check96_ptr + 158] = sn1_low.d2;
    assert [range_check96_ptr + 159] = sn1_low.d3;
    assert [range_check96_ptr + 160] = ep2_low.d0;
    assert [range_check96_ptr + 161] = ep2_low.d1;
    assert [range_check96_ptr + 162] = ep2_low.d2;
    assert [range_check96_ptr + 163] = ep2_low.d3;
    assert [range_check96_ptr + 164] = en2_low.d0;
    assert [range_check96_ptr + 165] = en2_low.d1;
    assert [range_check96_ptr + 166] = en2_low.d2;
    assert [range_check96_ptr + 167] = en2_low.d3;
    assert [range_check96_ptr + 168] = sp2_low.d0;
    assert [range_check96_ptr + 169] = sp2_low.d1;
    assert [range_check96_ptr + 170] = sp2_low.d2;
    assert [range_check96_ptr + 171] = sp2_low.d3;
    assert [range_check96_ptr + 172] = sn2_low.d0;
    assert [range_check96_ptr + 173] = sn2_low.d1;
    assert [range_check96_ptr + 174] = sn2_low.d2;
    assert [range_check96_ptr + 175] = sn2_low.d3;
    assert [range_check96_ptr + 176] = ep1_high.d0;
    assert [range_check96_ptr + 177] = ep1_high.d1;
    assert [range_check96_ptr + 178] = ep1_high.d2;
    assert [range_check96_ptr + 179] = ep1_high.d3;
    assert [range_check96_ptr + 180] = en1_high.d0;
    assert [range_check96_ptr + 181] = en1_high.d1;
    assert [range_check96_ptr + 182] = en1_high.d2;
    assert [range_check96_ptr + 183] = en1_high.d3;
    assert [range_check96_ptr + 184] = sp1_high.d0;
    assert [range_check96_ptr + 185] = sp1_high.d1;
    assert [range_check96_ptr + 186] = sp1_high.d2;
    assert [range_check96_ptr + 187] = sp1_high.d3;
    assert [range_check96_ptr + 188] = sn1_high.d0;
    assert [range_check96_ptr + 189] = sn1_high.d1;
    assert [range_check96_ptr + 190] = sn1_high.d2;
    assert [range_check96_ptr + 191] = sn1_high.d3;
    assert [range_check96_ptr + 192] = ep2_high.d0;
    assert [range_check96_ptr + 193] = ep2_high.d1;
    assert [range_check96_ptr + 194] = ep2_high.d2;
    assert [range_check96_ptr + 195] = ep2_high.d3;
    assert [range_check96_ptr + 196] = en2_high.d0;
    assert [range_check96_ptr + 197] = en2_high.d1;
    assert [range_check96_ptr + 198] = en2_high.d2;
    assert [range_check96_ptr + 199] = en2_high.d3;
    assert [range_check96_ptr + 200] = sp2_high.d0;
    assert [range_check96_ptr + 201] = sp2_high.d1;
    assert [range_check96_ptr + 202] = sp2_high.d2;
    assert [range_check96_ptr + 203] = sp2_high.d3;
    assert [range_check96_ptr + 204] = sn2_high.d0;
    assert [range_check96_ptr + 205] = sn2_high.d1;
    assert [range_check96_ptr + 206] = sn2_high.d2;
    assert [range_check96_ptr + 207] = sn2_high.d3;
    assert [range_check96_ptr + 208] = x_q_low.d0;
    assert [range_check96_ptr + 209] = x_q_low.d1;
    assert [range_check96_ptr + 210] = x_q_low.d2;
    assert [range_check96_ptr + 211] = x_q_low.d3;
    assert [range_check96_ptr + 212] = y_q_low.d0;
    assert [range_check96_ptr + 213] = y_q_low.d1;
    assert [range_check96_ptr + 214] = y_q_low.d2;
    assert [range_check96_ptr + 215] = y_q_low.d3;
    assert [range_check96_ptr + 216] = x_q_high.d0;
    assert [range_check96_ptr + 217] = x_q_high.d1;
    assert [range_check96_ptr + 218] = x_q_high.d2;
    assert [range_check96_ptr + 219] = x_q_high.d3;
    assert [range_check96_ptr + 220] = y_q_high.d0;
    assert [range_check96_ptr + 221] = y_q_high.d1;
    assert [range_check96_ptr + 222] = y_q_high.d2;
    assert [range_check96_ptr + 223] = y_q_high.d3;
    assert [range_check96_ptr + 224] = x_q_high_shifted.d0;
    assert [range_check96_ptr + 225] = x_q_high_shifted.d1;
    assert [range_check96_ptr + 226] = x_q_high_shifted.d2;
    assert [range_check96_ptr + 227] = x_q_high_shifted.d3;
    assert [range_check96_ptr + 228] = y_q_high_shifted.d0;
    assert [range_check96_ptr + 229] = y_q_high_shifted.d1;
    assert [range_check96_ptr + 230] = y_q_high_shifted.d2;
    assert [range_check96_ptr + 231] = y_q_high_shifted.d3;
    assert [range_check96_ptr + 232] = x_a0.d0;
    assert [range_check96_ptr + 233] = x_a0.d1;
    assert [range_check96_ptr + 234] = x_a0.d2;
    assert [range_check96_ptr + 235] = x_a0.d3;
    assert [range_check96_ptr + 236] = y_a0.d0;
    assert [range_check96_ptr + 237] = y_a0.d1;
    assert [range_check96_ptr + 238] = y_a0.d2;
    assert [range_check96_ptr + 239] = y_a0.d3;
    assert [range_check96_ptr + 240] = a.d0;
    assert [range_check96_ptr + 241] = a.d1;
    assert [range_check96_ptr + 242] = a.d2;
    assert [range_check96_ptr + 243] = a.d3;
    assert [range_check96_ptr + 244] = b.d0;
    assert [range_check96_ptr + 245] = b.d1;
    assert [range_check96_ptr + 246] = b.d2;
    assert [range_check96_ptr + 247] = b.d3;
    assert [range_check96_ptr + 248] = base_rlc.d0;
    assert [range_check96_ptr + 249] = base_rlc.d1;
    assert [range_check96_ptr + 250] = base_rlc.d2;
    assert [range_check96_ptr + 251] = base_rlc.d3;

    run_mod_p_circuit(
        p=[p],
        values_ptr=cast(range_check96_ptr, UInt384*),
        add_mod_offsets_ptr=add_mod_offsets_ptr,
        add_mod_n=98,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=120,
    );

    let range_check96_ptr = range_check96_ptr + 1072;

    return ();

    add_offsets:
    dw 220;
    dw 224;
    dw 228;
    dw 228;
    dw 208;
    dw 232;
    dw 240;
    dw 204;
    dw 244;
    dw 244;
    dw 248;
    dw 252;
    dw 252;
    dw 208;
    dw 256;
    dw 264;
    dw 268;
    dw 272;
    dw 272;
    dw 208;
    dw 276;
    dw 12;
    dw 4;
    dw 280;
    dw 288;
    dw 204;
    dw 292;
    dw 12;
    dw 8;
    dw 296;
    dw 312;
    dw 308;
    dw 200;
    dw 12;
    dw 8;
    dw 320;
    dw 328;
    dw 324;
    dw 316;
    dw 332;
    dw 328;
    dw 196;
    dw 340;
    dw 200;
    dw 336;
    dw 348;
    dw 196;
    dw 324;
    dw 12;
    dw 8;
    dw 356;
    dw 364;
    dw 324;
    dw 196;
    dw 12;
    dw 4;
    dw 372;
    dw 380;
    dw 204;
    dw 384;
    dw 12;
    dw 8;
    dw 388;
    dw 400;
    dw 396;
    dw 384;
    dw 12;
    dw 8;
    dw 408;
    dw 404;
    dw 412;
    dw 416;
    dw 32;
    dw 420;
    dw 424;
    dw 28;
    dw 428;
    dw 432;
    dw 24;
    dw 436;
    dw 440;
    dw 20;
    dw 444;
    dw 448;
    dw 56;
    dw 452;
    dw 456;
    dw 52;
    dw 460;
    dw 464;
    dw 48;
    dw 468;
    dw 472;
    dw 44;
    dw 476;
    dw 480;
    dw 40;
    dw 484;
    dw 488;
    dw 80;
    dw 492;
    dw 496;
    dw 76;
    dw 500;
    dw 504;
    dw 72;
    dw 508;
    dw 512;
    dw 68;
    dw 516;
    dw 520;
    dw 64;
    dw 524;
    dw 528;
    dw 116;
    dw 532;
    dw 536;
    dw 112;
    dw 540;
    dw 544;
    dw 108;
    dw 548;
    dw 552;
    dw 104;
    dw 556;
    dw 560;
    dw 100;
    dw 564;
    dw 568;
    dw 96;
    dw 572;
    dw 576;
    dw 92;
    dw 580;
    dw 584;
    dw 88;
    dw 588;
    dw 592;
    dw 596;
    dw 604;
    dw 608;
    dw 32;
    dw 612;
    dw 616;
    dw 28;
    dw 620;
    dw 624;
    dw 24;
    dw 628;
    dw 632;
    dw 20;
    dw 636;
    dw 640;
    dw 56;
    dw 644;
    dw 648;
    dw 52;
    dw 652;
    dw 656;
    dw 48;
    dw 660;
    dw 664;
    dw 44;
    dw 668;
    dw 672;
    dw 40;
    dw 676;
    dw 680;
    dw 80;
    dw 684;
    dw 688;
    dw 76;
    dw 692;
    dw 696;
    dw 72;
    dw 700;
    dw 704;
    dw 68;
    dw 708;
    dw 712;
    dw 64;
    dw 716;
    dw 720;
    dw 116;
    dw 724;
    dw 728;
    dw 112;
    dw 732;
    dw 736;
    dw 108;
    dw 740;
    dw 744;
    dw 104;
    dw 748;
    dw 752;
    dw 100;
    dw 756;
    dw 760;
    dw 96;
    dw 764;
    dw 768;
    dw 92;
    dw 772;
    dw 776;
    dw 88;
    dw 780;
    dw 784;
    dw 788;
    dw 796;
    dw 800;
    dw 812;
    dw 808;
    dw 804;
    dw 816;
    dw 124;
    dw 196;
    dw 820;
    dw 308;
    dw 824;
    dw 828;
    dw 824;
    dw 128;
    dw 852;
    dw 848;
    dw 840;
    dw 856;
    dw 132;
    dw 196;
    dw 860;
    dw 304;
    dw 864;
    dw 868;
    dw 864;
    dw 136;
    dw 892;
    dw 888;
    dw 880;
    dw 896;
    dw 172;
    dw 196;
    dw 900;
    dw 300;
    dw 904;
    dw 844;
    dw 888;
    dw 916;
    dw 916;
    dw 912;
    dw 920;
    dw 940;
    dw 936;
    dw 928;
    dw 960;
    dw 956;
    dw 948;
    dw 964;
    dw 180;
    dw 196;
    dw 968;
    dw 296;
    dw 972;
    dw 936;
    dw 956;
    dw 984;
    dw 984;
    dw 980;
    dw 988;
    dw 12;
    dw 0;
    dw 992;
    dw 996;
    dw 964;
    dw 184;
    dw 1016;
    dw 188;
    dw 196;
    dw 1020;
    dw 280;
    dw 1024;
    dw 996;
    dw 1008;
    dw 1036;
    dw 1036;
    dw 1032;
    dw 1040;
    dw 1052;
    dw 1056;
    dw 1060;
    dw 1060;
    dw 1064;
    dw 1068;
    dw 12;
    dw 1068;
    dw 780;

    mul_offsets:
    dw 124;
    dw 124;
    dw 216;
    dw 216;
    dw 124;
    dw 220;
    dw 204;
    dw 124;
    dw 224;
    dw 128;
    dw 128;
    dw 232;
    dw 132;
    dw 132;
    dw 236;
    dw 236;
    dw 132;
    dw 240;
    dw 204;
    dw 132;
    dw 248;
    dw 136;
    dw 136;
    dw 256;
    dw 196;
    dw 196;
    dw 260;
    dw 260;
    dw 196;
    dw 264;
    dw 204;
    dw 196;
    dw 268;
    dw 200;
    dw 200;
    dw 276;
    dw 280;
    dw 196;
    dw 284;
    dw 284;
    dw 196;
    dw 288;
    dw 296;
    dw 200;
    dw 300;
    dw 304;
    dw 300;
    dw 292;
    dw 196;
    dw 304;
    dw 308;
    dw 304;
    dw 304;
    dw 316;
    dw 320;
    dw 196;
    dw 324;
    dw 304;
    dw 332;
    dw 336;
    dw 340;
    dw 16;
    dw 344;
    dw 352;
    dw 348;
    dw 344;
    dw 356;
    dw 340;
    dw 360;
    dw 360;
    dw 364;
    dw 368;
    dw 372;
    dw 324;
    dw 376;
    dw 376;
    dw 324;
    dw 380;
    dw 388;
    dw 352;
    dw 392;
    dw 392;
    dw 340;
    dw 396;
    dw 404;
    dw 400;
    dw 368;
    dw 408;
    dw 352;
    dw 412;
    dw 196;
    dw 36;
    dw 420;
    dw 196;
    dw 424;
    dw 428;
    dw 196;
    dw 432;
    dw 436;
    dw 196;
    dw 440;
    dw 444;
    dw 196;
    dw 60;
    dw 452;
    dw 196;
    dw 456;
    dw 460;
    dw 196;
    dw 464;
    dw 468;
    dw 196;
    dw 472;
    dw 476;
    dw 196;
    dw 480;
    dw 484;
    dw 196;
    dw 84;
    dw 492;
    dw 196;
    dw 496;
    dw 500;
    dw 196;
    dw 504;
    dw 508;
    dw 196;
    dw 512;
    dw 516;
    dw 196;
    dw 520;
    dw 524;
    dw 196;
    dw 120;
    dw 532;
    dw 196;
    dw 536;
    dw 540;
    dw 196;
    dw 544;
    dw 548;
    dw 196;
    dw 552;
    dw 556;
    dw 196;
    dw 560;
    dw 564;
    dw 196;
    dw 568;
    dw 572;
    dw 196;
    dw 576;
    dw 580;
    dw 196;
    dw 584;
    dw 588;
    dw 596;
    dw 488;
    dw 448;
    dw 200;
    dw 528;
    dw 600;
    dw 604;
    dw 592;
    dw 600;
    dw 324;
    dw 36;
    dw 612;
    dw 324;
    dw 616;
    dw 620;
    dw 324;
    dw 624;
    dw 628;
    dw 324;
    dw 632;
    dw 636;
    dw 324;
    dw 60;
    dw 644;
    dw 324;
    dw 648;
    dw 652;
    dw 324;
    dw 656;
    dw 660;
    dw 324;
    dw 664;
    dw 668;
    dw 324;
    dw 672;
    dw 676;
    dw 324;
    dw 84;
    dw 684;
    dw 324;
    dw 688;
    dw 692;
    dw 324;
    dw 696;
    dw 700;
    dw 324;
    dw 704;
    dw 708;
    dw 324;
    dw 712;
    dw 716;
    dw 324;
    dw 120;
    dw 724;
    dw 324;
    dw 728;
    dw 732;
    dw 324;
    dw 736;
    dw 740;
    dw 324;
    dw 744;
    dw 748;
    dw 324;
    dw 752;
    dw 756;
    dw 324;
    dw 760;
    dw 764;
    dw 324;
    dw 768;
    dw 772;
    dw 324;
    dw 776;
    dw 780;
    dw 788;
    dw 680;
    dw 640;
    dw 340;
    dw 720;
    dw 792;
    dw 796;
    dw 784;
    dw 792;
    dw 416;
    dw 608;
    dw 804;
    dw 404;
    dw 800;
    dw 808;
    dw 300;
    dw 124;
    dw 820;
    dw 128;
    dw 16;
    dw 832;
    dw 140;
    dw 812;
    dw 836;
    dw 840;
    dw 824;
    dw 836;
    dw 144;
    dw 812;
    dw 844;
    dw 848;
    dw 832;
    dw 844;
    dw 296;
    dw 132;
    dw 860;
    dw 136;
    dw 16;
    dw 872;
    dw 148;
    dw 852;
    dw 876;
    dw 880;
    dw 864;
    dw 876;
    dw 152;
    dw 852;
    dw 884;
    dw 888;
    dw 872;
    dw 884;
    dw 292;
    dw 172;
    dw 900;
    dw 176;
    dw 16;
    dw 908;
    dw 912;
    dw 908;
    dw 892;
    dw 156;
    dw 804;
    dw 924;
    dw 928;
    dw 816;
    dw 924;
    dw 160;
    dw 804;
    dw 932;
    dw 936;
    dw 824;
    dw 932;
    dw 164;
    dw 848;
    dw 944;
    dw 948;
    dw 860;
    dw 944;
    dw 168;
    dw 848;
    dw 952;
    dw 956;
    dw 868;
    dw 952;
    dw 288;
    dw 180;
    dw 968;
    dw 184;
    dw 16;
    dw 976;
    dw 980;
    dw 976;
    dw 960;
    dw 988;
    dw 16;
    dw 1000;
    dw 1004;
    dw 992;
    dw 1000;
    dw 988;
    dw 16;
    dw 1008;
    dw 1012;
    dw 964;
    dw 1008;
    dw 272;
    dw 188;
    dw 1020;
    dw 192;
    dw 16;
    dw 1028;
    dw 1032;
    dw 1028;
    dw 1012;
    dw 212;
    dw 212;
    dw 1044;
    dw 1044;
    dw 212;
    dw 1048;
    dw 212;
    dw 900;
    dw 1052;
    dw 1044;
    dw 972;
    dw 1056;
    dw 1048;
    dw 1040;
    dw 1064;
}
