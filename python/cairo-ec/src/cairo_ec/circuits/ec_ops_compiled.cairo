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
    assert [range_check96_ptr + 124] = x_g.d0;
    assert [range_check96_ptr + 125] = x_g.d1;
    assert [range_check96_ptr + 126] = x_g.d2;
    assert [range_check96_ptr + 127] = x_g.d3;
    assert [range_check96_ptr + 128] = y_g.d0;
    assert [range_check96_ptr + 129] = y_g.d1;
    assert [range_check96_ptr + 130] = y_g.d2;
    assert [range_check96_ptr + 131] = y_g.d3;
    assert [range_check96_ptr + 132] = x_r.d0;
    assert [range_check96_ptr + 133] = x_r.d1;
    assert [range_check96_ptr + 134] = x_r.d2;
    assert [range_check96_ptr + 135] = x_r.d3;
    assert [range_check96_ptr + 136] = y_r.d0;
    assert [range_check96_ptr + 137] = y_r.d1;
    assert [range_check96_ptr + 138] = y_r.d2;
    assert [range_check96_ptr + 139] = y_r.d3;
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
    assert [range_check96_ptr + 204] = x_q_low.d0;
    assert [range_check96_ptr + 205] = x_q_low.d1;
    assert [range_check96_ptr + 206] = x_q_low.d2;
    assert [range_check96_ptr + 207] = x_q_low.d3;
    assert [range_check96_ptr + 208] = y_q_low.d0;
    assert [range_check96_ptr + 209] = y_q_low.d1;
    assert [range_check96_ptr + 210] = y_q_low.d2;
    assert [range_check96_ptr + 211] = y_q_low.d3;
    assert [range_check96_ptr + 212] = x_q_high.d0;
    assert [range_check96_ptr + 213] = x_q_high.d1;
    assert [range_check96_ptr + 214] = x_q_high.d2;
    assert [range_check96_ptr + 215] = x_q_high.d3;
    assert [range_check96_ptr + 216] = y_q_high.d0;
    assert [range_check96_ptr + 217] = y_q_high.d1;
    assert [range_check96_ptr + 218] = y_q_high.d2;
    assert [range_check96_ptr + 219] = y_q_high.d3;
    assert [range_check96_ptr + 220] = x_q_high_shifted.d0;
    assert [range_check96_ptr + 221] = x_q_high_shifted.d1;
    assert [range_check96_ptr + 222] = x_q_high_shifted.d2;
    assert [range_check96_ptr + 223] = x_q_high_shifted.d3;
    assert [range_check96_ptr + 224] = y_q_high_shifted.d0;
    assert [range_check96_ptr + 225] = y_q_high_shifted.d1;
    assert [range_check96_ptr + 226] = y_q_high_shifted.d2;
    assert [range_check96_ptr + 227] = y_q_high_shifted.d3;
    assert [range_check96_ptr + 228] = x_a0.d0;
    assert [range_check96_ptr + 229] = x_a0.d1;
    assert [range_check96_ptr + 230] = x_a0.d2;
    assert [range_check96_ptr + 231] = x_a0.d3;
    assert [range_check96_ptr + 232] = y_a0.d0;
    assert [range_check96_ptr + 233] = y_a0.d1;
    assert [range_check96_ptr + 234] = y_a0.d2;
    assert [range_check96_ptr + 235] = y_a0.d3;
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
        add_mod_n=121,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=122,
    );

    let range_check96_ptr = range_check96_ptr + 1204;

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
    dw 16;
    dw 8;
    dw 312;
    dw 320;
    dw 236;
    dw 324;
    dw 16;
    dw 12;
    dw 328;
    dw 344;
    dw 340;
    dw 232;
    dw 16;
    dw 12;
    dw 352;
    dw 360;
    dw 356;
    dw 348;
    dw 16;
    dw 16;
    dw 364;
    dw 368;
    dw 360;
    dw 228;
    dw 376;
    dw 232;
    dw 372;
    dw 380;
    dw 376;
    dw 364;
    dw 384;
    dw 232;
    dw 380;
    dw 388;
    dw 228;
    dw 360;
    dw 16;
    dw 12;
    dw 396;
    dw 404;
    dw 360;
    dw 228;
    dw 16;
    dw 8;
    dw 412;
    dw 420;
    dw 236;
    dw 424;
    dw 16;
    dw 12;
    dw 428;
    dw 440;
    dw 436;
    dw 424;
    dw 16;
    dw 12;
    dw 448;
    dw 444;
    dw 452;
    dw 456;
    dw 32;
    dw 460;
    dw 464;
    dw 28;
    dw 468;
    dw 472;
    dw 24;
    dw 476;
    dw 480;
    dw 20;
    dw 484;
    dw 488;
    dw 56;
    dw 492;
    dw 496;
    dw 52;
    dw 500;
    dw 504;
    dw 48;
    dw 508;
    dw 512;
    dw 44;
    dw 516;
    dw 520;
    dw 40;
    dw 524;
    dw 528;
    dw 80;
    dw 532;
    dw 536;
    dw 76;
    dw 540;
    dw 544;
    dw 72;
    dw 548;
    dw 552;
    dw 68;
    dw 556;
    dw 560;
    dw 64;
    dw 564;
    dw 568;
    dw 116;
    dw 572;
    dw 576;
    dw 112;
    dw 580;
    dw 584;
    dw 108;
    dw 588;
    dw 592;
    dw 104;
    dw 596;
    dw 600;
    dw 100;
    dw 604;
    dw 608;
    dw 96;
    dw 612;
    dw 616;
    dw 92;
    dw 620;
    dw 624;
    dw 88;
    dw 628;
    dw 632;
    dw 636;
    dw 644;
    dw 648;
    dw 32;
    dw 652;
    dw 656;
    dw 28;
    dw 660;
    dw 664;
    dw 24;
    dw 668;
    dw 672;
    dw 20;
    dw 676;
    dw 680;
    dw 56;
    dw 684;
    dw 688;
    dw 52;
    dw 692;
    dw 696;
    dw 48;
    dw 700;
    dw 704;
    dw 44;
    dw 708;
    dw 712;
    dw 40;
    dw 716;
    dw 720;
    dw 80;
    dw 724;
    dw 728;
    dw 76;
    dw 732;
    dw 736;
    dw 72;
    dw 740;
    dw 744;
    dw 68;
    dw 748;
    dw 752;
    dw 64;
    dw 756;
    dw 760;
    dw 116;
    dw 764;
    dw 768;
    dw 112;
    dw 772;
    dw 776;
    dw 108;
    dw 780;
    dw 784;
    dw 104;
    dw 788;
    dw 792;
    dw 100;
    dw 796;
    dw 800;
    dw 96;
    dw 804;
    dw 808;
    dw 92;
    dw 812;
    dw 816;
    dw 88;
    dw 820;
    dw 824;
    dw 828;
    dw 836;
    dw 840;
    dw 852;
    dw 848;
    dw 844;
    dw 856;
    dw 124;
    dw 228;
    dw 860;
    dw 344;
    dw 864;
    dw 868;
    dw 864;
    dw 128;
    dw 16;
    dw 16;
    dw 872;
    dw 876;
    dw 128;
    dw 872;
    dw 880;
    dw 864;
    dw 876;
    dw 892;
    dw 904;
    dw 908;
    dw 912;
    dw 132;
    dw 228;
    dw 916;
    dw 344;
    dw 920;
    dw 924;
    dw 920;
    dw 136;
    dw 16;
    dw 16;
    dw 928;
    dw 932;
    dw 136;
    dw 928;
    dw 936;
    dw 920;
    dw 932;
    dw 948;
    dw 960;
    dw 964;
    dw 968;
    dw 204;
    dw 228;
    dw 972;
    dw 344;
    dw 976;
    dw 16;
    dw 16;
    dw 980;
    dw 984;
    dw 208;
    dw 980;
    dw 988;
    dw 976;
    dw 984;
    dw 908;
    dw 964;
    dw 996;
    dw 996;
    dw 992;
    dw 1000;
    dw 1012;
    dw 1024;
    dw 1028;
    dw 1040;
    dw 1052;
    dw 1056;
    dw 1060;
    dw 212;
    dw 228;
    dw 1064;
    dw 344;
    dw 1068;
    dw 16;
    dw 16;
    dw 1072;
    dw 1076;
    dw 216;
    dw 1072;
    dw 1080;
    dw 1068;
    dw 1076;
    dw 1028;
    dw 1056;
    dw 1088;
    dw 1088;
    dw 1084;
    dw 1092;
    dw 16;
    dw 4;
    dw 1096;
    dw 16;
    dw 0;
    dw 1100;
    dw 1104;
    dw 1068;
    dw 216;
    dw 16;
    dw 16;
    dw 1108;
    dw 1112;
    dw 1096;
    dw 1108;
    dw 16;
    dw 16;
    dw 1124;
    dw 1128;
    dw 1100;
    dw 1124;
    dw 1140;
    dw 220;
    dw 228;
    dw 1144;
    dw 344;
    dw 1148;
    dw 16;
    dw 16;
    dw 1152;
    dw 1156;
    dw 224;
    dw 1152;
    dw 1160;
    dw 1148;
    dw 1156;
    dw 1120;
    dw 1136;
    dw 1168;
    dw 1168;
    dw 1164;
    dw 1172;
    dw 1184;
    dw 1188;
    dw 1192;
    dw 1192;
    dw 1196;
    dw 1200;
    dw 16;
    dw 1200;
    dw 852;

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
    dw 312;
    dw 228;
    dw 316;
    dw 316;
    dw 228;
    dw 320;
    dw 328;
    dw 232;
    dw 332;
    dw 336;
    dw 332;
    dw 324;
    dw 228;
    dw 336;
    dw 340;
    dw 336;
    dw 336;
    dw 348;
    dw 352;
    dw 228;
    dw 356;
    dw 336;
    dw 368;
    dw 372;
    dw 392;
    dw 388;
    dw 384;
    dw 396;
    dw 380;
    dw 400;
    dw 400;
    dw 404;
    dw 408;
    dw 412;
    dw 360;
    dw 416;
    dw 416;
    dw 360;
    dw 420;
    dw 428;
    dw 392;
    dw 432;
    dw 432;
    dw 380;
    dw 436;
    dw 444;
    dw 440;
    dw 408;
    dw 448;
    dw 392;
    dw 452;
    dw 228;
    dw 36;
    dw 460;
    dw 228;
    dw 464;
    dw 468;
    dw 228;
    dw 472;
    dw 476;
    dw 228;
    dw 480;
    dw 484;
    dw 228;
    dw 60;
    dw 492;
    dw 228;
    dw 496;
    dw 500;
    dw 228;
    dw 504;
    dw 508;
    dw 228;
    dw 512;
    dw 516;
    dw 228;
    dw 520;
    dw 524;
    dw 228;
    dw 84;
    dw 532;
    dw 228;
    dw 536;
    dw 540;
    dw 228;
    dw 544;
    dw 548;
    dw 228;
    dw 552;
    dw 556;
    dw 228;
    dw 560;
    dw 564;
    dw 228;
    dw 120;
    dw 572;
    dw 228;
    dw 576;
    dw 580;
    dw 228;
    dw 584;
    dw 588;
    dw 228;
    dw 592;
    dw 596;
    dw 228;
    dw 600;
    dw 604;
    dw 228;
    dw 608;
    dw 612;
    dw 228;
    dw 616;
    dw 620;
    dw 228;
    dw 624;
    dw 628;
    dw 636;
    dw 528;
    dw 488;
    dw 232;
    dw 568;
    dw 640;
    dw 644;
    dw 632;
    dw 640;
    dw 360;
    dw 36;
    dw 652;
    dw 360;
    dw 656;
    dw 660;
    dw 360;
    dw 664;
    dw 668;
    dw 360;
    dw 672;
    dw 676;
    dw 360;
    dw 60;
    dw 684;
    dw 360;
    dw 688;
    dw 692;
    dw 360;
    dw 696;
    dw 700;
    dw 360;
    dw 704;
    dw 708;
    dw 360;
    dw 712;
    dw 716;
    dw 360;
    dw 84;
    dw 724;
    dw 360;
    dw 728;
    dw 732;
    dw 360;
    dw 736;
    dw 740;
    dw 360;
    dw 744;
    dw 748;
    dw 360;
    dw 752;
    dw 756;
    dw 360;
    dw 120;
    dw 764;
    dw 360;
    dw 768;
    dw 772;
    dw 360;
    dw 776;
    dw 780;
    dw 360;
    dw 784;
    dw 788;
    dw 360;
    dw 792;
    dw 796;
    dw 360;
    dw 800;
    dw 804;
    dw 360;
    dw 808;
    dw 812;
    dw 360;
    dw 816;
    dw 820;
    dw 828;
    dw 720;
    dw 680;
    dw 380;
    dw 760;
    dw 832;
    dw 836;
    dw 824;
    dw 832;
    dw 456;
    dw 648;
    dw 844;
    dw 444;
    dw 840;
    dw 848;
    dw 336;
    dw 124;
    dw 860;
    dw 148;
    dw 140;
    dw 884;
    dw 884;
    dw 856;
    dw 888;
    dw 892;
    dw 868;
    dw 888;
    dw 152;
    dw 144;
    dw 896;
    dw 896;
    dw 856;
    dw 900;
    dw 904;
    dw 880;
    dw 900;
    dw 336;
    dw 132;
    dw 916;
    dw 164;
    dw 156;
    dw 940;
    dw 940;
    dw 912;
    dw 944;
    dw 948;
    dw 924;
    dw 944;
    dw 168;
    dw 160;
    dw 952;
    dw 952;
    dw 912;
    dw 956;
    dw 960;
    dw 936;
    dw 956;
    dw 336;
    dw 204;
    dw 972;
    dw 992;
    dw 988;
    dw 968;
    dw 180;
    dw 172;
    dw 1004;
    dw 1004;
    dw 856;
    dw 1008;
    dw 1012;
    dw 868;
    dw 1008;
    dw 184;
    dw 176;
    dw 1016;
    dw 1016;
    dw 856;
    dw 1020;
    dw 1024;
    dw 880;
    dw 1020;
    dw 196;
    dw 188;
    dw 1032;
    dw 1032;
    dw 912;
    dw 1036;
    dw 1040;
    dw 924;
    dw 1036;
    dw 200;
    dw 192;
    dw 1044;
    dw 1044;
    dw 912;
    dw 1048;
    dw 1052;
    dw 936;
    dw 1048;
    dw 336;
    dw 212;
    dw 1064;
    dw 1084;
    dw 1080;
    dw 1060;
    dw 1112;
    dw 1060;
    dw 1116;
    dw 1120;
    dw 1104;
    dw 1116;
    dw 1128;
    dw 1060;
    dw 1132;
    dw 1136;
    dw 1080;
    dw 1132;
    dw 336;
    dw 220;
    dw 1144;
    dw 1164;
    dw 1160;
    dw 1140;
    dw 244;
    dw 244;
    dw 1176;
    dw 1176;
    dw 244;
    dw 1180;
    dw 244;
    dw 1000;
    dw 1184;
    dw 1176;
    dw 1092;
    dw 1188;
    dw 1180;
    dw 1172;
    dw 1196;
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
    x_g: UInt384*,
    y_g: UInt384*,
    ep1_low: UInt384*,
    en1_low: UInt384*,
    sp1_low: UInt384*,
    sn1_low: UInt384*,
    ep1_high: UInt384*,
    en1_high: UInt384*,
    sp1_high: UInt384*,
    sn1_high: UInt384*,
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
    assert [range_check96_ptr + 108] = x_g.d0;
    assert [range_check96_ptr + 109] = x_g.d1;
    assert [range_check96_ptr + 110] = x_g.d2;
    assert [range_check96_ptr + 111] = x_g.d3;
    assert [range_check96_ptr + 112] = y_g.d0;
    assert [range_check96_ptr + 113] = y_g.d1;
    assert [range_check96_ptr + 114] = y_g.d2;
    assert [range_check96_ptr + 115] = y_g.d3;
    assert [range_check96_ptr + 116] = ep1_low.d0;
    assert [range_check96_ptr + 117] = ep1_low.d1;
    assert [range_check96_ptr + 118] = ep1_low.d2;
    assert [range_check96_ptr + 119] = ep1_low.d3;
    assert [range_check96_ptr + 120] = en1_low.d0;
    assert [range_check96_ptr + 121] = en1_low.d1;
    assert [range_check96_ptr + 122] = en1_low.d2;
    assert [range_check96_ptr + 123] = en1_low.d3;
    assert [range_check96_ptr + 124] = sp1_low.d0;
    assert [range_check96_ptr + 125] = sp1_low.d1;
    assert [range_check96_ptr + 126] = sp1_low.d2;
    assert [range_check96_ptr + 127] = sp1_low.d3;
    assert [range_check96_ptr + 128] = sn1_low.d0;
    assert [range_check96_ptr + 129] = sn1_low.d1;
    assert [range_check96_ptr + 130] = sn1_low.d2;
    assert [range_check96_ptr + 131] = sn1_low.d3;
    assert [range_check96_ptr + 132] = ep1_high.d0;
    assert [range_check96_ptr + 133] = ep1_high.d1;
    assert [range_check96_ptr + 134] = ep1_high.d2;
    assert [range_check96_ptr + 135] = ep1_high.d3;
    assert [range_check96_ptr + 136] = en1_high.d0;
    assert [range_check96_ptr + 137] = en1_high.d1;
    assert [range_check96_ptr + 138] = en1_high.d2;
    assert [range_check96_ptr + 139] = en1_high.d3;
    assert [range_check96_ptr + 140] = sp1_high.d0;
    assert [range_check96_ptr + 141] = sp1_high.d1;
    assert [range_check96_ptr + 142] = sp1_high.d2;
    assert [range_check96_ptr + 143] = sp1_high.d3;
    assert [range_check96_ptr + 144] = sn1_high.d0;
    assert [range_check96_ptr + 145] = sn1_high.d1;
    assert [range_check96_ptr + 146] = sn1_high.d2;
    assert [range_check96_ptr + 147] = sn1_high.d3;
    assert [range_check96_ptr + 148] = x_q_low.d0;
    assert [range_check96_ptr + 149] = x_q_low.d1;
    assert [range_check96_ptr + 150] = x_q_low.d2;
    assert [range_check96_ptr + 151] = x_q_low.d3;
    assert [range_check96_ptr + 152] = y_q_low.d0;
    assert [range_check96_ptr + 153] = y_q_low.d1;
    assert [range_check96_ptr + 154] = y_q_low.d2;
    assert [range_check96_ptr + 155] = y_q_low.d3;
    assert [range_check96_ptr + 156] = x_q_high.d0;
    assert [range_check96_ptr + 157] = x_q_high.d1;
    assert [range_check96_ptr + 158] = x_q_high.d2;
    assert [range_check96_ptr + 159] = x_q_high.d3;
    assert [range_check96_ptr + 160] = y_q_high.d0;
    assert [range_check96_ptr + 161] = y_q_high.d1;
    assert [range_check96_ptr + 162] = y_q_high.d2;
    assert [range_check96_ptr + 163] = y_q_high.d3;
    assert [range_check96_ptr + 164] = x_q_high_shifted.d0;
    assert [range_check96_ptr + 165] = x_q_high_shifted.d1;
    assert [range_check96_ptr + 166] = x_q_high_shifted.d2;
    assert [range_check96_ptr + 167] = x_q_high_shifted.d3;
    assert [range_check96_ptr + 168] = y_q_high_shifted.d0;
    assert [range_check96_ptr + 169] = y_q_high_shifted.d1;
    assert [range_check96_ptr + 170] = y_q_high_shifted.d2;
    assert [range_check96_ptr + 171] = y_q_high_shifted.d3;
    assert [range_check96_ptr + 172] = x_a0.d0;
    assert [range_check96_ptr + 173] = x_a0.d1;
    assert [range_check96_ptr + 174] = x_a0.d2;
    assert [range_check96_ptr + 175] = x_a0.d3;
    assert [range_check96_ptr + 176] = y_a0.d0;
    assert [range_check96_ptr + 177] = y_a0.d1;
    assert [range_check96_ptr + 178] = y_a0.d2;
    assert [range_check96_ptr + 179] = y_a0.d3;
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
        add_mod_n=100,
        mul_mod_offsets_ptr=mul_mod_offsets_ptr,
        mul_mod_n=97,
    );

    let range_check96_ptr = range_check96_ptr + 968;

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
    dw 16;
    dw 8;
    dw 232;
    dw 240;
    dw 180;
    dw 244;
    dw 16;
    dw 12;
    dw 248;
    dw 264;
    dw 260;
    dw 176;
    dw 16;
    dw 12;
    dw 272;
    dw 280;
    dw 276;
    dw 268;
    dw 16;
    dw 16;
    dw 284;
    dw 288;
    dw 280;
    dw 172;
    dw 296;
    dw 176;
    dw 292;
    dw 300;
    dw 296;
    dw 284;
    dw 304;
    dw 176;
    dw 300;
    dw 308;
    dw 172;
    dw 280;
    dw 16;
    dw 12;
    dw 316;
    dw 324;
    dw 280;
    dw 172;
    dw 16;
    dw 8;
    dw 332;
    dw 340;
    dw 180;
    dw 344;
    dw 16;
    dw 12;
    dw 348;
    dw 360;
    dw 356;
    dw 344;
    dw 16;
    dw 12;
    dw 368;
    dw 364;
    dw 372;
    dw 376;
    dw 28;
    dw 380;
    dw 384;
    dw 24;
    dw 388;
    dw 392;
    dw 20;
    dw 396;
    dw 400;
    dw 48;
    dw 404;
    dw 408;
    dw 44;
    dw 412;
    dw 416;
    dw 40;
    dw 420;
    dw 424;
    dw 36;
    dw 428;
    dw 432;
    dw 68;
    dw 436;
    dw 440;
    dw 64;
    dw 444;
    dw 448;
    dw 60;
    dw 452;
    dw 456;
    dw 56;
    dw 460;
    dw 464;
    dw 100;
    dw 468;
    dw 472;
    dw 96;
    dw 476;
    dw 480;
    dw 92;
    dw 484;
    dw 488;
    dw 88;
    dw 492;
    dw 496;
    dw 84;
    dw 500;
    dw 504;
    dw 80;
    dw 508;
    dw 512;
    dw 76;
    dw 516;
    dw 520;
    dw 524;
    dw 532;
    dw 536;
    dw 28;
    dw 540;
    dw 544;
    dw 24;
    dw 548;
    dw 552;
    dw 20;
    dw 556;
    dw 560;
    dw 48;
    dw 564;
    dw 568;
    dw 44;
    dw 572;
    dw 576;
    dw 40;
    dw 580;
    dw 584;
    dw 36;
    dw 588;
    dw 592;
    dw 68;
    dw 596;
    dw 600;
    dw 64;
    dw 604;
    dw 608;
    dw 60;
    dw 612;
    dw 616;
    dw 56;
    dw 620;
    dw 624;
    dw 100;
    dw 628;
    dw 632;
    dw 96;
    dw 636;
    dw 640;
    dw 92;
    dw 644;
    dw 648;
    dw 88;
    dw 652;
    dw 656;
    dw 84;
    dw 660;
    dw 664;
    dw 80;
    dw 668;
    dw 672;
    dw 76;
    dw 676;
    dw 680;
    dw 684;
    dw 692;
    dw 696;
    dw 708;
    dw 704;
    dw 700;
    dw 712;
    dw 108;
    dw 172;
    dw 716;
    dw 264;
    dw 720;
    dw 724;
    dw 720;
    dw 112;
    dw 16;
    dw 16;
    dw 728;
    dw 732;
    dw 112;
    dw 728;
    dw 736;
    dw 720;
    dw 732;
    dw 748;
    dw 760;
    dw 764;
    dw 768;
    dw 148;
    dw 172;
    dw 772;
    dw 264;
    dw 776;
    dw 16;
    dw 16;
    dw 780;
    dw 784;
    dw 152;
    dw 780;
    dw 788;
    dw 776;
    dw 784;
    dw 764;
    dw 792;
    dw 796;
    dw 808;
    dw 820;
    dw 824;
    dw 828;
    dw 156;
    dw 172;
    dw 832;
    dw 264;
    dw 836;
    dw 16;
    dw 16;
    dw 840;
    dw 844;
    dw 160;
    dw 840;
    dw 848;
    dw 836;
    dw 844;
    dw 824;
    dw 852;
    dw 856;
    dw 16;
    dw 4;
    dw 860;
    dw 16;
    dw 0;
    dw 864;
    dw 868;
    dw 836;
    dw 160;
    dw 16;
    dw 16;
    dw 872;
    dw 876;
    dw 860;
    dw 872;
    dw 16;
    dw 16;
    dw 888;
    dw 892;
    dw 864;
    dw 888;
    dw 904;
    dw 164;
    dw 172;
    dw 908;
    dw 264;
    dw 912;
    dw 16;
    dw 16;
    dw 916;
    dw 920;
    dw 168;
    dw 916;
    dw 924;
    dw 912;
    dw 920;
    dw 884;
    dw 900;
    dw 932;
    dw 932;
    dw 928;
    dw 936;
    dw 948;
    dw 952;
    dw 956;
    dw 956;
    dw 960;
    dw 964;
    dw 16;
    dw 964;
    dw 708;

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
    dw 232;
    dw 172;
    dw 236;
    dw 236;
    dw 172;
    dw 240;
    dw 248;
    dw 176;
    dw 252;
    dw 256;
    dw 252;
    dw 244;
    dw 172;
    dw 256;
    dw 260;
    dw 256;
    dw 256;
    dw 268;
    dw 272;
    dw 172;
    dw 276;
    dw 256;
    dw 288;
    dw 292;
    dw 312;
    dw 308;
    dw 304;
    dw 316;
    dw 300;
    dw 320;
    dw 320;
    dw 324;
    dw 328;
    dw 332;
    dw 280;
    dw 336;
    dw 336;
    dw 280;
    dw 340;
    dw 348;
    dw 312;
    dw 352;
    dw 352;
    dw 300;
    dw 356;
    dw 364;
    dw 360;
    dw 328;
    dw 368;
    dw 312;
    dw 372;
    dw 172;
    dw 32;
    dw 380;
    dw 172;
    dw 384;
    dw 388;
    dw 172;
    dw 392;
    dw 396;
    dw 172;
    dw 52;
    dw 404;
    dw 172;
    dw 408;
    dw 412;
    dw 172;
    dw 416;
    dw 420;
    dw 172;
    dw 424;
    dw 428;
    dw 172;
    dw 72;
    dw 436;
    dw 172;
    dw 440;
    dw 444;
    dw 172;
    dw 448;
    dw 452;
    dw 172;
    dw 456;
    dw 460;
    dw 172;
    dw 104;
    dw 468;
    dw 172;
    dw 472;
    dw 476;
    dw 172;
    dw 480;
    dw 484;
    dw 172;
    dw 488;
    dw 492;
    dw 172;
    dw 496;
    dw 500;
    dw 172;
    dw 504;
    dw 508;
    dw 172;
    dw 512;
    dw 516;
    dw 524;
    dw 432;
    dw 400;
    dw 176;
    dw 464;
    dw 528;
    dw 532;
    dw 520;
    dw 528;
    dw 280;
    dw 32;
    dw 540;
    dw 280;
    dw 544;
    dw 548;
    dw 280;
    dw 552;
    dw 556;
    dw 280;
    dw 52;
    dw 564;
    dw 280;
    dw 568;
    dw 572;
    dw 280;
    dw 576;
    dw 580;
    dw 280;
    dw 584;
    dw 588;
    dw 280;
    dw 72;
    dw 596;
    dw 280;
    dw 600;
    dw 604;
    dw 280;
    dw 608;
    dw 612;
    dw 280;
    dw 616;
    dw 620;
    dw 280;
    dw 104;
    dw 628;
    dw 280;
    dw 632;
    dw 636;
    dw 280;
    dw 640;
    dw 644;
    dw 280;
    dw 648;
    dw 652;
    dw 280;
    dw 656;
    dw 660;
    dw 280;
    dw 664;
    dw 668;
    dw 280;
    dw 672;
    dw 676;
    dw 684;
    dw 592;
    dw 560;
    dw 300;
    dw 624;
    dw 688;
    dw 692;
    dw 680;
    dw 688;
    dw 376;
    dw 536;
    dw 700;
    dw 364;
    dw 696;
    dw 704;
    dw 256;
    dw 108;
    dw 716;
    dw 124;
    dw 116;
    dw 740;
    dw 740;
    dw 712;
    dw 744;
    dw 748;
    dw 724;
    dw 744;
    dw 128;
    dw 120;
    dw 752;
    dw 752;
    dw 712;
    dw 756;
    dw 760;
    dw 736;
    dw 756;
    dw 256;
    dw 148;
    dw 772;
    dw 792;
    dw 788;
    dw 768;
    dw 140;
    dw 132;
    dw 800;
    dw 800;
    dw 712;
    dw 804;
    dw 808;
    dw 724;
    dw 804;
    dw 144;
    dw 136;
    dw 812;
    dw 812;
    dw 712;
    dw 816;
    dw 820;
    dw 736;
    dw 816;
    dw 256;
    dw 156;
    dw 832;
    dw 852;
    dw 848;
    dw 828;
    dw 876;
    dw 828;
    dw 880;
    dw 884;
    dw 868;
    dw 880;
    dw 892;
    dw 828;
    dw 896;
    dw 900;
    dw 848;
    dw 896;
    dw 256;
    dw 164;
    dw 908;
    dw 928;
    dw 924;
    dw 904;
    dw 188;
    dw 188;
    dw 940;
    dw 940;
    dw 188;
    dw 944;
    dw 188;
    dw 796;
    dw 948;
    dw 940;
    dw 856;
    dw 952;
    dw 944;
    dw 936;
    dw 960;
}
